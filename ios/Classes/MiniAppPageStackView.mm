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
             [NSError errorWithDomain:@"io.github.wajipu.flutter_lynx"
                                 code:404
                             userInfo:@{NSLocalizedDescriptionKey :
                                            @"page stack bundle missing"}]);
    return;
  }
  callback(data, nil);
}

@end

NS_ASSUME_NONNULL_END

@interface MiniAppPageStackRootView : UIView
@property(nonatomic, assign) CGSize lastViewport;
@end

@implementation MiniAppPageStackRootView
- (void)didAddSubview:(UIView *)subview {
  [super didAddSubview:subview];
  // 导航新增页也要接收容器尺寸，不能沿用创建时的 UIScreen 尺寸。
  self.lastViewport = CGSizeZero;
  [self setNeedsLayout];
}

- (void)layoutSubviews {
  [super layoutSubviews];
  CGSize size = self.bounds.size;
  if (size.width < 1 || size.height < 1 ||
      CGSizeEqualToSize(size, self.lastViewport)) {
    return;
  }
  self.lastViewport = size;
  // UiKitView 常以零尺寸创建；与单页容器一致，在布局后显式同步真实 viewport。
  for (UIView *subview in self.subviews) {
    if ([subview isKindOfClass:[LynxView class]]) {
      LynxView *view = (LynxView *)subview;
      view.frame = self.bounds;
      [view updateViewportWithPreferredLayoutWidth:size.width
                           preferredLayoutHeight:size.height
                                      needLayout:YES];
    }
  }
}
@end

@interface MiniAppPageStackView () <UITextFieldDelegate>
@end

@implementation MiniAppPageStackView {
  MiniAppPageStackRootView *_root;
  NSString *_bundlePath;
  NSDictionary *_initialData;
  NSSet<NSString *> *_allowedModules;
  BOOL _applySafeArea;
  FlutterMethodChannel *_stackChannel;
  FlutterMethodChannel *_bridgeChannel;
  NSString *_sourceContextId;
  LynxBridgeBinding *_bridgeBinding;
  MiniAppLynxHolder *_holder;
  // 交互式返回拖拽中跟手的栈顶视图。
  LynxView *_dragTopView;
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
    _sourceContextId = [params[@"sourceContextId"] isKindOfClass:[NSString class]]
                           ? [params[@"sourceContextId"] copy]
                           : nil;
    _applySafeArea = [params[@"applySafeArea"] isKindOfClass:[NSNumber class]]
                         ? [params[@"applySafeArea"] boolValue]
                         : YES;
    _allowedModules = [self parseAllowedModules:params[@"allowedModules"]];
    NSMutableDictionary *templateData = [_initialData mutableCopy];
    templateData[@"applySafeArea"] = @(_applySafeArea ? 1 : 0);
    _initialData = [templateData copy];
    _holder = [[MiniAppLynxHolder alloc] init];

    _root = [[MiniAppPageStackRootView alloc] initWithFrame:frame];
    _root.backgroundColor = UIColor.whiteColor;

    // 同步 prepared bundle 路径给页面栈容器（Dart 经 creationParams 传入；
    // PlatformView 的模板加载时机晚于本容器创建，不能依赖其回写）。
    if (_bundlePath.length > 0) {
      _holder.preparedBundlePath = _bundlePath;
    }

    // native → Flutter 的单向通知通道：栈底 goBack 时请求关闭容器页。
    _stackChannel = [FlutterMethodChannel
        methodChannelWithName:
            [NSString stringWithFormat:@"io.github.wajipu.flutter_lynx/page_stack_%lld",
                                       viewId]
              binaryMessenger:messenger];
    // 后台引擎也会注册插件，页面调用必须绑定当前视图所属引擎。
    _bridgeChannel = [FlutterMethodChannel
        methodChannelWithName:@"io.github.wajipu.flutter_lynx/bridge"
              binaryMessenger:messenger];
    _holder.allowedModules = _allowedModules;
    _holder.sourceContextId = _sourceContextId;
    _holder.bridgeChannel = _bridgeChannel;
    __weak typeof(self) weakSelf = self;
    [_stackChannel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
      MiniAppPageStackView *strongSelf = weakSelf;
      if (strongSelf == nil) {
        result([FlutterError errorWithCode:@"lynx_disposed" message:@"Page stack has been disposed" details:nil]);
      } else if ([call.method isEqualToString:@"updateData"]) {
        if (![call.arguments isKindOfClass:[NSDictionary class]]) {
          result([FlutterError errorWithCode:@"lynx_invalid_data" message:@"updateData requires string-keyed data" details:nil]);
          return;
        }
        for (id key in (NSDictionary *)call.arguments) {
          if (![key isKindOfClass:[NSString class]]) {
            result([FlutterError errorWithCode:@"lynx_invalid_data" message:@"updateData requires string-keyed data" details:nil]);
            return;
          }
        }
        NSMutableDictionary *data = [call.arguments mutableCopy];
        data[@"applySafeArea"] = @(strongSelf->_applySafeArea ? 1 : 0);
        [strongSelf->_holder updateTemplateData:data];
        strongSelf->_initialData = strongSelf->_holder.initialTemplateData;
        result(@YES);
      } else if ([call.method isEqualToString:@"setHidden"]) {
        // 宿主路由（如扫码页）覆盖期间隐藏整个原生容器：全屏平台视图不受
        // Flutter 绘制顺序约束，被覆盖路由仍会浮在其上，必须显式 hidden。
        if (![call.arguments isKindOfClass:[NSNumber class]]) {
          result([FlutterError errorWithCode:@"lynx_invalid_data" message:@"setHidden requires a bool" details:nil]);
          return;
        }
        strongSelf->_root.hidden = [(NSNumber *)call.arguments boolValue];
        result(@YES);
      } else {
        result(FlutterMethodNotImplemented);
      }
    }];

    NSLog(@"[MiniAppPageStackView] init params keys=%@ bundlePath='%@'", params.allKeys, _bundlePath);
    [self bootstrapFirstPage];
    [self installEdgeBackGesture];
    [[LynxNavigator sharedInstance]
        registerLynxHolder:_holder
              initLynxView:[self topLynxView]];
  }
  return self;
}

