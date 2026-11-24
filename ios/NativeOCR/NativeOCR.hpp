#pragma once
#include <array>
#include <memory>
#include <string>
#include <vector>
#include <opencv2/core.hpp>
#include <onnxruntime_cxx_api.h>

namespace photolab {
struct OCRBlock {
    std::array<cv::Point2f, 4> polygon;
    std::string text;
    double confidence;
};
class OCREngine {
public:
    OCREngine(const std::string& directory, std::vector<std::string> characters);
    std::vector<OCRBlock> recognize(const uint8_t* encoded, size_t length);
private:
    Ort::Env env_;
    Ort::SessionOptions options_;
    Ort::Session det_{nullptr}, cls_{nullptr}, rec_{nullptr};
    std::vector<std::string> characters_;
};
}
