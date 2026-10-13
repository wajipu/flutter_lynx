#import "MiniAppLynxHolder.h"

#import <Lynx/LynxTemplateProvider.h>
#import <Lynx/NavigationModule.h>

#import "LynxBridgeModule.h"

NS_ASSUME_NONNULL_BEGIN

NSString* const MiniAppLynxHolderCurrentBundlePathDidChange =
    @"MiniAppLynxHolderCurrentBundlePathDidChange";

/// 与 FlutterLynxPreparedFileProvider 同源的模板读取；导航出的新页面
/// 与来源页共用同一 bundle 文件。
@interface MiniAppHolderTemplateProvider : NSObject <LynxTemplateProvider>
- (instancetype)initWithPath:(NSString *)path;
@end

@implementation MiniAppHolderTemplateProvider {
  NSString *_path;
}

- (instancetype)initWithPath:(NSString *)path {
  if (self = [super init]) {
    _path = [path copy];
  }
  return self;
}

- (void)loadTemplateWithUrl:(NSString *)url
                 onComplete:(LynxTemplateLoadBlock)callback {
  NSData *data = [NSData dataWithContentsOfFile:_path];
  if (data.length == 0) {
    callback(nil,
             [NSError errorWithDomain:@"com.kmanager.flutter_lynx"
                                 code:404
                             userInfo:@{NSLocalizedDescriptionKey :
                                            @"mini app holder bundle missing"}]);
    return;
  }
  callback(data, nil);
}

@end

@interface MiniAppLynxHolder ()
- (BOOL)activateLynxView:(LynxView *)view;
@end

NS_ASSUME_NONNULL_END

@implementation MiniAppLynxHolder {
  NSMutableArray<LynxView *> *_lynxViews;
  NSMapTable<LynxView *, LynxBridgeBinding *> *_bindings;
  NSMapTable<LynxView *, NSDictionary *> *_appliedData;
  __weak LynxView *_visibleView;
  BOOL _invalidated;
}

+ (instancetype)shared {
  static MiniAppLynxHolder *instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[MiniAppLynxHolder alloc] init];
  });
  return instance;
}

- (instancetype)init {
  if (self = [super init]) {
    _lynxViews = [NSMutableArray array];
    _allowedModules = [NSSet set];
    _bindings = [NSMapTable weakToStrongObjectsMapTable];
    _appliedData = [NSMapTable weakToStrongObjectsMapTable];
  }
  return self;
}

- (void)setPreparedBundlePath:(NSString *)preparedBundlePath {
  _preparedBundlePath = [preparedBundlePath copy];
  [[NSNotificationCenter defaultCenter]
      postNotificationName:MiniAppLynxHolderCurrentBundlePathDidChange
                    object:self];
}

#pragma mark - LynxHolder

- (LynxBridgeBinding *)createBridgeBinding {
  LynxBridgeBinding *binding = [[LynxBridgeBinding alloc]
      initWithAllowedModules:self.allowedModules
               bridgeChannel:self.bridgeChannel
             sourceContextId:self.sourceContextId];
  __weak MiniAppLynxHolder *weakSelf = self;
  binding.onGoBack = ^{
    [weakSelf goBack];
  };
  binding.storeScopeObserver = ^(NSString *sourceContextId, NSNumber *requestedRevision, NSDictionary *selection) {
    MiniAppLynxHolder *holder = weakSelf;
    if (holder == nil || holder->_invalidated || ![holder.sourceContextId isEqualToString:sourceContextId]) {
      return;
    }
    NSNumber *currentRevision = holder.initialTemplateData[@"contextRevision"];
    if (![currentRevision isKindOfClass:[NSNumber class]] || ![currentRevision isEqualToNumber:requestedRevision]) {
      return;
    }
    NSMutableDictionary *latest = [holder.initialTemplateData mutableCopy];
    latest[@"contextRevision"] = selection[@"contextRevision"];
    latest[@"storeScopeLabel"] = selection[@"storeScopeLabel"];
    holder.initialTemplateData = latest;
  };
  return binding;
}

- (void)trackLynxView:(LynxView *)view
              binding:(LynxBridgeBinding *)binding
         templateData:(NSDictionary *)templateData {
  [_lynxViews addObject:view];
  [_bindings setObject:binding forKey:view];
  [_appliedData setObject:[templateData copy] forKey:view];
  _visibleView = view;
}

