#import "LynxPlatformView.h"
#import "LynxBridgeModule.h"
#import "MiniAppLynxHolder.h"
#import <Lynx/NavigationModule.h>
#import <Lynx/LynxNavigator.h>

#import <UIKit/UIKit.h>

#import <Lynx/LynxConfig.h>
#import <Lynx/LynxEnv.h>
#import <Lynx/LynxError.h>
#import <Lynx/LynxTemplateData.h>
#import <Lynx/LynxTemplateProvider.h>
#import <Lynx/LynxView.h>
#import <Lynx/LynxViewBuilder.h>
#import <Lynx/LynxViewClient.h>
#import <SDWebImage/SDImageCodersManager.h>
#import <SDWebImageWebPCoder/SDWebImageWebPCoder.h>

static const NSInteger kMaxBundleBytes = 10 * 1024 * 1024;
static NSString *const kModuleNamePattern = @"^[A-Za-z0-9_-]{1,64}$";
// 内联源码没有真实来源地址；about: scheme 保证引擎不会拿它解析相对资源。
static NSString *const kInlineTemplateBaseURL = @"about:lynx-inline";

/// StandardMessageCodec 把 Dart Uint8List 解码为 FlutterStandardTypedData（其
/// data 才是字节本体），不是裸 NSData；直喂 bytes 参数必须经此解码。
static NSData *DecodeTemplateBytesParam(id value) {
  if ([value isKindOfClass:[NSData class]]) {
    return value;
  }
  if ([value isKindOfClass:[FlutterStandardTypedData class]]) {
    return [(FlutterStandardTypedData *)value data];
  }
  return nil;
}

@interface FlutterLynxPreparedFileProvider : NSObject <LynxTemplateProvider>
@end

@implementation FlutterLynxPreparedFileProvider
- (void)loadTemplateWithUrl:(NSString *)url onComplete:(LynxTemplateLoadBlock)callback {
  NSURL *fileURL = nil;
  if ([url hasPrefix:@"file:"]) {
    fileURL = [NSURL URLWithString:url];
    if (fileURL.scheme.length == 0 || ![fileURL.scheme isEqualToString:@"file"] || fileURL.host.length > 0 ||
        fileURL.query.length > 0 || fileURL.fragment.length > 0) {
      callback(nil, [NSError errorWithDomain:@"com.kmanager.flutter_lynx"
                                        code:400
                                    userInfo:@{NSLocalizedDescriptionKey : @"Lynx only accepts a prepared local file URL"}]);
      return;
    }
  } else if (url.length > 0 && [url hasPrefix:@"/"]) {
    fileURL = [NSURL fileURLWithPath:url];
  } else {
    callback(nil, [NSError errorWithDomain:@"com.kmanager.flutter_lynx"
                                      code:400
                                  userInfo:@{NSLocalizedDescriptionKey : @"Lynx only accepts an absolute prepared local file path"}]);
    return;
  }
  NSError *error = nil;
  NSData *data = [NSData dataWithContentsOfURL:fileURL options:0 error:&error];
  // 页面栈容器需要知道当前 bundle：导航出的新页面复用同一文件。
  // 防御：url 非法分支的 fileURL 可能为 nil，不得以 nil 覆盖既有值。
  if (fileURL.path.length > 0) {
    [MiniAppLynxHolder shared].preparedBundlePath = fileURL.path;
  } else {
    NSLog(@"[MiniAppLynxHolder] skip nil path from url=%@", url);
  }
  if (error || data.length == 0 || data.length > kMaxBundleBytes) {
    callback(nil, error ?: [NSError errorWithDomain:@"com.kmanager.flutter_lynx"
                                               code:400
                                           userInfo:@{NSLocalizedDescriptionKey : @"Prepared Lynx bundle is missing, empty or larger than 10 MiB"}]);
    return;
  }
  callback(data, nil);
}
@end

@interface FlutterLynxLifecycleClient : NSObject <LynxViewLifecycle>
@property(nonatomic, copy) void (^onLoadSuccess)(void);
@property(nonatomic, copy) void (^onFirstScreen)(void);
@property(nonatomic, copy) void (^onLoadFail)(NSString *message);
@end

