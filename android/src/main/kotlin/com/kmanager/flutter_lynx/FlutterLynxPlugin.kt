package com.kmanager.flutter_lynx

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class FlutterLynxPlugin : FlutterPlugin, MethodCallHandler {
    companion object {
        var bridgeChannel: MethodChannel? = null
            private set

        fun callBridge(
            module: String,
            method: String,
            params: Map<String, Any?>,
            callId: String,
            callback: (Map<String, Any?>) -> Unit
        ) {
            val channel = bridgeChannel ?: run {
                callback(mapOf("callId" to callId, "code" to 500, "message" to "Bridge channel not initialized"))
                return
            }

            val request = mapOf(
                "callId" to callId,
                "module" to module,
                "method" to method,
                "params" to params
            )

            channel.invokeMethod("callBridge", request, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (result is Map<*, *>) {
                        @Suppress("UNCHECKED_CAST")
                        callback(result as Map<String, Any?>)
                    } else {
                        callback(mapOf("callId" to callId, "code" to 500, "message" to "Invalid Flutter bridge response"))
                    }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    callback(mapOf("callId" to callId, "code" to 500, "message" to (errorMessage ?: errorCode)))
                }

                override fun notImplemented() {
                    callback(mapOf("callId" to callId, "code" to 404, "message" to "Method not implemented on Flutter host"))
                }
            })
        }
    }

    private var pluginChannel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger: BinaryMessenger = binding.binaryMessenger

        pluginChannel = MethodChannel(messenger, "com.kmanager.flutter_lynx/plugin").apply {
            setMethodCallHandler(this@FlutterLynxPlugin)
        }

        bridgeChannel = MethodChannel(messenger, "com.kmanager.flutter_lynx/bridge").apply {
            setMethodCallHandler(this@FlutterLynxPlugin)
        }

        // Register Lynx Platform View Factory
        binding.platformViewRegistry.registerViewFactory(
            "com.kmanager.flutter_lynx/lynx_view",
            LynxPlatformViewFactory(binding.applicationContext, messenger)
        )
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }
            "sendCustomEvent" -> {
                val eventName = call.argument<String>("eventName") ?: ""
                val data = call.argument<Map<String, Any?>>("data") ?: emptyMap()
                val viewId = call.argument<Number>("viewId")?.toInt()
                if (LynxPlatformViewManager.sendEvent(eventName, data, viewId)) {
                    result.success(true)
                } else {
                    result.error("lynx_event_not_delivered", "No loaded Lynx view accepted the event", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        pluginChannel?.setMethodCallHandler(null)
        pluginChannel = null
        bridgeChannel?.setMethodCallHandler(null)
        bridgeChannel = null
    }
}
