import "package:flutter_lynx/flutter_lynx.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("没有原生插件时 show/hide 不抛", () async {
    await LynxHostCapsule.show(
      dark: false,
      onMore: () {},
      onClose: () {},
    );
    await LynxHostCapsule.setDark(true);
    await LynxHostCapsule.hide();
  });
}