@implementation FlutterLynxLifecycleClient
- (void)lynxView:(LynxView *)view didLoadFinishedWithUrl:(NSString *)url {
  if (self.onLoadSuccess) {
    self.onLoadSuccess();
  }
}

- (void)lynxViewDidFirstScreen:(LynxView *)view {
  if (self.onFirstScreen) {
    self.onFirstScreen();
  }
}

- (void)lynxView:(LynxView *)view didRecieveError:(NSError *)error {
  [self reportError:error];
}

- (void)lynxView:(LynxView *)view didLoadFailedWithUrl:(NSString *)url error:(NSError *)error {
  [self reportError:error];
}

- (void)reportError:(NSError *)error {
  if (!self.onLoadFail) {
    return;
  }
  self.onLoadFail([self describeError:error]);
}

- (NSString *)describeError:(NSError *)error {
  if ([error isKindOfClass:[LynxError class]]) {
    LynxError *lynxError = (LynxError *)error;
    NSString *message = lynxError.summaryMessage.length > 0 ? lynxError.summaryMessage : @"load failed";
    return [NSString stringWithFormat:@"Lynx %ld: %@", (long)lynxError.errorCode, message];
  }
  if (error.localizedDescription.length > 0) {
    return error.localizedDescription;
  }
  return @"Lynx load failed";
}
@end

@interface FlutterLynxRootView : UIView
@property(nonatomic, weak) LynxView *lynxView;
@property(nonatomic, assign) CGSize lastViewport;
/// 内容自适应高度：开启后高度由模板内容决定，测得的内容高经 onContentHeight
/// 回报宿主调整 Flutter 容器；宽度仍由容器约束（Exact）。
@property(nonatomic, assign) BOOL autoHeight;
@property(nonatomic, copy) void (^onContentHeight)(CGFloat);
@property(nonatomic, assign) CGFloat reportedContentHeight;
@end

@implementation FlutterLynxRootView
- (void)layoutSubviews {
  [super layoutSubviews];
  LynxView *view = self.lynxView;
  CGSize size = self.bounds.size;
  if (view == nil || size.width < 1) {
    return;
  }
  if (self.autoHeight) {
    // 宽度仍由容器约束；宽度变化时同步 viewport 宽度（高度交给内容决定）。
    // struct 属性不能对成员单独赋值，先取整体再写回。
    CGSize lastViewport = self.lastViewport;
    if (fabs(size.width - lastViewport.width) > 0.5) {
      lastViewport.width = size.width;
      self.lastViewport = lastViewport;
      view.frame = CGRectMake(0, 0, size.width, MAX(view.frame.size.height, 1));
      [view updateViewportWithPreferredLayoutWidth:size.width
                         preferredLayoutHeight:view.frame.size.height
                                    needLayout:YES];
    }
    CGFloat contentHeight = view.intrinsicContentSize.height;
    if (contentHeight >= 1 &&
        fabs(contentHeight - self.reportedContentHeight) > 0.5) {
      self.reportedContentHeight = contentHeight;
      view.frame = CGRectMake(0, 0, size.width, contentHeight);
      if (self.onContentHeight) {
        self.onContentHeight(contentHeight);
      }
    }
    return;
  }
  // Flutter UiKitView is often created with a zero frame; Lynx keeps that
  // viewport until we push the real size after layout.
  if (size.height >= 1 && !CGSizeEqualToSize(size, self.lastViewport)) {
    self.lastViewport = size;
    view.frame = self.bounds;
    [view updateViewportWithPreferredLayoutWidth:size.width
                           preferredLayoutHeight:size.height
                                      needLayout:YES];
  }
}
@end

@implementation LynxPlatformViewManager {
  NSMapTable<NSNumber *, LynxPlatformView *> *_views;
}

+ (instancetype)shared {
  static LynxPlatformViewManager *instance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[LynxPlatformViewManager alloc] init];
  });
  return instance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _views = [NSMapTable strongToWeakObjectsMapTable];
  }
  return self;
}

- (void)registerView:(id)view forViewId:(int64_t)viewId {
  @synchronized(self) {
    [_views setObject:view forKey:@(viewId)];
  }
}

- (void)unregisterView:(id)view forViewId:(int64_t)viewId {
  @synchronized(self) {
    LynxPlatformView *current = [_views objectForKey:@(viewId)];
    if (current == view) {
      [_views removeObjectForKey:@(viewId)];
    }
  }
}

