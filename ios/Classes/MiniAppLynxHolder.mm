#import "MiniAppLynxHolder.h"

#import <Lynx/LynxTemplateProvider.h>

#import "LynxPlatformView.h"

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

NS_ASSUME_NONNULL_END

@implementation MiniAppLynxHolder {
  /// 页面栈（栈底在前）；P1 仅维护状态，P2 对接真实视图挂载。
  NSMutableArray<NSString *> *_pageStack;
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
    _pageStack = [NSMutableArray array];
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

- (LynxView *)createLynxView:(LynxRoute *)route {
  if (self.preparedBundlePath.length == 0) {
    NSLog(@"[MiniAppLynxHolder] navigate ignored: no prepared bundle");
    return nil;
  }
  LynxConfig *config = [[LynxConfig alloc]
      initWithProvider:[[MiniAppHolderTemplateProvider alloc]
                           initWithPath:self.preparedBundlePath]];
  LynxView *view = [[LynxView alloc] initWithBuilderBlock:^(LynxViewBuilder *builder) {
    builder.config = config;
    builder.screenSize = UIScreen.mainScreen.bounds.size;
    builder.fontScale = 1.0;
  }];
  view.frame = UIScreen.mainScreen.bounds;
  view.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  // 页面路由 = 初始 path：route 名即页面路径，模板入口按 path 渲染。
  NSMutableDictionary *init = [NSMutableDictionary dictionary];
  init[@"initialPath"] = route.routeName ?: @"/";
  if (route.param) {
    init[@"routeParams"] = route.param;
  }
  [view loadTemplateFromURL:[@"file://" stringByAppendingString:self.preparedBundlePath]
                  initData:[[LynxTemplateData alloc] initWithDictionary:init]];
  [_pageStack addObject:route.routeName ?: @"page"];
  NSLog(@"[MiniAppLynxHolder] navigate route=%@ stack=%lu",
        route.routeName ?: @"", (unsigned long)_pageStack.count);
  return view;
}

- (void)showLynxView:(LynxView *)lynxView name:(NSString *)name {
  // 页面栈显示：挂入容器（navigate 出的页面已在创建时挂入，此处幂等）。
  if (lynxView.superview != self.containerView) {
    [self.containerView addSubview:lynxView];
    lynxView.frame = self.containerView.bounds;
    lynxView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  }
}

- (void)hideLynxView:(LynxView *)lynxView {
  // goBack 回退：移除栈顶视图（返回上层页面仍由 goBack 后的 show 挂回），
  // 并同步页面栈深度，供栈底判定。
  [lynxView removeFromSuperview];
  if (_pageStack.count > 1) {
    [_pageStack removeLastObject];
  }
}

#pragma mark - 栈底通知

- (void)notifyStackBottomBack {
  if (self.onStackBottomBack) {
    self.onStackBottomBack();
  }
}

@end
