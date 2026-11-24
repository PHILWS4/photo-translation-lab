#include "NativeOCR.hpp"
#include <opencv2/core/version.hpp>
#import "NativeOCRBridge.h"
@implementation NativeOCRBridge {
    std::unique_ptr<photolab::OCREngine> _engine;
}
- (nullable instancetype)initWithModelDirectory:(NSString *)directory error:(NSError **)error {
    self = [super init]; if (!self) return nil;
    try {
        NSData *json = [NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"characters.json"] options:0 error:error];
        if (!json) return nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:json options:0 error:error];
        if (![parsed isKindOfClass:[NSArray class]]) throw std::runtime_error("Invalid OCR vocabulary JSON");
        std::vector<std::string> characters;
        for (id character in parsed) {
            if (![character isKindOfClass:[NSString class]]) throw std::runtime_error("Invalid OCR vocabulary token");
            characters.emplace_back([character UTF8String]);
        }
        _engine = std::make_unique<photolab::OCREngine>(directory.UTF8String,std::move(characters));
        return self;
    } catch (const std::exception& ex) {
        if (error) *error = [NSError errorWithDomain:@"PhotoLab.NativeOCR" code:1 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"本地 OCR 初始化失败：%s",ex.what()]}];
        return nil;
    }
}
- (nullable NSData *)recognizePNG:(NSData *)data error:(NSError **)error {
    try {
        auto blocks = _engine->recognize((const uint8_t *)data.bytes,data.length);
        NSMutableArray *result=[NSMutableArray array];
        for (const auto& block:blocks) {
            NSMutableArray *polygon=[NSMutableArray array];
            for (auto p:block.polygon) [polygon addObject:@[@(p.x),@(p.y)]];
            NSString *text=[[NSString alloc] initWithBytes:block.text.data() length:block.text.size() encoding:NSUTF8StringEncoding];
            if (!text) throw std::runtime_error("OCR output is not valid UTF-8");
            [result addObject:@{@"block_id":[NSString stringWithFormat:@"%lu",(unsigned long)result.count],@"text":text,@"confidence":@(block.confidence),@"polygon":polygon}];
        }
        return [NSJSONSerialization dataWithJSONObject:result options:0 error:error];
    } catch (const std::exception& ex) {
        if (error) *error = [NSError errorWithDomain:@"PhotoLab.NativeOCR" code:2 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"本地 OCR 失败：%s",ex.what()]}];
        return nil;
    }
}
+ (NSString *)runtimeVersion { return [NSString stringWithUTF8String:OrtGetApiBase()->GetVersionString()]; }
+ (NSString *)opencvVersion { return @CV_VERSION; }
@end