- (BOOL)sendEvent:(NSString *)eventName data:(NSDictionary *)data viewId:(NSNumber *)viewId {
  NSArray<LynxPlatformView *> *targets = nil;
  @synchronized(self) {
    if (viewId != nil) {
      LynxPlatformView *view = [_views objectForKey:viewId];
      targets = view == nil ? @[] : @[ view ];
    } else {
      targets = _views.objectEnumerator.allObjects;
    }
  }
  BOOL delivered = NO;
  for (LynxPlatformView *view in targets) {
    delivered = [view sendCustomEvent:eventName data:data] || delivered;
  }
  return delivered;
}

@end

@implementation LynxPlatformView {
  FlutterLynxRootView *_rootView;
  FlutterMethodChannel *_methodChannel;
  FlutterMethodChannel *_eventChannel;
  FlutterMethodChannel *_bridgeChannel;
  BOOL _autoHeight;
  double _reportedContentHeight;
  int64_t _viewId;
  NSString *_url;
  NSString *_source;
  NSData *_templateBytes;
  NSDictionary *_initialData;
  NSString *_sourceContextId;
  NSSet<NSString *> *_allowedModules;
  NSError *_allowedModulesError;
  LynxView *_lynxView;
  LynxBridgeBinding *_bridgeBinding;
  FlutterLynxLifecycleClient *_lifecycleClient;
  NSInteger _loadGeneration;
  BOOL _loadStarted;
  BOOL _templateRequested;
  BOOL _loaded;
  BOOL _disposed;
}

- (instancetype)initWithFrame:(CGRect)frame
                       viewId:(int64_t)viewId
                       params:(NSDictionary *)params
                    messenger:(NSObject<FlutterBinaryMessenger> *)messenger {
  self = [super init];
  if (self) {
    _viewId = viewId;
    _url = [params[@"url"] isKindOfClass:[NSString class]] ? params[@"url"] : @"";
    // 文本走 source（UTF-8 编码），rspeedy/tasm 二进制模板产物走 templateBytes。
    _source = [params[@"source"] isKindOfClass:[NSString class]] ? params[@"source"] : nil;
    _templateBytes = DecodeTemplateBytesParam(params[@"templateBytes"]);
    _autoHeight = [params[@"autoHeight"] isKindOfClass:[NSNumber class]] &&
                  [params[@"autoHeight"] boolValue];
    _initialData = [self stringKeyedMap:params[@"initialData"]] ?: @{};
    _sourceContextId = [params[@"sourceContextId"] isKindOfClass:[NSString class]]
                           ? [params[@"sourceContextId"] copy]
                           : nil;
    NSError *moduleError = nil;
    _allowedModules = [self parseAllowedModules:params[@"allowedModules"] error:&moduleError];
    _allowedModulesError = moduleError;
    _rootView = [[FlutterLynxRootView alloc] initWithFrame:frame];
    _rootView.backgroundColor = UIColor.whiteColor;
    _rootView.userInteractionEnabled = YES;
    _methodChannel = [FlutterMethodChannel
        methodChannelWithName:[NSString stringWithFormat:@"com.kmanager.flutter_lynx/lynx_view_%lld", viewId]
              binaryMessenger:messenger];
    _eventChannel = [FlutterMethodChannel
        methodChannelWithName:[NSString stringWithFormat:@"com.kmanager.flutter_lynx/lynx_view_%lld_events", viewId]
              binaryMessenger:messenger];
    // 后台 Flutter 引擎也会注册插件；回调始终走当前视图所属引擎的 messenger。
    _bridgeChannel = [FlutterMethodChannel
        methodChannelWithName:@"com.kmanager.flutter_lynx/bridge"
              binaryMessenger:messenger];
    __weak typeof(self) weakSelf = self;
    [_methodChannel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
      [weakSelf handleMethodCall:call result:result];
    }];
    [[LynxPlatformViewManager shared] registerView:self forViewId:viewId];
    @try {
      [self createNativeView];
    } @catch (__unused NSException *exception) {
      [self destroyNativeView];
    }
  }
  return self;
}

