#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface NativeTranslationBridge : NSObject
- (nullable instancetype)initWithModelDirectory:(NSString *)directory error:(NSError **)error;
- (nullable NSArray<NSNumber *> *)encodeText:(NSString *)text error:(NSError **)error;
- (nullable NSString *)decodeIDs:(NSArray<NSNumber *> *)ids error:(NSError **)error;
// Diagnostic token arrays are returned in memory; normal measurement logs never contain them.
- (nullable NSData *)translateText:(NSString *)text stepLimit:(NSInteger)limit error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
