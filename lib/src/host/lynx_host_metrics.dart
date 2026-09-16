import "dart:ui" as ui;

import "package:flutter/widgets.dart";

/// 宿主读到的安全区，单位是逻辑像素，数值来自 Flutter 当前视图，不编造。
class LynxHostSafeArea {
  /// 顶部未遮挡 inset，通常等于状态栏/灵动岛高度。
  final double top;

  /// 底部未遮挡 inset，通常等于 Home Indicator。
  final double bottom;

  /// 左侧未遮挡 inset。
  final double left;

  /// 右侧未遮挡 inset。
  final double right;

  const LynxHostSafeArea({
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
  });

  Map<String, double> toMap() => {
        "top": top,
        "bottom": bottom,
        "left": left,
        "right": right,
      };
}

/// 右上角宿主胶囊的页面坐标，对齐微信 iOS `menuButton`：状态栏下 4pt、距右 7pt、87×32。
///
/// 几何给 initData / getSystemInfo；可见胶囊由原生窗口层按同一公式画。
class LynxHostMenuButton {
  /// 胶囊高度，对齐微信 iOS `menuButton.height`。
  static const double heightValue = 32;

  /// 单个按钮宽度；左右各 43，加 1pt 分割线共 87。
  static const double buttonWidth = 43;

  /// 距屏幕右缘，对齐微信 iOS `screenWidth - 7`。
  static const double rightInset = 7;

  static const double _dividerWidth = 1;

  /// 微信 iOS：胶囊顶边在状态栏下方 4pt，和标题同一行，不贴进灵动岛。
  static const double belowStatusBar = 4;

  /// 微信 iOS `menuButton.top = statusBarHeight + 4`。
  static double topFromSafeTop(double safeTop) => safeTop + belowStatusBar;

  /// 有「更多」时是双按钮，否则只有关闭。
  static double widthFor({required bool hasMore}) {
    return hasMore ? buttonWidth * 2 + _dividerWidth : buttonWidth;
  }

  /// 胶囊宽度。
  final double width;

  /// 胶囊高度。
  final double height;

  /// 距屏幕顶。
  final double top;

  /// 距屏幕左。
  final double left;

  /// 距屏幕右边缘的右边界。
  final double right;

  /// 底边距屏幕顶。
  final double bottom;

  const LynxHostMenuButton({
    required this.width,
    required this.height,
    required this.top,
    required this.left,
    required this.right,
    required this.bottom,
  });

  factory LynxHostMenuButton.fromSafeTop({
    required double safeTop,
    required double screenWidth,
    required bool hasMore,
  }) {
    final top = topFromSafeTop(safeTop);
    final width = widthFor(hasMore: hasMore);
    final left = screenWidth - rightInset - width;
    return LynxHostMenuButton(
      width: width,
      height: heightValue,
      top: top,
      left: left,
      right: left + width,
      bottom: top + heightValue,
    );
  }

  Map<String, double> toMap() => {
        "width": width,
        "height": height,
        "top": top,
        "left": left,
        "right": right,
        "bottom": bottom,
      };

}

/// 把 Flutter 当前视图的安全区和胶囊几何交给小程序。
class LynxHostMetrics {
  /// 逻辑像素屏宽。
  final double screenWidth;

  /// 逻辑像素屏高。
  final double screenHeight;

  /// 设备像素比。
  final double pixelRatio;

  /// 设备安全区。
  final LynxHostSafeArea safeArea;

  /// 宿主胶囊位置。
  final LynxHostMenuButton menuButton;

  const LynxHostMetrics({
    required this.screenWidth,
    required this.screenHeight,
    required this.pixelRatio,
    required this.safeArea,
    required this.menuButton,
  });

  /// 状态栏高度，等于安全区 top。
  double get statusBarHeight => safeArea.top;

  factory LynxHostMetrics.fromView(
    ui.FlutterView view, {
    required bool capsuleHasMore,
  }) {
    final pixelRatio = view.devicePixelRatio;
    final physicalSize = view.physicalSize;
    final padding = view.viewPadding;
    return LynxHostMetrics._fromLogical(
      screenWidth: physicalSize.width / pixelRatio,
      screenHeight: physicalSize.height / pixelRatio,
      pixelRatio: pixelRatio,
      top: padding.top / pixelRatio,
      bottom: padding.bottom / pixelRatio,
      left: padding.left / pixelRatio,
      right: padding.right / pixelRatio,
      capsuleHasMore: capsuleHasMore,
    );
  }

  factory LynxHostMetrics.fromMediaQuery(
    MediaQueryData data, {
    required bool capsuleHasMore,
  }) {
    final padding = data.viewPadding;
    return LynxHostMetrics._fromLogical(
      screenWidth: data.size.width,
      screenHeight: data.size.height,
      pixelRatio: data.devicePixelRatio,
      top: padding.top,
      bottom: padding.bottom,
      left: padding.left,
      right: padding.right,
      capsuleHasMore: capsuleHasMore,
    );
  }

  factory LynxHostMetrics._fromLogical({
    required double screenWidth,
    required double screenHeight,
    required double pixelRatio,
    required double top,
    required double bottom,
    required double left,
    required double right,
    required bool capsuleHasMore,
  }) {
    final safeArea = LynxHostSafeArea(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
    );
    return LynxHostMetrics(
      screenWidth: screenWidth,
      screenHeight: screenHeight,
      pixelRatio: pixelRatio,
      safeArea: safeArea,
      menuButton: LynxHostMenuButton.fromSafeTop(
        safeTop: safeArea.top,
        screenWidth: screenWidth,
        hasMore: capsuleHasMore,
      ),
    );
  }

  Map<String, dynamic> toSystemInfo({
    required String platform,
    required String osVersion,
    required String language,
  }) {
    return {
      "platform": platform,
      "osVersion": osVersion,
      "screenWidth": screenWidth,
      "screenHeight": screenHeight,
      "pixelRatio": pixelRatio,
      "language": language,
      ...toInitData(),
    };
  }

  /// 首屏就能读到安全区和胶囊几何，不必等 getSystemInfo。
  Map<String, dynamic> toInitData() {
    return {
      "statusBarHeight": statusBarHeight,
      "safeArea": safeArea.toMap(),
      "menuButton": menuButton.toMap(),
    };
  }

  /// 全屏小程序打开安全区开关时，给小程序自己排版用的边。
  ///
  /// 宿主不再用 Flutter `Padding` 垫出一圈画布；顶底是设备安全区。关掉开关时四周为 0。
  EdgeInsets contentInset({required bool applySafeArea}) {
    if (!applySafeArea) {
      return EdgeInsets.zero;
    }
    return EdgeInsets.fromLTRB(
      safeArea.left,
      safeArea.top,
      safeArea.right,
      safeArea.bottom,
    );
  }
}
