#import "LynxHostCapsuleOverlay.h"

static const CGFloat kHostCapsuleWidth = 87.0;
static const CGFloat kHostCapsuleHeight = 32.0;
static const CGFloat kHostCapsuleRightInset = 7.0;
static const CGFloat kHostCapsuleBelowStatusBar = 4.0;
static const CGFloat kHostCapsuleButtonWidth = 43.0;
static const CGFloat kHostCapsuleDividerWidth = 1.0;

/// 铺满窗口但只拦截胶囊按钮，避免挡住小程序内容。
@interface LynxHostCapsulePassthroughView : UIView
@property(nonatomic, assign) BOOL dark;
@property(nonatomic, strong) UIVisualEffectView *chrome;
@property(nonatomic, strong) UIView *divider;
@property(nonatomic, strong) UIButton *moreButton;
@property(nonatomic, strong) UIButton *closeButton;
@end

@implementation LynxHostCapsulePassthroughView

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.userInteractionEnabled = YES;

    _chrome = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialLight]];
    _chrome.userInteractionEnabled = NO;
    _chrome.clipsToBounds = YES;
    [self addSubview:_chrome];

    _divider = [[UIView alloc] initWithFrame:CGRectZero];
    _divider.userInteractionEnabled = NO;
    [self addSubview:_divider];

    _moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_moreButton setImage:[UIImage systemImageNamed:@"ellipsis"] forState:UIControlStateNormal];
    _moreButton.accessibilityIdentifier = @"lynx_host_capsule_more";
    [self addSubview:_moreButton];

    _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_closeButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    _closeButton.accessibilityIdentifier = @"lynx_host_capsule_close";
    [self addSubview:_closeButton];

    [self applyDark:NO];
  }
  return self;
}

- (void)applyDark:(BOOL)dark {
  _dark = dark;
  UIBlurEffectStyle style =
      dark ? UIBlurEffectStyleSystemChromeMaterialDark : UIBlurEffectStyleSystemChromeMaterialLight;
  self.chrome.effect = [UIBlurEffect effectWithStyle:style];
  UIColor *icon = dark ? [UIColor colorWithWhite:1 alpha:0.92] : [UIColor colorWithWhite:0.12 alpha:0.92];
  UIColor *line = dark ? [UIColor colorWithWhite:1 alpha:0.22] : [UIColor colorWithWhite:0 alpha:0.12];
  self.moreButton.tintColor = icon;
  self.closeButton.tintColor = icon;
  self.divider.backgroundColor = line;
}

- (void)safeAreaInsetsDidChange {
  [super safeAreaInsetsDidChange];
  [self setNeedsLayout];
}

- (void)layoutSubviews {
  [super layoutSubviews];
  UIEdgeInsets insets = self.window ? self.window.safeAreaInsets : self.safeAreaInsets;
  CGFloat top = insets.top + kHostCapsuleBelowStatusBar;
  CGFloat left = CGRectGetWidth(self.bounds) - kHostCapsuleRightInset - kHostCapsuleWidth;
  CGRect capsule = CGRectMake(left, top, kHostCapsuleWidth, kHostCapsuleHeight);
  self.chrome.frame = capsule;
  self.chrome.layer.cornerRadius = kHostCapsuleHeight / 2.0;
  self.moreButton.frame = CGRectMake(CGRectGetMinX(capsule), CGRectGetMinY(capsule), kHostCapsuleButtonWidth, kHostCapsuleHeight);
  self.divider.frame = CGRectMake(CGRectGetMinX(capsule) + kHostCapsuleButtonWidth,
                                  CGRectGetMinY(capsule) + 8.0,
                                  kHostCapsuleDividerWidth,
                                  kHostCapsuleHeight - 16.0);
  self.closeButton.frame = CGRectMake(CGRectGetMinX(capsule) + kHostCapsuleButtonWidth + kHostCapsuleDividerWidth,
                                      CGRectGetMinY(capsule),
                                      kHostCapsuleButtonWidth,
                                      kHostCapsuleHeight);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
  UIView *hit = [super hitTest:point withEvent:event];
  if (hit == self || hit == self.chrome || hit == self.divider) {
    return nil;
  }
  return hit;
}

@end

@implementation LynxHostCapsuleOverlay {
  FlutterMethodChannel *_channel;
  LynxHostCapsulePassthroughView *_overlay;
}

+ (instancetype)shared {
  static LynxHostCapsuleOverlay *instance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[LynxHostCapsuleOverlay alloc] init];
  });
  return instance;
}

- (void)bindChannel:(FlutterMethodChannel *)channel {
  _channel = channel;
}

- (UIWindow *)hostWindow {
  if (@available(iOS 13.0, *)) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
      if (![scene isKindOfClass:[UIWindowScene class]]) {
        continue;
      }
      if (scene.activationState != UISceneActivationStateForegroundActive) {
        continue;
      }
      for (UIWindow *window in ((UIWindowScene *)scene).windows) {
        if (window.isKeyWindow && !window.isHidden) {
          return window;
        }
      }
    }
  }
  for (UIWindow *window in UIApplication.sharedApplication.windows) {
    if (window.isKeyWindow && !window.isHidden) {
      return window;
    }
  }
  return UIApplication.sharedApplication.windows.firstObject;
}

- (void)showDark:(BOOL)dark {
  UIWindow *window = [self hostWindow];
  if (window == nil) {
    return;
  }
  if (_overlay == nil) {
    _overlay = [[LynxHostCapsulePassthroughView alloc] initWithFrame:window.bounds];
    [_overlay.moreButton addTarget:self action:@selector(onMore) forControlEvents:UIControlEventTouchUpInside];
    [_overlay.closeButton addTarget:self action:@selector(onClose) forControlEvents:UIControlEventTouchUpInside];
  }
  [_overlay applyDark:dark];
  _overlay.frame = window.bounds;
  if (_overlay.superview != window) {
    [_overlay removeFromSuperview];
    [window addSubview:_overlay];
  }
  [window bringSubviewToFront:_overlay];
  [_overlay setNeedsLayout];
}

- (void)setDark:(BOOL)dark {
  [_overlay applyDark:dark];
}

- (void)hide {
  [_overlay removeFromSuperview];
}

- (void)onMore {
  [_channel invokeMethod:@"onMore" arguments:nil];
}

- (void)onClose {
  [self hide];
  [_channel invokeMethod:@"onClose" arguments:nil];
}

@end
