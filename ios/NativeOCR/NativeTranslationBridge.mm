#import "NativeTranslationBridge.h"
#include <onnxruntime_cxx_api.h>
#include <sentencepiece_processor.h>
#include <array>
#include <cmath>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

namespace {
void check(const sentencepiece::util::Status& status) {
    if (!status.ok()) throw std::runtime_error(status.ToString());
}
void fail(NSError **error, const std::exception& ex) {
    if (error) *error = [NSError errorWithDomain:@"PhotoLab.NativeTranslation" code:1
        userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"本地翻译失败：%@",[NSString stringWithUTF8String:ex.what()] ?: @"未知原生错误"]}];
}
struct Engine {
    Ort::Env env{ORT_LOGGING_LEVEL_WARNING,"PhotoLab.Translation"};
    Ort::SessionOptions options;
    Ort::Session encoder{nullptr}, decoder{nullptr};
    sentencepiece::SentencePieceProcessor source, target;
    std::unordered_map<std::string,int64_t> vocabulary;
    std::vector<std::string> inverse;
    explicit Engine(NSString *directory) {
        env.DisableTelemetryEvents(); options.SetIntraOpNumThreads(2); options.SetInterOpNumThreads(1);
        options.SetGraphOptimizationLevel(ORT_DISABLE_ALL);
        options.SetDeterministicCompute(true);
        // Explicit unfused graph for cross-platform quantization comparison.
        check(source.Load([[directory stringByAppendingPathComponent:@"source.spm"] UTF8String]));
        check(target.Load([[directory stringByAppendingPathComponent:@"target.spm"] UTF8String]));
        NSError *error=nil;
        NSData *bytes=[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"vocab.json"] options:0 error:&error];
        id values=bytes ? [NSJSONSerialization JSONObjectWithData:bytes options:0 error:&error] : nil;
        if (![values isKindOfClass:[NSDictionary class]] || [values count]!=65001) throw std::runtime_error("Invalid Marian vocabulary");
        inverse.resize(65001); std::vector<bool> seen(65001,false);
        for (NSString *piece in values) {
            id value=values[piece];
            if (![value isKindOfClass:[NSNumber class]]) throw std::runtime_error("Invalid token ID");
            int64_t n=[value longLongValue];
            if (n<0 || n>=65001 || seen[n]) throw std::runtime_error("Duplicate or out-of-range vocabulary ID");
            seen[n]=true; vocabulary.emplace(piece.UTF8String,n); inverse[n]=piece.UTF8String;
        }
        if (vocabulary.at("</s>")!=0 || vocabulary.at("<unk>")!=1 || vocabulary.at("<pad>")!=65000)
            throw std::runtime_error("Special token IDs differ from the fixed model");
        NSData *configBytes=[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"config.json"]];
        NSDictionary *config=configBytes ? [NSJSONSerialization JSONObjectWithData:configBytes options:0 error:&error] : nil;
        if (![config isKindOfClass:[NSDictionary class]] || ![config[@"decoder_start_token_id"] isEqual:@65000] ||
            ![config[@"pad_token_id"] isEqual:@65000] || ![config[@"eos_token_id"] isEqual:@0])
            throw std::runtime_error("Unsupported decoder configuration");
        encoder=Ort::Session(env,[[directory stringByAppendingPathComponent:@"onnx/encoder_model_quantized.onnx"] UTF8String],options);
        decoder=Ort::Session(env,[[directory stringByAppendingPathComponent:@"onnx/decoder_model_quantized.onnx"] UTF8String],options);
    }
    int64_t tokenID(const std::string& piece) const {
        auto found=vocabulary.find(piece);return found==vocabulary.end() ? 1 : found->second;
    }
    void encodeChunk(std::string chunk,std::vector<int64_t>& ids) const {
        // MarianTokenizer removes a leading >>language<< marker before SentencePiece.
        if (chunk.rfind(">>",0)==0) {
            auto end=chunk.find("<<");
            if (end!=std::string::npos) {ids.push_back(tokenID(chunk.substr(0,end+2)));chunk.erase(0,end+2);}
        }
        std::vector<std::string> pieces;check(source.Encode(chunk,&pieces));
        for (const auto& piece:pieces) ids.push_back(tokenID(piece));
    }
    std::vector<int64_t> encode(const std::string& text) const {
        // Hugging Face's added special tokens are isolated before _tokenize.
        const std::array<std::string,3> specials={"</s>","<unk>","<pad>"};
        std::vector<int64_t> ids;size_t cursor=0;
        while (cursor<text.size()) {
            size_t next=std::string::npos;std::string match;
            for (const auto& s:specials) {auto p=text.find(s,cursor);if(p<next){next=p;match=s;}}
            if (next==std::string::npos) {encodeChunk(text.substr(cursor),ids);break;}
            if (next>cursor) encodeChunk(text.substr(cursor,next-cursor),ids);
            ids.push_back(tokenID(match));cursor=next+match.size();
        }
        ids.push_back(0);return ids;
    }
    NSString *decode(const std::vector<int64_t>& ids) const {
        std::vector<std::string> pieces;
        for (auto n:ids) {
            if (n<0 || n>=65001) throw std::runtime_error("Output token ID out of range");
            if (n!=0 && n!=1 && n!=65000) pieces.push_back(inverse[n]);
        }
        std::string result;check(target.Decode(pieces,&result));
        NSString *text=[[NSString alloc] initWithBytes:result.data() length:result.size() encoding:NSUTF8StringEncoding];
        if (!text) throw std::runtime_error("Translation is not valid UTF-8");
        text=[[text stringByReplacingOccurrencesOfString:@"▁" withString:@" "] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        // Transformers clean_up_tokenization_spaces, in the same replacement order.
        NSArray *from=@[@" .",@" ?",@" !",@" ,",@" ' ",@" n't",@" 'm",@" 's",@" 've",@" 're"];
        NSArray *to=@[@".",@"?",@"!",@",",@"'",@"n't",@"'m",@"'s",@"'ve",@"'re"];
        for (NSUInteger i=0;i<from.count;++i) text=[text stringByReplacingOccurrencesOfString:from[i] withString:to[i]];
        return text;
    }
    std::vector<int64_t> generate(std::vector<int64_t>& input,int limit) {
        if (input.size()>256) throw std::runtime_error("单句超过 256 token；不会静默截断");
        if (limit<1 || limit>128) throw std::runtime_error("Invalid decoder step limit");
        std::vector<int64_t> mask(input.size(),1);std::array<int64_t,2> shape={1,(int64_t)input.size()};
        auto memory=Ort::MemoryInfo::CreateCpu(OrtArenaAllocator,OrtMemTypeDefault);
        std::vector<Ort::Value> encoderInputs;
        encoderInputs.push_back(Ort::Value::CreateTensor<int64_t>(memory,input.data(),input.size(),shape.data(),2));
        encoderInputs.push_back(Ort::Value::CreateTensor<int64_t>(memory,mask.data(),mask.size(),shape.data(),2));
        const char *encoderNames[]={"input_ids","attention_mask"};const char *hiddenName[]={"last_hidden_state"};
        auto hidden=encoder.Run(Ort::RunOptions{nullptr},encoderNames,encoderInputs.data(),2,hiddenName,1);
        auto hiddenShape=hidden[0].GetTensorTypeAndShapeInfo().GetShape();
        if (hiddenShape!=std::vector<int64_t>({1,(int64_t)input.size(),512})) throw std::runtime_error("Unexpected encoder output shape");
        std::vector<int64_t> generated={65000};
        const char *decoderNames[]={"encoder_attention_mask","input_ids","encoder_hidden_states"};const char *outputNames[]={"logits"};
        for (int step=0;step<limit;++step) {
            std::array<int64_t,2> decoderShape={1,(int64_t)generated.size()};
            std::vector<Ort::Value> inputs;
            inputs.push_back(Ort::Value::CreateTensor<int64_t>(memory,mask.data(),mask.size(),shape.data(),2));
            inputs.push_back(Ort::Value::CreateTensor<int64_t>(memory,generated.data(),generated.size(),decoderShape.data(),2));
            inputs.push_back(Ort::Value::CreateTensor<float>(memory,hidden[0].GetTensorMutableData<float>(),input.size()*512,hiddenShape.data(),3));
            auto outputs=decoder.Run(Ort::RunOptions{nullptr},decoderNames,inputs.data(),3,outputNames,1);
            auto outputShape=outputs[0].GetTensorTypeAndShapeInfo().GetShape();
            if (outputShape!=std::vector<int64_t>({1,(int64_t)generated.size(),65001})) throw std::runtime_error("Unexpected decoder output shape");
            const float *scores=outputs[0].GetTensorData<float>()+(generated.size()-1)*65001;
            int64_t best=0;float maximum=-std::numeric_limits<float>::infinity();
            for (int64_t n=0;n<65000;++n) { // Mask pad=65000; first index wins ties, as numpy.argmax.
                if (!std::isfinite(scores[n])) throw std::runtime_error("Non-finite decoder score");
                if (scores[n]>maximum){maximum=scores[n];best=n;}
            }
            generated.push_back(best);
            if (best==0) return std::vector<int64_t>(generated.begin()+1,generated.end());
        }
        throw std::runtime_error("译文生成达到长度上限；未把截断文本当成成功结果");
    }
};
NSArray<NSNumber *> *numbers(const std::vector<int64_t>& ids) {
    NSMutableArray *values=[NSMutableArray arrayWithCapacity:ids.size()];for (auto n:ids) [values addObject:@(n)];return values;
}
}
@implementation NativeTranslationBridge { std::unique_ptr<Engine> _engine; }
- (nullable instancetype)initWithModelDirectory:(NSString *)directory error:(NSError **)error {
    self=[super init];if (!self) return nil;
    try {_engine=std::make_unique<Engine>(directory);return self;}catch(const std::exception& ex){fail(error,ex);return nil;}
}
- (nullable NSArray<NSNumber *> *)encodeText:(NSString *)text error:(NSError **)error {
    try{return numbers(_engine->encode(std::string(text.UTF8String,[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding])));}catch(const std::exception& ex){fail(error,ex);return nil;}
}
- (nullable NSString *)decodeIDs:(NSArray<NSNumber *> *)ids error:(NSError **)error {
    try {std::vector<int64_t> values;for(NSNumber *n in ids) values.push_back(n.longLongValue);return _engine->decode(values);}
    catch(const std::exception& ex){fail(error,ex);return nil;}
}
- (nullable NSData *)translateText:(NSString *)text stepLimit:(NSInteger)limit error:(NSError **)error {
    try {
        auto input=_engine->encode(std::string(text.UTF8String,[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]));auto output=_engine->generate(input,(int)limit);
        return [NSJSONSerialization dataWithJSONObject:@{@"input_ids":numbers(input),@"output_ids":numbers(output),@"text":_engine->decode(output)} options:0 error:error];
    }catch(const std::exception& ex){fail(error,ex);return nil;}
}
@end