- (UIView *)view {
  return _rootView;
}

- (void)createNativeView {
  if (_allowedModulesError != nil) {
    @throw [NSException exceptionWithName:NSInvalidArgumentException
                                   reason:_allowedModulesError.localizedDescription
                                 userInfo:nil];
  }
  [LynxEnv sharedInstance];
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    [[SDImageCodersManager sharedManager] addCoder:[SDImageWebPCoder sharedCoder]];
  });
  LynxBridgeBinding *binding = [[LynxBridgeBinding alloc]
      initWithAllowedModules:_allowedModules
               bridgeChannel:_bridgeChannel
             sourceContextId:_sourceContextId];
  _bridgeBinding = binding;
  FlutterLynxLifecycleClient *lifecycle = [[FlutterLynxLifecycleClient alloc] init];
  __weak typeof(self) weakSelf = self;
  lifecycle.onLoadSuccess = ^{
    [weakSelf deliver:^{
      [weakSelf emitEvent:@"onLoadSuccess" arguments:nil loaded:@YES];
    }
              binding:binding];
  };
  lifecycle.onFirstScreen = ^{
    [weakSelf deliver:^{
      [weakSelf emitEvent:@"onFirstScreen" arguments:nil loaded:nil];
    }
              binding:binding];
  };
  lifecycle.onLoadFail = ^(NSString *message) {
    [weakSelf deliver:^{
      [weakSelf emitEvent:@"onLoadFail" arguments:message loaded:@NO];
    }
              binding:binding];
  };
  _lifecycleClient = lifecycle;

  LynxConfig *config = [[LynxConfig alloc] initWithProvider:[[FlutterLynxPreparedFileProvider alloc] init]];
  [config registerModule:[LynxBridgeModule class] param:binding];
  // Lynx navigator 模块：模板 JS 的页面栈导航（navigateTo/replace/goBack）。
  [config registerModule:[NavigationModule class]];
  LynxView *nativeView = [[LynxView alloc] initWithBuilderBlock:^(LynxViewBuilder *builder) {
    builder.config = config;
    builder.screenSize = UIScreen.mainScreen.bounds.size;
    builder.fontScale = 1.0;
  }];
  nativeView.frame = _rootView.bounds;
  if (_autoHeight) {
    // 内容自适应高度：Max 模式下高度由模板内容决定（封顶 preferredMaxLayoutHeight），
    // 内容高经 root 测量后回报宿主；宽度仍随容器。autoresizing 不带 FlexibleHeight，
    // 避免容器更新前被拉伸。
    nativeView.layoutWidthMode = LynxViewSizeModeExact;
    nativeView.layoutHeightMode = LynxViewSizeModeMax;
    nativeView.preferredMaxLayoutHeight = 480;
    nativeView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  } else {
    nativeView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    nativeView.layoutWidthMode = LynxViewSizeModeExact;
    nativeView.layoutHeightMode = LynxViewSizeModeExact;
  }
  nativeView.preferredLayoutWidth = CGRectGetWidth(_rootView.bounds);
  nativeView.preferredLayoutHeight = CGRectGetHeight(_rootView.bounds);
  [nativeView addLifecycleClient:lifecycle];
  // 页面栈容器注册：LynxNavigator 的 navigate/goBack 回调进入 MiniAppLynxHolder。
  [[LynxNavigator sharedInstance] registerLynxHolder:[MiniAppLynxHolder shared]
                                        initLynxView:nativeView];
  _lynxView = nativeView;
  _rootView.lynxView = nativeView;
  _rootView.lastViewport = CGSizeZero;
  _rootView.autoHeight = _autoHeight;
  // 复用本方法前面已定义的 weakSelf；eventChannel 是 ivar，用 -> 访问。
  _rootView.onContentHeight = ^(CGFloat height) {
    LynxPlatformView *strongSelf = weakSelf;
    if (strongSelf == nil) {
      return;
    }
    [strongSelf->_eventChannel invokeMethod:@"onHeightChanged" arguments:@(height)];
  };
  [_rootView addSubview:nativeView];
  [_rootView setNeedsLayout];
}