- (NSUInteger)pageCount {
  return _lynxViews.count;
}

- (NSDictionary *)templateDataForView:(LynxView *)view {
  NSMutableDictionary *data = [NSMutableDictionary dictionaryWithDictionary:self.initialTemplateData ?: @{}];
  NSDictionary *applied = [_appliedData objectForKey:view];
  for (NSString *key in @[@"initialPath", @"routeParams"]) {
    if (applied[key] != nil) {
      data[key] = applied[key];
    } else {
      [data removeObjectForKey:key];
    }
  }
  return data;
}

- (void)applyLatestDataToView:(LynxView *)view preserveScope:(BOOL)preserveScope {
  NSDictionary *applied = [_appliedData objectForKey:view];
  if (applied == nil) {
    return;
  }
  NSMutableDictionary *data = [[self templateDataForView:view] mutableCopy];
  if (preserveScope && ![applied[@"contextRevision"] isEqual:data[@"contextRevision"]]) {
    for (NSString *key in @[@"contextRevision", @"storeScopeLabel"]) {
      if (applied[key] != nil) {
        data[key] = applied[key];
      } else {
        [data removeObjectForKey:key];
      }
    }
  }
  if (![applied isEqualToDictionary:data]) {
    [view updateDataWithDictionary:data];
    [_appliedData setObject:[data copy] forKey:view];
  }
}

- (void)updateTemplateData:(NSDictionary *)data {
  NSMutableDictionary *latest = [NSMutableDictionary dictionaryWithDictionary:self.initialTemplateData ?: @{}];
  [latest addEntriesFromDictionary:data];
  NSNumber *currentRevision = self.initialTemplateData[@"contextRevision"];
  NSNumber *incomingRevision = data[@"contextRevision"];
  if ([currentRevision isKindOfClass:[NSNumber class]] && [incomingRevision isKindOfClass:[NSNumber class]] &&
      [incomingRevision compare:currentRevision] == NSOrderedAscending) {
    latest[@"contextRevision"] = currentRevision;
    latest[@"storeScopeLabel"] = self.initialTemplateData[@"storeScopeLabel"];
  }
  self.initialTemplateData = latest;
  if (_visibleView != nil) {
    [self applyLatestDataToView:_visibleView preserveScope:YES];
  }
}

- (void)invalidateBridgeBindings {
  _invalidated = YES;
  for (LynxBridgeBinding *binding in _bindings.objectEnumerator) {
    [binding invalidate];
  }
}

- (void)goBack {
  if (_invalidated) {
    return;
  }
  LynxView *previous = _lynxViews.count > 1 ? _lynxViews[_lynxViews.count - 2] : nil;
  [[LynxNavigator sharedInstance] goBack];
  // Lynx 4.1 CardManager 的重复 ivar 使 pop 后的 invokeOnShow 读不到父页。
  if (previous != nil && _visibleView != previous) {
    [previous onEnterForeground];
  }
}

