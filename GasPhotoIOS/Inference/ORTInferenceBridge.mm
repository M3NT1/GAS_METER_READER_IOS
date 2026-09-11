#import "ORTInferenceBridge.h"
#import <onnxruntime_objc/onnxruntime.h>

@interface ORTInferenceBridge ()

@property(nonatomic, strong) ORTEnv *environment;
@property(nonatomic, strong) ORTSession *detectorSession;
@property(nonatomic, strong) ORTSession *digitSession;

@end

@implementation ORTInferenceBridge

- (nullable instancetype)initWithDetectorModelPath:(NSString *)detectorModelPath
                                digitModelPath:(NSString *)digitModelPath
                                         error:(NSError **)error {
  self = [super init];
  if (!self) {
    return nil;
  }

  NSError *runtimeError = nil;
  _environment = [[ORTEnv alloc] initWithLoggingLevel:ORTLoggingLevelWarning error:&runtimeError];
  if (!_environment) {
    if (error) {
      *error = runtimeError;
    }
    return nil;
  }

  _detectorSession = [[ORTSession alloc] initWithEnv:_environment
                                            modelPath:detectorModelPath
                                       sessionOptions:nil
                                                error:&runtimeError];
  if (!_detectorSession) {
    if (error) {
      *error = runtimeError;
    }
    return nil;
  }

  _digitSession = [[ORTSession alloc] initWithEnv:_environment
                                         modelPath:digitModelPath
                                    sessionOptions:nil
                                             error:&runtimeError];
  if (!_digitSession) {
    if (error) {
      *error = runtimeError;
    }
    return nil;
  }

  return self;
}

- (nullable NSData *)detectorOutputForInput:(NSData *)input error:(NSError **)error {
  return [self outputForSession:_detectorSession
                          input:input
                          shape:@[@1, @3, @960, @960]
                          error:error];
}

- (nullable NSData *)digitOutputForInput:(NSData *)input error:(NSError **)error {
  return [self outputForSession:_digitSession
                          input:input
                          shape:@[@1, @3, @128, @128]
                          error:error];
}

- (nullable NSData *)outputForSession:(ORTSession *)session
                                 input:(NSData *)input
                                 shape:(NSArray<NSNumber *> *)shape
                                 error:(NSError **)error {
  NSError *runtimeError = nil;
  ORTValue *inputValue = [[ORTValue alloc] initWithTensorData:[input mutableCopy]
                                                    elementType:ORTTensorElementDataTypeFloat
                                                          shape:shape
                                                          error:&runtimeError];
  if (!inputValue) {
    if (error) {
      *error = runtimeError;
    }
    return nil;
  }

  NSArray<NSString *> *inputNames = [session inputNamesWithError:&runtimeError];
  NSArray<NSString *> *outputNames = [session outputNamesWithError:&runtimeError];
  if (!inputNames || !outputNames || inputNames.count != 1 || outputNames.count != 1) {
    if (error) {
      *error = runtimeError;
    }
    return nil;
  }

  NSDictionary<NSString *, ORTValue *> *outputs = [session runWithInputs:@{inputNames.firstObject : inputValue}
                                                                outputNames:[NSSet setWithArray:outputNames]
                                                                 runOptions:nil
                                                                      error:&runtimeError];
  ORTValue *output = outputs[outputNames.firstObject];
  NSMutableData *data = [output tensorDataWithError:&runtimeError];
  if (!data) {
    if (error) {
      *error = runtimeError;
    }
    return nil;
  }
  return [data copy];
}

@end