- (void)destroyNativeView {
  [_bridgeBinding invalidate];
  _bridgeBinding = nil;
  _lifecycleClient.onLoadSuccess = nil;
  _lifecycleClient.onFirstScreen = nil;
  _lifecycleClient.onLoadFail = nil;
  _lifecycleClient = nil;
  LynxView *previous = _lynxView;
  _rootView.lynxView = nil;
  _rootView.lastViewport = CGSizeZero;
  _lynxView = nil;
  _loaded = NO;
  _templateRequested = NO;
  [previous clearForDestroy];
  [previous removeFromSuperview];
}

- (void)emitEvent:(NSString *)name arguments:(id)arguments loaded:(NSNumber *)loaded {
  if (loaded != nil) {
    _loaded = loaded.boolValue;
  }
  [_eventChannel invokeMethod:name arguments:arguments];
}

- (void)deliver:(void (^)(void))action binding:(LynxBridgeBinding *)binding {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self->_disposed && self->_loadStarted && self->_bridgeBinding == binding && binding.isActive) {
      action();
    }
  });
}

- (void)fail:(NSString *)message generation:(NSInteger)generation {
  if (!_disposed && generation == _loadGeneration) {
    _loaded = NO;
    _templateRequested = NO;
    [_eventChannel invokeMethod:@"onLoadFail" arguments:message];
  }
}

- (NSURL *)preparedFileURL:(NSString *)value error:(NSError **)error {
  if ([value hasPrefix:@"file:"]) {
    NSURL *url = [NSURL URLWithString:value];
    if (url.scheme.length == 0 || ![url.scheme isEqualToString:@"file"] || url.host.length > 0 ||
        url.query.length > 0 || url.fragment.length > 0) {
      if (error) {
        *error = [self error:@"Lynx only accepts a prepared local file URL"];
      }
      return nil;
    }
    return url;
  }
  if (value.length == 0 || ![value hasPrefix:@"/"]) {
    if (error) {
      *error = [self error:@"Lynx only accepts an absolute prepared local file path"];
    }
    return nil;
  }
  return [NSURL fileURLWithPath:value];
}

- (NSError *)error:(NSString *)message {
  return [NSError errorWithDomain:@"com.kmanager.flutter_lynx"
                             code:400
                         userInfo:@{NSLocalizedDescriptionKey : message}];
}

- (void)reload:(FlutterMethodCall *)call result:(FlutterResult)result {
  _loadGeneration += 1;
  NSInteger generation = _loadGeneration;
  _loadStarted = YES;
  @try {
    [self destroyNativeView];
    NSDictionary *args = @{};
    if (call.arguments != nil && call.arguments != [NSNull null]) {
      args = [self stringKeyedMap:call.arguments];
      if (args == nil) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"reload requires string-keyed arguments"
                                     userInfo:nil];
      }
    }
    NSString *nextUrl = _url;
    if (args[@"url"] != nil) {
      if (![args[@"url"] isKindOfClass:[NSString class]]) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"url must be a string" userInfo:nil];
      }
      nextUrl = args[@"url"];
    }
    NSDictionary *nextData = _initialData;
    if (args[@"initialData"] != nil) {
      nextData = [self stringKeyedMap:args[@"initialData"]];
      if (nextData == nil) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"initialData must be an object with string keys"
                                     userInfo:nil];
      }
    }
    NSError *fileError = nil;
    NSURL *fileURL = [self preparedFileURL:nextUrl error:&fileError];
    if (fileURL == nil) {
      @throw [NSException exceptionWithName:NSInvalidArgumentException
                                     reason:fileError.localizedDescription
                                   userInfo:nil];
    }
    _url = nextUrl;
    // 文件链路接管后丢弃直喂内容，各模式不混用。
    _source = nil;
    _templateBytes = nil;
    _initialData = nextData;
    [self createNativeView];
    LynxView *targetView = _lynxView;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSError *readError = nil;
      NSData *bytes = [NSData dataWithContentsOfURL:fileURL options:0 error:&readError];
      if (readError != nil || bytes.length == 0 || bytes.length > kMaxBundleBytes) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self fail:(readError.localizedDescription ?: @"Prepared Lynx bundle is missing, empty or larger than 10 MiB")
          generation:generation];
        });
        return;
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_disposed || generation != self->_loadGeneration || self->_lynxView != targetView) {
          return;
        }
        @try {
          self->_templateRequested = YES;
          LynxTemplateData *data = [[LynxTemplateData alloc] initWithDictionary:nextData];
          [targetView loadTemplate:bytes withURL:fileURL.absoluteString initData:data];
        } @catch (NSException *exception) {
          [self fail:(exception.reason ?: @"Unable to render the Lynx bundle") generation:generation];
        }
      });
    });
    result(@YES);
  } @catch (NSException *exception) {
    [self fail:(exception.reason ?: @"Unable to load the Lynx bundle") generation:generation];
    result([FlutterError errorWithCode:@"lynx_load_failed" message:exception.reason details:nil]);
  }
}

