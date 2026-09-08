import "package:flutter_test/flutter_test.dart";
import "package:flutter_lynx_example/main.dart";

void main() {
  testWidgets("Verify Lynx demo app renders", (WidgetTester tester) async {
    await tester.pumpWidget(const LynxDemoApp());
    await tester.pump();

    // Verify title and tabs are rendered
    expect(find.text("Lynx 动态小程序 Demo"), findsOneWidget);
    expect(find.text("小程序中心"), findsOneWidget);
    expect(find.text("组件嵌入"), findsOneWidget);
    expect(find.text("JSB 调测日志"), findsOneWidget);
  });
}
