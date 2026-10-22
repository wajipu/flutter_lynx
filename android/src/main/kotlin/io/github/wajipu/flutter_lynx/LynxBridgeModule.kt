package io.github.wajipu.flutter_lynx

import android.content.Context
import android.os.Handler
import androidx.annotation.Keep
import com.lynx.jsbridge.Arguments
import com.lynx.jsbridge.LynxMethod
import com.lynx.jsbridge.LynxModule
import com.lynx.react.bridge.Callback
import com.lynx.react.bridge.ReadableMap
import io.flutter.plugin.common.MethodChannel

/** One binding belongs to one native view; reload/disposal invalidates pending host callbacks. */
class LynxBridgeBinding(
    private val mainHandler: Handler,
    allowedModules: Set<String>,
    private val bridgeChannel: MethodChannel,
    private val sourceContextId: String?
) {
    private val allowedModules = allowedModules.toSet()
    @Volatile
    var isActive: Boolean = true
        private set

    fun invalidate() {
        isActive = false
    }

    fun call(module: String, method: String, params: Map<String, Any?>, callId: String, callback: Callback) {
        mainHandler.post {
            if (!isActive) return@post
            // Reject at the native boundary: default is a literal module, not a wildcard.
            if (module !in allowedModules) {
                callback.invoke(Arguments.makeNativeMap(mapOf(
                    "callId" to callId,
                    "code" to 403,
                    "message" to "Bridge module is not allowed"
                )))
                return@post
            }
            // Origin comes only from the native view binding, not JS arguments.
            FlutterLynxPlugin.callBridge(module, method, params, callId, sourceContextId, bridgeChannel) { response ->
                // SDK conversion recursively wraps nested Map/List values for its JNI type reader.
                if (isActive) callback.invoke(Arguments.makeNativeMap(response))
            }
        }
    }
}

/** Exposes NativeModules.LynxBridge.call without adding another JS runtime or network client. */
@Keep
class LynxBridgeModule(context: Context, param: Any) : LynxModule(context, param) {
    private val binding = param as LynxBridgeBinding

    @Keep
    @LynxMethod
    fun call(module: String, method: String, params: ReadableMap, callId: String, callback: Callback) {
        binding.call(module, method, params.toHashMap(), callId, callback)
    }

    override fun destroy() {
        binding.invalidate()
        super.destroy()
    }
}
