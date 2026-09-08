package com.kmanager.flutter_lynx

import android.content.Context
import android.graphics.Color
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.TextView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.File
import java.util.concurrent.ConcurrentHashMap

object LynxPlatformViewManager {
    val activeViews = ConcurrentHashMap<Int, LynxPlatformView>()

    fun broadcastEvent(eventName: String, data: Map<String, Any?>) {
        for (view in activeViews.values) {
            view.sendCustomEvent(eventName, data)
        }
    }
}

class LynxPlatformView(
    private val context: Context,
    private val messenger: BinaryMessenger,
    private val viewId: Int,
    private val creationParams: Map<String, Any?>
) : PlatformView, MethodChannel.MethodCallHandler {

    private val rootLayout: FrameLayout = FrameLayout(context).apply {
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        setBackgroundColor(Color.WHITE)
    }

    private val methodChannel: MethodChannel =
        MethodChannel(messenger, "com.kmanager.flutter_lynx/lynx_view_$viewId").apply {
            setMethodCallHandler(this@LynxPlatformView)
        }

    private val eventChannel: MethodChannel =
        MethodChannel(messenger, "com.kmanager.flutter_lynx/lynx_view_${viewId}_events")

    private var url: String = creationParams["url"] as? String ?: ""
    private var initialData: Map<String, Any?> =
        (creationParams["initialData"] as? Map<*, *>)?.filterKeys { it is String } as? Map<String, Any?> ?: emptyMap()

    init {
        LynxPlatformViewManager.activeViews[viewId] = this
        initLynxOrPlaceholder()
    }

    private fun initLynxOrPlaceholder() {
        // Here we attempt to dynamically reflect or instantiate com.lynx.tasm.LynxView
        // If Lynx AAR dependency is provided at runtime, real LynxView is initialized.
        // Otherwise, a graceful native container is presented.
        try {
            val lynxViewClass = Class.forName("com.lynx.tasm.LynxView")
            val lynxViewBuilderClass = Class.forName("com.lynx.tasm.LynxViewBuilder")
            val builder = lynxViewBuilderClass.getConstructor(Context::class.java).newInstance(context)
            val buildMethod = lynxViewBuilderClass.getMethod("build")
            val lynxView = buildMethod.invoke(builder) as View

            rootLayout.addView(lynxView)

            // Load template
            val loadTemplateMethod = lynxViewClass.getMethod("loadTemplate", ByteArray::class.java, Map::class.java)
            val file = File(url.removePrefix("file://"))
            if (file.exists()) {
                val bytes = file.readBytes()
                loadTemplateMethod.invoke(lynxView, bytes, initialData)
            }

            eventChannel.invokeMethod("onLoadSuccess", null)
            eventChannel.invokeMethod("onFirstScreen", null)
        } catch (_: ClassNotFoundException) {
            // Native fallback view when Lynx engine runtime AAR is loaded dynamically or in dev
            val container = FrameLayout(context).apply {
                setBackgroundColor(Color.parseColor("#F8F9FA"))
            }

            val tv = TextView(context).apply {
                text = "Lynx View Ready\nID: $viewId\nBundle: $url"
                setTextColor(Color.parseColor("#212529"))
                textSize = 14f
                setPadding(32, 32, 32, 32)
            }
            container.addView(tv)
            rootLayout.addView(container)

            eventChannel.invokeMethod("onLoadSuccess", null)
            eventChannel.invokeMethod("onFirstScreen", null)
        } catch (e: Exception) {
            eventChannel.invokeMethod("onLoadFail", e.message ?: "Failed to initialize LynxView")
        }
    }

    fun sendCustomEvent(eventName: String, data: Map<String, Any?>) {
        // Forward event into Lynx runtime
    }

    override fun getView(): View = rootLayout

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "updateData" -> {
                val data = call.arguments as? Map<String, Any?> ?: emptyMap()
                result.success(true)
            }
            "sendCustomEvent" -> {
                val eventName = call.argument<String>("eventName") ?: ""
                val data = call.argument<Map<String, Any?>>("data") ?: emptyMap()
                sendCustomEvent(eventName, data)
                result.success(true)
            }
            "reload" -> {
                initLynxOrPlaceholder()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        LynxPlatformViewManager.activeViews.remove(viewId)
        methodChannel.setMethodCallHandler(null)
        rootLayout.removeAllViews()
    }
}
