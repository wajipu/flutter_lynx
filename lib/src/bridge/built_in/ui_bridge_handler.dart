import "../lynx_bridge_handler.dart";
import "../lynx_bridge_request.dart";
import "../lynx_bridge_response.dart";

typedef ToastPresenter = void Function(String title, {String? icon, int? durationMs});
typedef ModalPresenter = Future<bool> Function(String title, String content, {bool showCancel, String confirmText, String cancelText});
typedef LoadingPresenter = void Function(bool show, {String? title});
typedef TitleSetter = void Function(String title);

/// Built-in bridge handler for UI operations (Toast, Modal, Loading, Title).
class UIBridgeHandler implements LynxBridgeHandler {
  static const String _module = "ui";

  ToastPresenter? onShowToast;
  ModalPresenter? onShowModal;
  LoadingPresenter? onShowLoading;
  TitleSetter? onSetTitle;

  UIBridgeHandler({
    this.onShowToast,
    this.onShowModal,
    this.onShowLoading,
    this.onSetTitle,
  });

  @override
  bool canHandle(String module, String method) {
    if (module == _module || module == "default") {
      return [
        "showToast",
        "showModal",
        "showLoading",
        "hideLoading",
        "setNavigationBarTitle",
      ].contains(method);
    }
    return false;
  }

  @override
  Future<LynxBridgeResponse> handle(LynxBridgeRequest request) async {
    final params = request.params;
    switch (request.method) {
      case "showToast":
        final title = params["title"]?.toString() ?? "";
        final icon = params["icon"]?.toString();
        final duration = params["duration"] as int? ?? 1500;
        if (onShowToast != null) {
          onShowToast!(title, icon: icon, durationMs: duration);
        }
        return LynxBridgeResponse.success(callId: request.callId);

      case "showModal":
        final title = params["title"]?.toString() ?? "";
        final content = params["content"]?.toString() ?? "";
        final showCancel = params["showCancel"] as bool? ?? true;
        final confirmText = params["confirmText"]?.toString() ?? "确定";
        final cancelText = params["cancelText"]?.toString() ?? "取消";
        bool confirmed = true;
        if (onShowModal != null) {
          confirmed = await onShowModal!(
            title,
            content,
            showCancel: showCancel,
            confirmText: confirmText,
            cancelText: cancelText,
          );
        }
        return LynxBridgeResponse.success(
          callId: request.callId,
          data: {"confirm": confirmed, "cancel": !confirmed},
        );

      case "showLoading":
        final title = params["title"]?.toString();
        onShowLoading?.call(true, title: title);
        return LynxBridgeResponse.success(callId: request.callId);

      case "hideLoading":
        onShowLoading?.call(false);
        return LynxBridgeResponse.success(callId: request.callId);

      case "setNavigationBarTitle":
        final title = params["title"]?.toString() ?? "";
        onSetTitle?.call(title);
        return LynxBridgeResponse.success(callId: request.callId);

      default:
        return LynxBridgeResponse.error(
          callId: request.callId,
          code: 404,
          message: "Method ${request.method} not supported in UIBridgeHandler",
        );
    }
  }
}
