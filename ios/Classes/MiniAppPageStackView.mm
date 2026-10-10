#import "MiniAppPageStackView.h"

#import <Lynx/LynxConfig.h>
#import <Lynx/LynxHolder.h>
#import <Lynx/LynxNavigator.h>
#import <Lynx/LynxRoute.h>
#import <Lynx/LynxTemplateProvider.h>
#import <Lynx/LynxView.h>
#import <Lynx/LynxViewBuilder.h>
#import <Lynx/NavigationModule.h>
#import "LynxBridgeModule.h"

#import "FlutterLynxPlugin.h"
#import "MiniAppLynxHolder.h"

NS_ASSUME_NONNULL_BEGIN

// 页面栈各页共用的模板读取：直接读宿主准备好的 bundle 文件。
@interface MiniAppStackTemplateProvider : NSObject <LynxTemplateProvider>
- (instancetype)initWithPath:(NSString *)path;
@end

@implementation MiniAppStackTemplateProvider {
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
                                            @"page stack bundle missing"}]);
    return;
  }
  callback(data, nil);
}

@end

NS_ASSUME_NONNULL_END


@interface MiniAppPageStackView () <UITextFieldDelegate>
@end

@implementation MiniAppPageStackView {
  UIView *_root;
  NSString *_bundlePath;
  NSDictionary *_initialData;
  NSSet<NSString *> *_allowedModules;
  BOOL _applySafeArea;
  FlutterMethodChannel *_stackChannel;
}

- (instancetype)initWithFrame:(CGRect)frame
                       viewId:(int64_t)viewId
                       params:(NSDictionary *)params
                    messenger:(NSObject<FlutterBinaryMessenger> *)messenger {
  if (self = [super init]) {
    _bundlePath = [params[@"bundlePath"] isKindOfClass:[NSString class]]
                      ? params[@"bundlePath"]
                      : @"";
    _initialData = [self stringKeyedMap:params[@"initialData"]] ?: @{};
    _applySafeArea = [params[@"applySafeArea"] isKindOfClass:[NSNumber class]]
                         ? [params[@"applySafeArea"] boolValue]
                         : YES;
    _allowedModules = [self parseAllowedModules:params[@"allowedModules"]];

    _root = [[UIView alloc] initWithFrame:frame];
    _root.backgroundColor = UIColor.whiteColor;

    // 同步 prepared bundle 路径给页面栈容器（Dart 经 creationParams 传入；
    // PlatformView 的模板加载时机晚于本容器创建，不能依赖其回写）。
    if (_bundlePath.length > 0) {
      [MiniAppLynxHolder shared].preparedBundlePath = _bundlePath;
    }

    // native → Flutter 的单向通知通道：栈底 goBack 时请求关闭容器页。
    _stackChannel = [FlutterMethodChannel
        methodChannelWithName:
            [NSString stringWithFormat:@"com.kmanager.flutter_lynx/page_stack_%lld",
                                       viewId]
              binaryMessenger:messenger];

    [self bootstrapFirstPage];
    [self installEdgeBackGesture];
    [[LynxNavigator sharedInstance]
        registerLynxHolder:[MiniAppLynxHolder shared]
              initLynxView:[self topLynxView]];
  }
  return self;
}

- (UIView *)view {
  return _root;
}

- (void)bootstrapFirstPage {
  LynxView *first = [self createLynxViewWithInitialData:_initialData];
  [_root addSubview:first];
  first.frame = _root.bounds;
  first.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [MiniAppLynxHolder shared].containerView = _root;
}