- (UIView *)view {
  return _root;
}

- (void)dealloc {
  // Platform-view disposal revokes callbacks belonging to this origin.
  [_bridgeBinding invalidate];
  [_holder invalidateBridgeBindings];
  [_stackChannel setMethodCallHandler:nil];
}

- (void)bootstrapFirstPage {
  _holder.initialTemplateData = _initialData;
  LynxView *first = [self createLynxViewWithInitialData:_initialData];
  [_root addSubview:first];
  MiniAppLynxHolder *holder = _holder;
  holder.containerView = _root;
  holder.initialTemplateData = _initialData;
}

- (LynxView *)createLynxViewWithInitialData:(NSDictionary *)initialData {
  NSLog(@"[MiniAppPageStackView] createLynxView holderPath=%@ paramPath=%@",
        _holder.preparedBundlePath, _bundlePath);
  if (_bundlePath.length == 0) {
    NSLog(@"[MiniAppPageStackView] abort: empty param path");
    return nil;
  }
  LynxConfig *config = [[LynxConfig alloc]
      initWithProvider:[[MiniAppStackTemplateProvider alloc]
                           initWithPath:_bundlePath]];
  // 白名单与整页单页模式一致，由 creationParams 传入。
  LynxBridgeBinding *binding = [_holder createBridgeBinding];
  _bridgeBinding = binding;
  [config registerModule:[LynxBridgeModule class] param:binding];
  [config registerModule:[MiniAppStackNavigationModule class] param:binding];

  MiniAppStackLynxView *view = [[MiniAppStackLynxView alloc] initWithBuilderBlock:^(LynxViewBuilder *builder) {
    builder.config = config;
    builder.screenSize = UIScreen.mainScreen.bounds.size;
    builder.fontScale = 1.0;
  }];
  view.holder = _holder;
  // 首次加载使用容器约束，后续有效尺寸由根视图布局同步。
  view.frame = _root.bounds;
  view.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  view.layoutWidthMode = LynxViewSizeModeExact;
  view.layoutHeightMode = LynxViewSizeModeExact;
  view.preferredLayoutWidth = CGRectGetWidth(_root.bounds);
  view.preferredLayoutHeight = CGRectGetHeight(_root.bounds);
  // 初始数据经 loadTemplate 的 initData 参数注入（LynxView 无独立
  // updateInitialData 入口）；模板文件字节直喂。
  NSData *bytes = [NSData dataWithContentsOfFile:_holder.preparedBundlePath];
  NSMutableDictionary *init = [NSMutableDictionary dictionaryWithDictionary:initialData];
  init[@"applySafeArea"] = @(_applySafeArea ? 1 : 0);
  NSString *url = [@"file://" stringByAppendingString:_holder.preparedBundlePath];
  [view loadTemplate:bytes
              withURL:url
             initData:[[LynxTemplateData alloc] initWithDictionary:init]];
  [_holder trackLynxView:view binding:binding templateData:init];
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

- (NSDictionary<NSString *, id> *)stringKeyedMap:(id)value {
  if (![value isKindOfClass:[NSDictionary class]]) {
    return @{};
  }
  // 只限制键类型，保留模板初始数据中的数字、布尔值和嵌套对象。
  NSMutableDictionary<NSString *, id> *out = [NSMutableDictionary dictionary];
  [(NSDictionary *)value
      enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([key isKindOfClass:[NSString class]]) {
          out[key] = obj;
        }
      }];
  return out;
}

