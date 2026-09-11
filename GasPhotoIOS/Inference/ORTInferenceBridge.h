#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ORTInferenceBridge : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (nullable instancetype)initWithDetectorModelPath:(NSString *)detectorModelPath
                                digitModelPath:(NSString *)digitModelPath
                                         error:(NSError **)error NS_DESIGNATED_INITIALIZER;

- (nullable NSData *)detectorOutputForInput:(NSData *)input error:(NSError **)error;
- (nullable NSData *)digitOutputForInput:(NSData *)input error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
