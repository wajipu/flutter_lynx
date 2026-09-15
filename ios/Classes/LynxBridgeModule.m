#import "LynxBridgeModule.h"
#import "FlutterLynxPlugin.h"

@implementation LynxBridgeBinding {
  NSSet<NSString *> *_allowedModules;
  BOOL _active;
}

- (instancetype)initWithAllowedModules:(NSSet<NSString *> *)allowedModules {
  self = [super init];
  if (self) {
    _allowedModules = [allowedModules copy];
    _active = YES;
  }
  return self;
}

- (BOOL)isActive {
  return _active;
}

- (void)invalidate {
  _active = NO;
}

- (void)callModule:(NSString *)module
            method:(NSString *)method
            params:(NSDictionary *)params
            callId:(NSString *)callId
          callback:(void (^)(id result))callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self->_active) {
      return;
    }
    if (![self->_allowedModules containsObject:module]) {
      callback(@{
        @"callId" : callId ?: @"",
        @"code" : @403,
        @"message" : @"Bridge module is not allowed",
      });
      return;
    }
    [FlutterLynxPlugin callBridge:module
                           method:method
                           params:params
                           callId:callId
                       completion:^(NSDictionary *response) {
                         if (self->_active && callback) {
                           callback(response);
                         }
                       }];
  });
}

@end

@implementation LynxBridgeModule {
  LynxBridgeBinding *_binding;
}

+ (NSString *)name {
  return @"LynxBridge";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"call" : NSStringFromSelector(@selector(call:method:params:callId:callback:)),
  };
}

- (instancetype)initWithParam:(id)param {
  self = [super init];
  if (self) {
    NSAssert([param isKindOfClass:[LynxBridgeBinding class]], @"LynxBridge requires a view binding");
    _binding = param;
  }
  return self;
}

- (void)call:(NSString *)module
      method:(NSString *)method
      params:(NSDictionary *)params
      callId:(NSString *)callId
    callback:(void (^)(id result))callback {
  [_binding callModule:module
                method:method
                params:[params isKindOfClass:[NSDictionary class]] ? params : @{}
                callId:callId
              callback:callback];
}

@end
