// Native port of RapidOCR 1.4.4 / PaddleOCR preprocessing and postprocessing.
// Upstream PaddlePaddle Authors: Apache-2.0. See THIRD_PARTY_NOTICES.md.
#include "NativeOCR.hpp"
#include "clipper.hpp"
#include <opencv2/imgproc.hpp>
#include <opencv2/imgcodecs.hpp>
#include <algorithm>
#include <cmath>
#include <numeric>
#include <stdexcept>

namespace photolab {
namespace {
using Box = std::array<cv::Point2f, 4>;
int evenRound(double x) { return static_cast<int>(std::nearbyint(x)); }
float distance(cv::Point2f a, cv::Point2f b) { return static_cast<float>(cv::norm(a-b)); }
Box order(Box points) {
    std::stable_sort(points.begin(), points.end(), [](auto a, auto b) { return a.x < b.x; });
    if (points[0].y > points[1].y) std::swap(points[0], points[1]);
    if (points[2].y > points[3].y) std::swap(points[2], points[3]);
    return {points[0], points[2], points[3], points[1]};
}
template<class Points> std::pair<Box, float> miniBox(const Points& contour) {
    auto rectangle = cv::minAreaRect(contour);
    Box points; rectangle.points(points.data());
    return {order(points), std::min(rectangle.size.width, rectangle.size.height)};
}
Ort::Value infer(Ort::Session& session, std::vector<float>& buffer, const std::array<int64_t,4>& shape) {
    auto memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    auto input = Ort::Value::CreateTensor<float>(memory, buffer.data(), buffer.size(), shape.data(), shape.size());
    Ort::AllocatorWithDefaultOptions allocator;
    auto inName = session.GetInputNameAllocated(0, allocator);
    auto outName = session.GetOutputNameAllocated(0, allocator);
    const char* inputs[] = {inName.get()}; const char* outputs[] = {outName.get()};
    auto values = session.Run(Ort::RunOptions{nullptr}, inputs, &input, 1, outputs, 1);
    return std::move(values[0]);
}
std::vector<float> normalize(const std::vector<cv::Mat>& images, int height, int width, bool detector = false) {
    size_t plane = static_cast<size_t>(height)*width;
    std::vector<float> tensor(images.size()*3*plane, 0);
    for (size_t n = 0; n < images.size(); ++n) {
        int resizedWidth = detector ? width : std::min(width, static_cast<int>(std::ceil(height*images[n].cols/double(images[n].rows))));
        cv::Mat resized; cv::resize(images[n], resized, {resizedWidth,height}, 0, 0, cv::INTER_LINEAR);
        for (int y = 0; y < height; ++y) {
            auto row = resized.ptr<cv::Vec3b>(y);
            for (int x = 0; x < resizedWidth; ++x)
                for (int c = 0; c < 3; ++c) {
                    float scaled = detector ? float(row[x][c]) * float(1.0/255.0) : float(row[x][c])/255.0f;
                    tensor[(n*3+c)*plane+size_t(y)*width+x] = (scaled-0.5f)/0.5f;
                }
        }
    }
    return tensor;
}
double boxScore(const cv::Mat& prediction, const Box& box) {
    float minX=box[0].x,maxX=minX,minY=box[0].y,maxY=minY;
    for (auto p:box) { minX=std::min(minX,p.x);maxX=std::max(maxX,p.x);minY=std::min(minY,p.y);maxY=std::max(maxY,p.y); }
    int x0=std::clamp(int(std::floor(minX)),0,prediction.cols-1), x1=std::clamp(int(std::ceil(maxX)),0,prediction.cols-1);
    int y0=std::clamp(int(std::floor(minY)),0,prediction.rows-1), y1=std::clamp(int(std::ceil(maxY)),0,prediction.rows-1);
    cv::Mat mask = cv::Mat::zeros(y1-y0+1,x1-x0+1,CV_8U);
    std::vector<cv::Point> points;
    for (auto p:box) points.emplace_back(int(p.x-x0),int(p.y-y0));
    cv::fillPoly(mask,std::vector<std::vector<cv::Point>>{points},1);
    return cv::mean(prediction(cv::Rect(x0,y0,x1-x0+1,y1-y0+1)),mask)[0];
}
std::vector<cv::Point2f> unclip(const Box& box) {
    std::vector<cv::Point2f> points(box.begin(),box.end());
    double area=std::abs(cv::contourArea(points)), perimeter=0;
    for (int i=0;i<4;++i) perimeter+=cv::norm(cv::Point2d(box[i])-cv::Point2d(box[(i+1)%4]));
    if (perimeter<=0) return {};
    ClipperLib::Path path;
    for (auto p:box) path.emplace_back(static_cast<ClipperLib::cInt>(p.x),static_cast<ClipperLib::cInt>(p.y));
    ClipperLib::ClipperOffset offset;
    offset.AddPath(path,ClipperLib::jtRound,ClipperLib::etClosedPolygon);
    ClipperLib::Paths expanded; offset.Execute(expanded,area*1.6/perimeter);
    std::vector<cv::Point2f> result;
    for (auto& polygon:expanded) for (auto p:polygon) result.emplace_back(float(p.X),float(p.Y));
    return result;
}
std::vector<Box> detect(Ort::Session& session, const cv::Mat& image) {
    double ratio=std::min(image.rows,image.cols)<736 ? 736.0/std::min(image.rows,image.cols) : 1.0;
    int height=evenRound(int(image.rows*ratio)/32.0)*32, width=evenRound(int(image.cols*ratio)/32.0)*32;
    if (height<=0 || width<=0) throw std::runtime_error("OCR detector resize is invalid");
    auto input=normalize({image},height,width,true);
    auto value=infer(session,input,{1,3,height,width});
    auto shape=value.GetTensorTypeAndShapeInfo().GetShape();
    if (shape.size()!=4 || shape[0]!=1 || shape[1]!=1) throw std::runtime_error("Unexpected detector tensor");
    cv::Mat prediction(int(shape[2]),int(shape[3]),CV_32F,value.GetTensorMutableData<float>());
    cv::Mat bitmap; cv::compare(prediction,0.3,bitmap,cv::CMP_GT);
    cv::dilate(bitmap,bitmap,cv::Mat::ones(2,2,CV_8U));
    std::vector<std::vector<cv::Point>> contours; cv::findContours(bitmap,contours,cv::RETR_LIST,cv::CHAIN_APPROX_SIMPLE);
    std::vector<Box> boxes;
    for (size_t i=0;i<std::min<size_t>(1000,contours.size());++i) {
        auto [box,shortSide]=miniBox(contours[i]);
        if (shortSide<3 || boxScore(prediction,box)<0.5) continue;
        auto expanded=unclip(box); if (expanded.empty()) continue;
        auto [large,largeShort]=miniBox(expanded); if (largeShort<5) continue;
        for (auto& p:large) {
            p.x=std::clamp(evenRound(double(p.x)/prediction.cols*image.cols),0,image.cols);
            p.y=std::clamp(evenRound(double(p.y)/prediction.rows*image.rows),0,image.rows);
        }
        large=order(large);
        for (auto& p:large) {p.x=std::clamp(int(p.x),0,image.cols-1);p.y=std::clamp(int(p.y),0,image.rows-1);}
        if (int(distance(large[0],large[1]))<=3 || int(distance(large[0],large[3]))<=3) continue;
        boxes.push_back(large);
    }
    std::stable_sort(boxes.begin(),boxes.end(),[](const auto& a,const auto& b){return a[0].y==b[0].y ? a[0].x<b[0].x : a[0].y<b[0].y;});
    for (int i=0;i<int(boxes.size())-1;++i) for (int j=i;j>=0;--j) {
        if (std::abs(boxes[j+1][0].y-boxes[j][0].y)<10 && boxes[j+1][0].x<boxes[j][0].x) std::swap(boxes[j],boxes[j+1]);
        else break;
    }
    return boxes;
}
cv::Mat crop(const cv::Mat& image,const Box& points) {
    int width=int(std::max(distance(points[0],points[1]),distance(points[2],points[3])));
    int height=int(std::max(distance(points[0],points[3]),distance(points[1],points[2])));
    Box target={cv::Point2f(0,0),cv::Point2f(width,0),cv::Point2f(width,height),cv::Point2f(0,height)};
    auto transform=cv::getPerspectiveTransform(points.data(),target.data());
    cv::Mat output;cv::warpPerspective(image,output,transform,{width,height},cv::INTER_CUBIC,cv::BORDER_REPLICATE);
    if (output.rows/double(output.cols)>=1.5) cv::rotate(output,output,cv::ROTATE_90_COUNTERCLOCKWISE);
    return output;
}
std::vector<size_t> sortedIndices(const std::vector<cv::Mat>& images) {
    std::vector<size_t> indices(images.size());std::iota(indices.begin(),indices.end(),0);
    std::stable_sort(indices.begin(),indices.end(),[&](size_t a,size_t b){return images[a].cols/double(images[a].rows)<images[b].cols/double(images[b].rows);});
    return indices;
}
}

OCREngine::OCREngine(const std::string& directory,std::vector<std::string> characters)
    :env_(ORT_LOGGING_LEVEL_ERROR,"photo-translation-ocr"),characters_(std::move(characters)) {
    env_.DisableTelemetryEvents();
    options_.SetIntraOpNumThreads(2);options_.SetInterOpNumThreads(1);
    options_.DisableCpuMemArena();options_.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
    // CPU provider only: no CoreML fallback or network inference.
    det_=Ort::Session(env_,(directory+"/ch_PP-OCRv4_det_infer.onnx").c_str(),options_);
    cls_=Ort::Session(env_,(directory+"/ch_ppocr_mobile_v2.0_cls_infer.onnx").c_str(),options_);
    rec_=Ort::Session(env_,(directory+"/ch_PP-OCRv4_rec_infer.onnx").c_str(),options_);
    if (characters_.size()!=6625) throw std::runtime_error("OCR vocabulary does not match the fixed model");
}
std::vector<OCRBlock> OCREngine::recognize(const uint8_t* encoded,size_t length) {
    if (!length || length>12*1024*1024) throw std::runtime_error("OCR input exceeds 12 MiB");
    cv::Mat bytes(1,int(length),CV_8U,const_cast<uint8_t*>(encoded));
    cv::Mat image=cv::imdecode(bytes,cv::IMREAD_COLOR);
    if (image.empty()) throw std::runtime_error("OCR cannot decode PNG");
    const int originalHeight=image.rows,originalWidth=image.cols;
    if (int64_t(image.rows)*image.cols>20000000) throw std::runtime_error("OCR input exceeds 20 megapixels");
    double ratioH=1,ratioW=1;
    if (std::max(image.rows,image.cols)>2000 || std::min(image.rows,image.cols)<30) {
        double ratio=std::max(image.rows,image.cols)>2000 ? 2000.0/std::max(image.rows,image.cols) : 30.0/std::min(image.rows,image.cols);
        int height=evenRound(int(image.rows*ratio)/32.0)*32, width=evenRound(int(image.cols*ratio)/32.0)*32;
        if (height<=0 || width<=0) throw std::runtime_error("OCR aspect ratio is unsupported");
        ratioH=image.rows/double(height);ratioW=image.cols/double(width);
        cv::resize(image,image,{width,height});
    }
    int padding=0;
    if (image.rows<=30 || image.cols/double(image.rows)>8) {
        int newHeight=std::max(image.cols/8,30)*2;
        padding=std::abs(newHeight-image.rows)/2;
        cv::copyMakeBorder(image,image,padding,padding,0,0,cv::BORDER_CONSTANT,cv::Scalar(0,0,0));
    }
    auto boxes=detect(det_,image);
    if (boxes.empty()) return {};
    std::vector<cv::Mat> crops;for (auto& box:boxes) crops.push_back(crop(image,box));
    auto indices=sortedIndices(crops);
    for (size_t start=0;start<indices.size();start+=6) {
        size_t count=std::min<size_t>(6,indices.size()-start);
        std::vector<cv::Mat> batch;for(size_t j=0;j<count;++j) batch.push_back(crops[indices[start+j]]);
        auto input=normalize(batch,48,192);
        auto values=infer(cls_,input,{int64_t(count),3,48,192});
        auto shape=values.GetTensorTypeAndShapeInfo().GetShape();
        if(shape.size()!=2 || shape[0]!=count || shape[1]!=2) throw std::runtime_error("Unexpected classifier tensor");
        auto scores=values.GetTensorData<float>();
        for(size_t j=0;j<count;++j) if(scores[j*2+1]>scores[j*2] && scores[j*2+1]>0.9f) cv::rotate(crops[indices[start+j]],crops[indices[start+j]],cv::ROTATE_180);
    }
    indices=sortedIndices(crops);
    std::vector<std::pair<std::string,double>> recognized(crops.size());
    for(size_t start=0;start<indices.size();start+=6) {
        size_t count=std::min<size_t>(6,indices.size()-start);double maxRatio=320.0/48;
        std::vector<cv::Mat> batch;
        for(size_t j=0;j<count;++j) {auto m=crops[indices[start+j]];batch.push_back(m);maxRatio=std::max(maxRatio,m.cols/double(m.rows));}
        int width=int(48*maxRatio);auto input=normalize(batch,48,width);
        auto values=infer(rec_,input,{int64_t(count),3,48,width});
        auto shape=values.GetTensorTypeAndShapeInfo().GetShape();
        if(shape.size()!=3 || shape[0]!=count || shape[2]!=characters_.size()) throw std::runtime_error("Unexpected recognizer tensor");
        auto scores=values.GetTensorData<float>();
        for(size_t j=0;j<count;++j) {
            std::string text;double confidence=0;int kept=0,previous=-1;
            for(int64_t t=0;t<shape[1];++t) {
                const float* row=scores+(j*shape[1]+t)*shape[2];
                int best=int(std::max_element(row,row+shape[2])-row);
                if(best!=0 && best!=previous) {text+=characters_[best];confidence+=row[best];++kept;}
                previous=best;
            }
            recognized[indices[start+j]]={text,kept ? confidence/kept : 0};
        }
    }
    std::vector<OCRBlock> result;
    for(size_t i=0;i<boxes.size();++i) {
        if(recognized[i].second<0.5) continue;
        auto box=boxes[i];for(auto& p:box) {p.x=std::clamp(float(p.x*ratioW),0.0f,float(originalWidth));p.y=std::clamp(float((p.y-padding)*ratioH),0.0f,float(originalHeight));}
        result.push_back({box,recognized[i].first,recognized[i].second});
    }
    return result;
}
}
