#import "LynxBridgeModule.h"
#import "FlutterLynxPlugin.h"
#include <math.h>

static BOOL MiniAppSafeRevision(id value) {
  if (![value isKindOfClass:[NSNumber class]] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) {
    return NO;
  }
  double number = [value doubleValue];
  return isfinite(number) && floor(number) == number && number >= 0 && number <= 9007199254740991.0;
}

@implementation LynxBridgeBinding {
  NSSet<NSString *> *_allowedModules;
  FlutterMethodChannel *_bridgeChannel;
  NSString *_sourceContextId;
  BOOL _active;
}

- (instancetype)initWithAllowedModules:(NSSet<NSString *> *)allowedModules
                         bridgeChannel:(FlutterMethodChannel *)bridgeChannel
                       sourceContextId:(NSString *)sourceContextId {
  self = [super init];
  if (self) {
    _allowedModules = [allowedModules copy];
    _bridgeChannel = bridgeChannel;
    // The host's creation parameter is immutable for this binding's lifetime.
    _sourceContextId = [sourceContextId copy];
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
                  sourceContextId:self->_sourceContextId
                          channel:self->_bridgeChannel
                       completion:^(NSDictionary *response) {
                         if (self->_active && callback) {
                           if (self.storeScopeObserver && self->_sourceContextId.length > 0 &&
                               [module isEqualToString:@"data"] && [method isEqualToString:@"storeSelect"] &&
                               [response[@"callId"] isEqual:callId] && MiniAppSafeRevision(response[@"code"]) &&
                               [response[@"code"] integerValue] == 0) {
                             NSDictionary *envelope = response[@"data"];
                             NSDictionary *selection = [envelope isKindOfClass:[NSDictionary class]] ? envelope[@"data"] : nil;
                             NSNumber *requestedRevision = params[@"contextRevision"];
                             if ([envelope isKindOfClass:[NSDictionary class]] && MiniAppSafeRevision(envelope[@"code"]) &&
                                 [envelope[@"code"] integerValue] == 200 && [selection isKindOfClass:[NSDictionary class]] &&
                                 selection.count == 3 && [selection[@"storeScopeLabel"] isKindOfClass:[NSString class]] &&
                                 MiniAppSafeRevision(selection[@"status"]) && [selection[@"status"] integerValue] == 1 &&
                                 MiniAppSafeRevision(requestedRevision) && MiniAppSafeRevision(selection[@"contextRevision"]) &&
                                 [selection[@"contextRevision"] doubleValue] == [requestedRevision doubleValue] + 1) {
                               self.storeScopeObserver(self->_sourceContextId, requestedRevision, selection);
                             }
                           }
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

- (void)destroy {
  // A cleared native view must not complete old host calls into its JS runtime.
  [_binding invalidate];
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