- (void)loadFromSource:(FlutterMethodCall *)call result:(FlutterResult)result {
  _loadGeneration += 1;
  NSInteger generation = _loadGeneration;
  _loadStarted = YES;
  @try {
    // 先解析参数再拆视图：入参不合法时保留旧画面，等 onLoadFail 后由宿主决定重试。
    NSDictionary *args = @{};
    if (call.arguments != nil && call.arguments != [NSNull null]) {
      args = [self stringKeyedMap:call.arguments];
      if (args == nil) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"loadFromSource requires string-keyed arguments"
                                     userInfo:nil];
      }
    }
    id sourceArg = args[@"source"];
    id bytesArg = args[@"templateBytes"];
    NSString *nextSource = nil;
    NSData *inlineBytes = nil;
    if (sourceArg != nil) {
      if (![sourceArg isKindOfClass:[NSString class]]) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"source must be a string"
                                     userInfo:nil];
      }
      nextSource = sourceArg;
      inlineBytes = [nextSource dataUsingEncoding:NSUTF8StringEncoding];
    } else if (bytesArg != nil) {
      NSData *decoded = DecodeTemplateBytesParam(bytesArg);
      if (decoded == nil) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"templateBytes must be raw bytes"
                                     userInfo:nil];
      }
      inlineBytes = decoded;
    }
    if (inlineBytes.length == 0 || inlineBytes.length > kMaxBundleBytes) {
      @throw [NSException exceptionWithName:NSInvalidArgumentException
                                     reason:@"Lynx template source is empty or larger than 10 MiB"
                                   userInfo:nil];
    }
    NSDictionary *nextData = _initialData;
    if (args[@"initialData"] != nil) {
      nextData = [self stringKeyedMap:args[@"initialData"]];
      if (nextData == nil) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"initialData must be an object with string keys"
                                     userInfo:nil];
      }
    }
    [self destroyNativeView];
    // 两种装载模式互斥：直喂后清空文件 URL，避免后续无参 reload 拿到过期文件。
    _url = @"";
    _source = nextSource;
    _templateBytes = nextSource == nil ? inlineBytes : nil;
    _initialData = nextData;
    [self createNativeView];
    LynxView *targetView = _lynxView;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (self->_disposed || generation != self->_loadGeneration || self->_lynxView != targetView) {
        return;
      }
      @try {
        self->_templateRequested = YES;
        LynxTemplateData *data = [[LynxTemplateData alloc] initWithDictionary:nextData];
        // 与文件链路同一官方 bytes 直喂入口 loadTemplate:withURL:initData:，URL 换成内联占位。
        [targetView loadTemplate:inlineBytes withURL:kInlineTemplateBaseURL initData:data];
      } @catch (NSException *exception) {
        [self fail:(exception.reason ?: @"Unable to render the Lynx template source") generation:generation];
      }
    });
    // Scheduling acknowledgement only; success is exclusively a lifecycle client callback.
    result(@YES);
  } @catch (NSException *exception) {
    [self fail:(exception.reason ?: @"Unable to load the Lynx template source") generation:generation];
    result([FlutterError errorWithCode:@"lynx_load_failed" message:exception.reason details:nil]);
  }
}

