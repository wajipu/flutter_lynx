package com.kmanager.flutter_lynx

import android.app.Activity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class FlutterLynxPlugin : FlutterPlugin, ActivityAware, MethodCallHandler {
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
    private var hostCapsuleChannel: MethodChannel? = null
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger: BinaryMessenger = binding.binaryMessenger

        pluginChannel = MethodChannel(messenger, "com.kmanager.flutter_lynx/plugin").apply {
            setMethodCallHandler(this@FlutterLynxPlugin)
        }

        bridgeChannel = MethodChannel(messenger, "com.kmanager.flutter_lynx/bridge").apply {
            setMethodCallHandler(this@FlutterLynxPlugin)
        }

        hostCapsuleChannel = MethodChannel(messenger, "com.kmanager.flutter_lynx/host_capsule").apply {
            setMethodCallHandler(this@FlutterLynxPlugin)
            LynxHostCapsuleOverlay.bindChannel(this)
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
            "show" -> {
                LynxHostCapsuleOverlay.show(call.argument<Number>("dark")?.toInt() != 0)
                result.success(true)
            }
            "setDark" -> {
                LynxHostCapsuleOverlay.setDark(call.argument<Number>("dark")?.toInt() != 0)
                result.success(true)
            }
            "hide" -> {
                LynxHostCapsuleOverlay.hide()
                result.success(true)
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

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        LynxHostCapsuleOverlay.bindActivity(binding.activity)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        LynxHostCapsuleOverlay.bindActivity(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity?.let { LynxHostCapsuleOverlay.unbindActivity(it) }
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity?.let { LynxHostCapsuleOverlay.unbindActivity(it) }
        activity = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        LynxHostCapsuleOverlay.hide()
        pluginChannel?.setMethodCallHandler(null)
        pluginChannel = null
        hostCapsuleChannel?.setMethodCallHandler(null)
        hostCapsuleChannel = null
        bridgeChannel?.setMethodCallHandler(null)
        bridgeChannel = null
    }
}
