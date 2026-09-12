// Models
export "src/models/lynx_template_data.dart";
export "src/models/lynx_event.dart";
export "src/models/lynx_load_status.dart";

// Bridge
export "src/bridge/lynx_bridge.dart";
export "src/bridge/lynx_bridge_handler.dart";
export "src/bridge/lynx_bridge_request.dart";
export "src/bridge/lynx_bridge_response.dart";
export "src/bridge/built_in/system_bridge_handler.dart";
export "src/bridge/built_in/ui_bridge_handler.dart";
export "src/bridge/built_in/storage_bridge_handler.dart";
export "src/bridge/built_in/router_bridge_handler.dart";

// Manager
export "src/manager/mini_program_manifest.dart";
export "src/manager/bundle_downloader.dart";
export "src/manager/lynx_mini_program_manager.dart";

// Views & Canvas
export "src/view/lynx_view.dart";
export "src/view/lynx_controller.dart";
export "src/view/lynx_mini_program_page.dart";
export "src/canvas/lynx_dynamic_canvas.dart";

// Utils
export "src/utils/lynx_logger.dart";

// Platform Interface
import "flutter_lynx_platform_interface.dart";
export "flutter_lynx_platform_interface.dart";

class FlutterLynx {
  Future<String?> getPlatformVersion() {
    return FlutterLynxPlatform.instance.getPlatformVersion();
  }
}
