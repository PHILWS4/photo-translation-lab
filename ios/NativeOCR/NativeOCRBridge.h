#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface NativeOCRBridge : NSObject
- (nullable instancetype)initWithModelDirectory:(NSString *)directory error:(NSError **)error;
- (nullable NSData *)recognizePNG:(NSData *)data error:(NSError **)error;
+ (NSString *)runtimeVersion;
+ (NSString *)opencvVersion;
@end
NS_ASSUME_NONNULL_END
