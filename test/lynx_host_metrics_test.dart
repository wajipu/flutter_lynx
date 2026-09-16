import "package:flutter/material.dart";
import "package:flutter_lynx/flutter_lynx.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("胶囊几何对齐微信 iOS：状态栏下 4pt、宽 87、高 32", () {
    expect(LynxHostMenuButton.topFromSafeTop(62), 66);
    expect(LynxHostMenuButton.topFromSafeTop(59), 63);
    expect(LynxHostMenuButton.topFromSafeTop(0), 4);
    expect(LynxHostMenuButton.widthFor(hasMore: true), 87);
    expect(LynxHostMenuButton.widthFor(hasMore: false), 43);
    expect(LynxHostMenuButton.heightValue, 32);
  });

  test("fromMediaQuery 使用 Flutter viewPadding，不编造安全区", () {
    final metrics = LynxHostMetrics.fromMediaQuery(
      const MediaQueryData(
        size: Size(393, 852),
        devicePixelRatio: 3,
        viewPadding: EdgeInsets.only(top: 59, bottom: 34),
        padding: EdgeInsets.only(top: 59, bottom: 34),
      ),
      capsuleHasMore: true,
    );

    expect(metrics.statusBarHeight, 59);
    expect(metrics.safeArea.top, 59);
    expect(metrics.safeArea.bottom, 34);
    expect(metrics.safeArea.left, 0);
    expect(metrics.safeArea.right, 0);
    expect(metrics.menuButton.height, LynxHostMenuButton.heightValue);
    expect(
      metrics.menuButton.width,
      LynxHostMenuButton.widthFor(hasMore: true),
    );
    expect(
      metrics.menuButton.top,
      59 + LynxHostMenuButton.belowStatusBar,
    );
    expect(metrics.menuButton.top > 59, isTrue);
    expect(
      metrics.menuButton.right,
      393 - LynxHostMenuButton.rightInset,
    );
    expect(
      metrics.menuButton.bottom,
      metrics.menuButton.top + LynxHostMenuButton.heightValue,
    );
    expect(metrics.toInitData()["statusBarHeight"], 59);
    expect(
      metrics.contentInset(applySafeArea: true),
      const EdgeInsets.fromLTRB(0, 59, 0, 34),
    );
    expect(metrics.contentInset(applySafeArea: false), EdgeInsets.zero);
  });

  test("没有安全区时返回 0，不用本地数字顶替", () {
    final metrics = LynxHostMetrics.fromMediaQuery(
      const MediaQueryData(
        size: Size(390, 844),
        devicePixelRatio: 2,
      ),
      capsuleHasMore: false,
    );

    expect(metrics.statusBarHeight, 0);
    expect(metrics.safeArea.top, 0);
    expect(metrics.menuButton.top, LynxHostMenuButton.belowStatusBar);
    expect(
      metrics.menuButton.width,
      LynxHostMenuButton.widthFor(hasMore: false),
    );
  });

  testWidgets("fromView 读取当前 FlutterView 的 viewPadding", (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    tester.view.viewPadding =
        const FakeViewPadding(top: 177, bottom: 102, left: 0, right: 0);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(const SizedBox.shrink());

    final metrics = LynxHostMetrics.fromView(
      tester.view,
      capsuleHasMore: true,
    );
    expect(metrics.statusBarHeight, 59);
    expect(metrics.safeArea.bottom, 34);
    expect(
      metrics.toSystemInfo(
        platform: "ios",
        osVersion: "26.2",
        language: "zh_CN",
      )["statusBarHeight"],
      59,
    );
  });
}