- (BOOL)sendCustomEvent:(NSString *)eventName data:(NSDictionary *)data {
  if (_lynxView == nil || _disposed || !_loaded || eventName.length == 0) {
    return NO;
  }
  [_lynxView sendGlobalEvent:@"onFlutterEvent"
                  withParams:@[ @{
                    @"name" : eventName,
                    @"data" : data ?: @{},
                  } ]];
  return YES;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (_disposed) {
    result([FlutterError errorWithCode:@"lynx_disposed" message:@"Lynx view has been disposed" details:nil]);
    return;
  }
  @try {
    if ([call.method isEqualToString:@"reload"]) {
      [self reload:call result:result];
      return;
    }
    if ([call.method isEqualToString:@"loadFromSource"]) {
      [self loadFromSource:call result:result];
      return;
    }
    if ([call.method isEqualToString:@"updateData"]) {
      NSDictionary *data = [self stringKeyedMap:call.arguments];
      if (data == nil) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"updateData requires string-keyed data"
                                     userInfo:nil];
      }
      if (!_templateRequested || _lynxView == nil) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"Lynx template has not been requested"
                                     userInfo:nil];
      }
      [_lynxView updateDataWithDictionary:data];
      NSMutableDictionary *merged = [_initialData mutableCopy] ?: [NSMutableDictionary dictionary];
      [merged addEntriesFromDictionary:data];
      _initialData = [merged copy];
      result(@YES);
      return;
    }
    if ([call.method isEqualToString:@"sendCustomEvent"]) {
      NSDictionary *args = [call.arguments isKindOfClass:[NSDictionary class]] ? call.arguments : @{};
      NSString *name = [args[@"eventName"] isKindOfClass:[NSString class]] ? args[@"eventName"] : nil;
      NSDictionary *data = [self stringKeyedMap:args[@"data"]];
      if (name.length == 0) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"eventName is required" userInfo:nil];
      }
      if (data == nil) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"event data must have string keys"
                                     userInfo:nil];
      }
      if (![self sendCustomEvent:name data:data]) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"Lynx view is not loaded or event name is empty"
                                     userInfo:nil];
      }
      result(@YES);
      return;
    }
    result(FlutterMethodNotImplemented);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"lynx_call_failed" message:exception.reason details:nil]);
  }
}

- (void)dealloc {
  if (_disposed) {
    return;
  }
  _disposed = YES;
  _loadGeneration += 1;
  [[LynxPlatformViewManager shared] unregisterView:self forViewId:_viewId];
  [_methodChannel setMethodCallHandler:nil];
  [self destroyNativeView];
}

- (NSDictionary *)stringKeyedMap:(id)value {
  if (value == nil || value == [NSNull null]) {
    return nil;
  }
  if (![value isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  NSDictionary *map = value;
  for (id key in map) {
    if (![key isKindOfClass:[NSString class]]) {
      return nil;
    }
  }
  return map;
}

- (NSSet<NSString *> *)parseAllowedModules:(id)value error:(NSError **)error {
  if (![value isKindOfClass:[NSArray class]]) {
    if (error) {
      *error = [self error:@"allowedModules must contain 1 to 32 module names"];
    }
    return nil;
  }
  NSArray *items = value;
  if (items.count < 1 || items.count > 32) {
    if (error) {
      *error = [self error:@"allowedModules must contain 1 to 32 module names"];
    }
    return nil;
  }
  NSMutableSet<NSString *> *modules = [NSMutableSet set];
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:kModuleNamePattern options:0 error:nil];
  for (id item in items) {
    if (![item isKindOfClass:[NSString class]] ||
        [regex numberOfMatchesInString:item options:0 range:NSMakeRange(0, [item length])] != 1) {
      if (error) {
        *error = [self error:@"allowedModules contains an invalid module name"];
      }
      return nil;
    }
    [modules addObject:item];
  }
  return [modules copy];
}

@end

@implementation LynxPlatformViewFactory {
  NSObject<FlutterBinaryMessenger> *_messenger;
}

- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger {
  self = [super init];
  if (self) {
    _messenger = messenger;
  }
  return self;
}

- (NSObject<FlutterMessageCodec> *)createArgsCodec {
  return [FlutterStandardMessageCodec sharedInstance];
}

- (NSObject<FlutterPlatformView> *)createWithFrame:(CGRect)frame
                                    viewIdentifier:(int64_t)viewId
                                         arguments:(id)args {
  NSDictionary *params = [args isKindOfClass:[NSDictionary class]] ? args : @{};
  return [[LynxPlatformView alloc] initWithFrame:frame viewId:viewId params:params messenger:_messenger];
}

@end