- (LynxView *)createLynxView:(LynxRoute *)route {
  if (_invalidated || self.preparedBundlePath.length == 0) {
    NSLog(@"[MiniAppLynxHolder] navigate ignored: no prepared bundle");
    return nil;
  }
  LynxConfig *config = [[LynxConfig alloc]
      initWithProvider:[[MiniAppHolderTemplateProvider alloc]
                           initWithPath:self.preparedBundlePath]];
  LynxBridgeBinding *binding = [self createBridgeBinding];
  [config registerModule:[LynxBridgeModule class] param:binding];
  [config registerModule:[MiniAppStackNavigationModule class] param:binding];
  MiniAppStackLynxView *view = [[MiniAppStackLynxView alloc] initWithBuilderBlock:^(LynxViewBuilder *builder) {
    builder.config = config;
    builder.screenSize = UIScreen.mainScreen.bounds.size;
    builder.fontScale = 1.0;
  }];
  view.holder = self;
  view.frame = self.containerView.bounds;
  view.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  view.layoutWidthMode = LynxViewSizeModeExact;
  view.layoutHeightMode = LynxViewSizeModeExact;
  view.preferredLayoutWidth = CGRectGetWidth(self.containerView.bounds);
  view.preferredLayoutHeight = CGRectGetHeight(self.containerView.bounds);
  // 页面路由 = 初始 path：route 名即页面路径，模板入口按 path 渲染。
  // 主题/palette/安全区等与首页共享同一上下文，仅 path 与路由参数不同。
  NSMutableDictionary *init = [NSMutableDictionary
      dictionaryWithDictionary:self.initialTemplateData ?: @{}];
  init[@"initialPath"] = route.routeName ?: @"/";
  [init removeObjectForKey:@"routeParams"];
  if (route.param) {
    init[@"routeParams"] = route.param;
  }
  // bytes 直喂（与主通道一致）：loadTemplateFromURL 走 provider 同步回调，
  // 在 navigate 持锁路径上存在重入死锁风险。
  NSData *bytes = [NSData dataWithContentsOfFile:self.preparedBundlePath];
  NSString *fileURL = [@"file://" stringByAppendingString:self.preparedBundlePath];
  [view loadTemplate:bytes
              withURL:fileURL
             initData:[[LynxTemplateData alloc] initWithDictionary:init]];
  [self trackLynxView:view binding:binding templateData:init];
  // 引擎的 show 回调在模板异步加载完成后才触发；新页创建即挂入容器，
  // 否则加载期间页面不可见（表现为点击无反应）。
  if (self.containerView) {
    view.frame = self.containerView.bounds;
    view.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.containerView addSubview:view];
  }
  NSLog(@"[MiniAppLynxHolder] navigate route=%@ stack=%lu",
        route.routeName ?: @"", (unsigned long)self.pageCount);
  return view;
}

- (void)showLynxView:(LynxView *)lynxView name:(NSString *)name {
  [self activateLynxView:lynxView];
}

- (BOOL)activateLynxView:(LynxView *)lynxView {
  if (_invalidated) {
    return NO;
  }
  NSUInteger index = [_lynxViews indexOfObjectIdenticalTo:lynxView];
  if (index == NSNotFound) {
    return NO;
  }
  BOOL returning = index + 1 < _lynxViews.count;
  if (returning) {
    NSRange poppedRange = NSMakeRange(index + 1, _lynxViews.count - index - 1);
    for (LynxView *popped in [_lynxViews subarrayWithRange:poppedRange]) {
      [[_bindings objectForKey:popped] invalidate];
      [_bindings removeObjectForKey:popped];
      [_appliedData removeObjectForKey:popped];
      [popped removeFromSuperview];
    }
    [_lynxViews removeObjectsInRange:poppedRange];
  }
  // Lynx 返回已挂载的父页时只调用 onEnterForeground，必须先同步门店版本。
  // 首次/重复显示当前页保留请求来源版本，交由 storeSelect 原回调确认。
  [self applyLatestDataToView:lynxView preserveScope:!returning];
  _visibleView = lynxView;
  // 页面栈显示：挂入容器（navigate 出的页面已在创建时挂入，此处幂等）。
  if (lynxView.superview != self.containerView) {
    [self.containerView addSubview:lynxView];
    lynxView.frame = self.containerView.bounds;
    lynxView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  }
  lynxView.hidden = NO;
  [self.containerView bringSubviewToFront:lynxView];
  return YES;
}

- (void)hideLynxView:(LynxView *)lynxView {
  if ([_lynxViews indexOfObjectIdenticalTo:lynxView] == NSNotFound) {
    return;
  }
  if (_visibleView == lynxView) {
    _visibleView = nil;
  }
  // 父页激活时统一回收被 pop 的后继；迟到的退出动画回调可重复调用此处。
  [lynxView removeFromSuperview];
}

#pragma mark - 栈底通知

- (void)notifyStackBottomBack {
  if (self.onStackBottomBack) {
    self.onStackBottomBack();
  }
}

@end

@implementation MiniAppStackLynxView

- (void)onEnterForeground {
  if ([self.holder activateLynxView:self]) {
    [super onEnterForeground];
  }
}

@end

@implementation MiniAppStackNavigationModule {
  LynxBridgeBinding *_binding;
}

- (instancetype)initWithParam:(id)param {
  if (self = [super init]) {
    _binding = param;
  }
  return self;
}

- (void)goBack {
  LynxBridgeBinding *binding = _binding;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (binding.isActive && binding.onGoBack) {
      binding.onGoBack();
    }
  });
}

@end