- (LynxView *)createLynxViewWithInitialData:(NSDictionary *)initialData {
  LynxConfig *config = [[LynxConfig alloc]
      initWithProvider:[[MiniAppStackTemplateProvider alloc]
                           initWithPath:_bundlePath]];
  // 页面栈各页共享 bridge 转发通道（Dart 侧 LynxBridge 单例全局分发），
  // 白名单与整页单页模式一致，由 creationParams 传入。
  LynxBridgeBinding *binding = [[LynxBridgeBinding alloc]
      initWithAllowedModules:_allowedModules
               bridgeChannel:[FlutterLynxPlugin bridgeChannel]];
  [config registerModule:[LynxBridgeModule class] param:binding];
  [config registerModule:[NavigationModule class]];

  LynxView *view = [[LynxView alloc] initWithBuilderBlock:^(LynxViewBuilder *builder) {
    builder.config = config;
    builder.screenSize = UIScreen.mainScreen.bounds.size;
    builder.fontScale = 1.0;
  }];
  // 初始数据经 loadTemplate 的 initData 参数注入（LynxView 无独立
  // updateInitialData 入口）；模板文件字节直喂。
  NSData *bytes = [NSData dataWithContentsOfFile:[MiniAppLynxHolder shared].preparedBundlePath];
  NSMutableDictionary *init = [NSMutableDictionary dictionaryWithDictionary:initialData];
  init[@"applySafeArea"] = @(_applySafeArea);
  NSString *url = [@"file://" stringByAppendingString:[MiniAppLynxHolder shared].preparedBundlePath];
  [view loadTemplate:bytes
              withURL:url
             initData:[[LynxTemplateData alloc] initWithDictionary:init]];
  return view;
}

- (NSSet<NSString *> *)parseAllowedModules:(id)value {
  if (![value isKindOfClass:[NSArray class]]) {
    return [NSSet set];
  }
  NSMutableSet<NSString *> *set = [NSMutableSet set];
  for (id item in (NSArray *)value) {
    if ([item isKindOfClass:[NSString class]]) {
      [set addObject:item];
    }
  }
  return set;
}

- (NSDictionary<NSString *, NSString *> *)stringKeyedMap:(id)value {
  if (![value isKindOfClass:[NSDictionary class]]) {
    return @{};
  }
  NSMutableDictionary<NSString *, NSString *> *out = [NSMutableDictionary dictionary];
  [(NSDictionary *)value
      enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([key isKindOfClass:[NSString class]] && [obj isKindOfClass:[NSString class]]) {
          out[key] = obj;
        }
      }];
  return out;
}

- (LynxView *)topLynxView {
  return _root.subviews.lastObject;
}

#pragma mark - 背滑手势（原生，直接驱动页面栈）

- (void)installEdgeBackGesture {
  UIScreenEdgePanGestureRecognizer *edge =
      [[UIScreenEdgePanGestureRecognizer alloc]
          initWithTarget:self
                  action:@selector(handleEdgePan:)];
  edge.edges = UIRectEdgeLeft;
  [_root addGestureRecognizer:edge];
}

- (void)handleEdgePan:(UIScreenEdgePanGestureRecognizer *)gesture {
  if (gesture.state != UIGestureRecognizerStateEnded) {
    return;
  }
  if ([MiniAppLynxHolder shared].pageCount > 1) {
    // 有上级页面：交还页面栈回退。
    [[LynxNavigator sharedInstance] goBack];
  } else {
    // 栈底：通知 Flutter 关闭整页容器。
    [_stackChannel invokeMethod:@"dismiss" arguments:nil];
  }
}

@end

@implementation MiniAppPageStackFactory
- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger {
  return [super init];
}

- (NSObject<FlutterPlatformView> *)createWithFrame:(CGRect)frame
                                    viewIdentifier:(int64_t)viewId
                                         arguments:(id _Nullable)args
                                   binaryMessenger:(NSObject<FlutterBinaryMessenger> *)messenger {
  return [[MiniAppPageStackView alloc] initWithFrame:frame
                                              viewId:viewId
                                              params:args
                                            messenger:messenger];
}

- (NSObject<FlutterPlatformView> *)createWithFrame:(CGRect)frame
                                    viewIdentifier:(int64_t)viewId
                                         arguments:(id _Nullable)args {
  return [self createWithFrame:frame viewIdentifier:viewId arguments:args binaryMessenger:nil];
}

@end