- (LynxView *)topLynxView {
  return _root.subviews.lastObject;
}

#pragma mark - 背滑手势（原生，交互式驱动页面栈返回）

- (void)installEdgeBackGesture {
  UIScreenEdgePanGestureRecognizer *edge =
      [[UIScreenEdgePanGestureRecognizer alloc]
          initWithTarget:self
                  action:@selector(handleEdgePan:)];
  edge.edges = UIRectEdgeLeft;
  [_root addGestureRecognizer:edge];
}

// 微信式交互返回：栈深>1 时栈顶视图跟手右移，越过阈值（位移 35% 或
// 快甩）交给页面栈回退（退出动画从当前位置续滑）；不足则弹回原位。
// 栈底滑动无动作——退出容器只走右上角胶囊 ×。
- (void)handleEdgePan:(UIScreenEdgePanGestureRecognizer *)gesture {
  if (_holder.pageCount <= 1) {
    return;
  }
  switch (gesture.state) {
    case UIGestureRecognizerStateBegan: {
      _dragTopView = [_holder topLynxView];
      break;
    }
    case UIGestureRecognizerStateChanged: {
      LynxView *top = _dragTopView;
      if (top == nil) {
        return;
      }
      CGFloat tx = MAX(0, [gesture translationInView:_root].x);
      top.transform = CGAffineTransformMakeTranslation(tx, 0);
      break;
    }
    case UIGestureRecognizerStateEnded: {
      LynxView *top = _dragTopView;
      _dragTopView = nil;
      if (top == nil) {
        return;
      }
      CGPoint velocity = [gesture velocityInView:_root];
      CGFloat width = MAX(CGRectGetWidth(_root.bounds), 1);
      CGFloat progress = top.transform.tx / width;
      if (progress > 0.35 || velocity.x > 800) {
        [_holder goBack];
      } else {
        [UIView animateWithDuration:0.25
                              delay:0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
                           top.transform = CGAffineTransformIdentity;
                         }
                         completion:nil];
      }
      break;
    }
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed:
    default: {
      LynxView *top = _dragTopView;
      _dragTopView = nil;
      if (top != nil) {
        [UIView animateWithDuration:0.25
                              delay:0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
                           top.transform = CGAffineTransformIdentity;
                         }
                         completion:nil];
      }
      break;
    }
  }
}

@end

@implementation MiniAppPageStackFactory {
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
  // 与 Dart creationParamsCodec 配对，否则 Flutter 会传入空参数。
  return [FlutterStandardMessageCodec sharedInstance];
}

- (NSObject<FlutterPlatformView> *)createWithFrame:(CGRect)frame
                                    viewIdentifier:(int64_t)viewId
                                         arguments:(id _Nullable)args
                                   binaryMessenger:(NSObject<FlutterBinaryMessenger> *)messenger {
  NSLog(@"[MiniAppPageStackFactory] create viewId=%lld argsClass=%@ args=%@",
        viewId, NSStringFromClass([args class]), args);
  return [[MiniAppPageStackView alloc] initWithFrame:frame
                                              viewId:viewId
                                              params:args
                                            messenger:messenger];
}

- (NSObject<FlutterPlatformView> *)createWithFrame:(CGRect)frame
                                    viewIdentifier:(int64_t)viewId
                                         arguments:(id _Nullable)args {
  return [self createWithFrame:frame viewIdentifier:viewId arguments:args binaryMessenger:_messenger];
}

@end
