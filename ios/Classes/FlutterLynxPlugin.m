#import "FlutterLynxPlugin.h"
#import "LynxHostCapsuleOverlay.h"
#import "LynxPlatformView.h"

#import <UIKit/UIKit.h>

@implementation FlutterLynxPlugin {
  FlutterMethodChannel *_pluginChannel;
  FlutterMethodChannel *_hostCapsuleChannel;
}

static FlutterMethodChannel *kBridgeChannel;

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterLynxPlugin *instance = [[FlutterLynxPlugin alloc] init];
  FlutterMethodChannel *pluginChannel =
      [FlutterMethodChannel methodChannelWithName:@"com.kmanager.flutter_lynx/plugin"
                                  binaryMessenger:[registrar messenger]];
  [registrar addMethodCallDelegate:instance channel:pluginChannel];
  instance->_pluginChannel = pluginChannel;

  kBridgeChannel = [FlutterMethodChannel methodChannelWithName:@"com.kmanager.flutter_lynx/bridge"
                                               binaryMessenger:[registrar messenger]];
  [registrar addMethodCallDelegate:instance channel:kBridgeChannel];

  FlutterMethodChannel *hostCapsuleChannel =
      [FlutterMethodChannel methodChannelWithName:@"com.kmanager.flutter_lynx/host_capsule"
                                  binaryMessenger:[registrar messenger]];
  [registrar addMethodCallDelegate:instance channel:hostCapsuleChannel];
  instance->_hostCapsuleChannel = hostCapsuleChannel;
  [[LynxHostCapsuleOverlay shared] bindChannel:hostCapsuleChannel];

  LynxPlatformViewFactory *factory =
      [[LynxPlatformViewFactory alloc] initWithMessenger:[registrar messenger]];
  [registrar registerViewFactory:factory withId:@"com.kmanager.flutter_lynx/lynx_view"];
}

+ (void)callBridge:(NSString *)module
            method:(NSString *)method
            params:(NSDictionary *)params
            callId:(NSString *)callId
        completion:(void (^)(NSDictionary *response))completion {
  FlutterMethodChannel *channel = kBridgeChannel;
  if (channel == nil) {
    completion(@{
      @"callId" : callId ?: @"",
      @"code" : @500,
      @"message" : @"Bridge channel not initialized",
    });
    return;
  }
  [channel invokeMethod:@"callBridge"
              arguments:@{
                @"callId" : callId ?: @"",
                @"module" : module ?: @"",
                @"method" : method ?: @"",
                @"params" : params ?: @{},
              }
                 result:^(id result) {
                   if ([result isKindOfClass:[NSDictionary class]]) {
                     completion(result);
                     return;
                   }
                   if ([result isKindOfClass:[FlutterError class]]) {
                     FlutterError *error = result;
                     completion(@{
                       @"callId" : callId ?: @"",
                       @"code" : @500,
                       @"message" : error.message ?: error.code,
                     });
                     return;
                   }
                   if (result == FlutterMethodNotImplemented) {
                     completion(@{
                       @"callId" : callId ?: @"",
                       @"code" : @404,
                       @"message" : @"Method not implemented on Flutter host",
                     });
                     return;
                   }
                   completion(@{
                     @"callId" : callId ?: @"",
                     @"code" : @500,
                     @"message" : @"Invalid Flutter bridge response",
                   });
                 }];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([call.method isEqualToString:@"getPlatformVersion"]) {
    result([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
    return;
  }
  if ([call.method isEqualToString:@"show"] || [call.method isEqualToString:@"setDark"] ||
      [call.method isEqualToString:@"hide"]) {
    NSDictionary *args = [call.arguments isKindOfClass:[NSDictionary class]] ? call.arguments : @{};
    BOOL dark = [args[@"dark"] isKindOfClass:[NSNumber class]] && [args[@"dark"] intValue] != 0;
    if ([call.method isEqualToString:@"show"]) {
      [[LynxHostCapsuleOverlay shared] showDark:dark];
    } else if ([call.method isEqualToString:@"setDark"]) {
      [[LynxHostCapsuleOverlay shared] setDark:dark];
    } else {
      [[LynxHostCapsuleOverlay shared] hide];
    }
    result(@YES);
    return;
  }
  if ([call.method isEqualToString:@"sendCustomEvent"]) {
    NSDictionary *args = [call.arguments isKindOfClass:[NSDictionary class]] ? call.arguments : @{};
    NSString *eventName = [args[@"eventName"] isKindOfClass:[NSString class]] ? args[@"eventName"] : @"";
    NSDictionary *data = [args[@"data"] isKindOfClass:[NSDictionary class]] ? args[@"data"] : @{};
    NSNumber *viewId = [args[@"viewId"] isKindOfClass:[NSNumber class]] ? args[@"viewId"] : nil;
    if ([[LynxPlatformViewManager shared] sendEvent:eventName data:data viewId:viewId]) {
      result(@YES);
    } else {
      result([FlutterError errorWithCode:@"lynx_event_not_delivered"
                                 message:@"No loaded Lynx view accepted the event"
                                 details:nil]);
    }
    return;
  }
  result(FlutterMethodNotImplemented);
}

- (void)detachFromEngineForRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  [[LynxHostCapsuleOverlay shared] hide];
  [_pluginChannel setMethodCallHandler:nil];
  _pluginChannel = nil;
  [_hostCapsuleChannel setMethodCallHandler:nil];
  _hostCapsuleChannel = nil;
  [kBridgeChannel setMethodCallHandler:nil];
  kBridgeChannel = nil;
}

@end
