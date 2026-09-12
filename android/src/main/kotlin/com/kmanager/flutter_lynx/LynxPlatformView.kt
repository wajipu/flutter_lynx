package com.kmanager.flutter_lynx

import android.app.Application
import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import com.facebook.drawee.backends.pipeline.Fresco
import com.lynx.jsbridge.Arguments
import com.lynx.react.bridge.JavaOnlyArray
import com.lynx.service.image.LynxImageService
import com.lynx.tasm.LynxEnv
import com.lynx.tasm.LynxError
import com.lynx.tasm.LynxView
import com.lynx.tasm.LynxViewBuilder
import com.lynx.tasm.LynxViewClient
import com.lynx.tasm.service.ILynxImageService
import com.lynx.tasm.service.LynxServiceCenter
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.File
import java.net.URI
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Future

object LynxPlatformViewManager {
    private val activeViews = ConcurrentHashMap<Int, LynxPlatformView>()

    fun register(viewId: Int, view: LynxPlatformView) {
        activeViews[viewId] = view
    }

    fun unregister(viewId: Int, view: LynxPlatformView) {
        activeViews.remove(viewId, view)
    }

    fun sendEvent(eventName: String, data: Map<String, Any?>, viewId: Int?): Boolean {
        if (viewId != null) return activeViews[viewId]?.sendCustomEvent(eventName, data) ?: false
        var delivered = false
        for (view in activeViews.values) {
            delivered = view.sendCustomEvent(eventName, data) || delivered
        }
        return delivered
    }
}

class LynxPlatformView(
    private val context: Context,
    messenger: BinaryMessenger,
    private val viewId: Int,
    creationParams: Map<String, Any?>
) : PlatformView, MethodChannel.MethodCallHandler {
    private val rootLayout = FrameLayout(context).apply {
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        setBackgroundColor(Color.WHITE)
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private val fileExecutor = Executors.newSingleThreadExecutor()
    private val methodChannel =
        MethodChannel(messenger, "com.kmanager.flutter_lynx/lynx_view_$viewId")
    private val eventChannel =
        MethodChannel(messenger, "com.kmanager.flutter_lynx/lynx_view_" + viewId + "_events")
    private var url = creationParams["url"] as? String ?: ""
    private var initialData = stringMap(creationParams["initialData"]) ?: emptyMap()
    // Preserve invalid creation input until Dart's reload handshake can receive onLoadFail.
    private val allowedModules = runCatching { parseAllowedModules(creationParams["allowedModules"]) }
    private var lynxView: LynxView? = null
    private var bridgeBinding: LynxBridgeBinding? = null
    private var fileTask: Future<*>? = null
    private var loadGeneration = 0
    private var loadStarted = false
    private var templateRequested = false
    private var loaded = false
    private var disposed = false

    init {
        methodChannel.setMethodCallHandler(this)
        LynxPlatformViewManager.register(viewId, this)
        // Dart subscribes before reload; initialization errors are reported at that handshake.
        try {
            createNativeView()
        } catch (_: Exception) {
            destroyNativeView()
        } catch (_: LinkageError) {
            destroyNativeView()
        }
    }

    private fun createNativeView() {
        val modules = allowedModules.getOrThrow()
        val application = context.applicationContext as? Application
            ?: throw IllegalStateException("Lynx requires an Android Application context")
        LynxEnv.inst().init(application, null, null, null)
        check(LynxEnv.inst().isNativeLibraryLoaded) { "Lynx native libraries are unavailable" }
        val services = LynxServiceCenter.inst()
        val imageService = services.getService(ILynxImageService::class.java)
        // Keep a host's custom service and Fresco configuration; only fill the missing official setup.
        if (imageService == null || imageService is LynxImageService) {
            if (!Fresco.hasBeenInitialized()) {
                Fresco.initialize(application)
            }
            if (imageService == null) {
                services.registerService(LynxImageService.getInstance())
            }
        }
        val binding = LynxBridgeBinding(mainHandler, modules)
        bridgeBinding = binding
        val builder = LynxViewBuilder()
        builder.registerModule("LynxBridge", LynxBridgeModule::class.java, binding)
        val nativeView = builder.build(context)
        lynxView = nativeView
        nativeView.addLynxViewClient(object : LynxViewClient() {
            override fun onLoadSuccess() = deliver {
                loaded = true
                eventChannel.invokeMethod("onLoadSuccess", null)
            }

            override fun onFirstScreen() = deliver {
                eventChannel.invokeMethod("onFirstScreen", null)
            }

            // SDK 3.2 dispatches the common callback before the typed callback for the same error.
            override fun onReceivedError(error: LynxError) = report(error)

            private fun report(error: LynxError) = deliver {
                loaded = false
                eventChannel.invokeMethod("onLoadFail", "Lynx " + error.errorCode + ": " + error.msg)
            }

            private fun deliver(action: () -> Unit) {
                mainHandler.post {
                    if (!disposed && loadStarted && bridgeBinding === binding && binding.isActive) {
                        action()
                    }
                }
            }
        })
        rootLayout.addView(nativeView, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        ))
    }

    private fun destroyNativeView() {
        bridgeBinding?.invalidate()
        bridgeBinding = null
        val previous = lynxView
        lynxView = null
        loaded = false
        templateRequested = false
        try {
            previous?.destroy()
        } finally {
            rootLayout.removeAllViews()
        }
    }

    private fun fail(message: String, generation: Int) {
        if (!disposed && generation == loadGeneration) {
            loaded = false
            templateRequested = false
            eventChannel.invokeMethod("onLoadFail", message)
        }
    }

    private fun preparedFile(value: String): File {
        val file = if (value.startsWith("file:")) {
            val uri = URI(value)
            require(uri.scheme == "file" && uri.rawAuthority == null &&
                uri.rawQuery == null && uri.rawFragment == null) {
                "Lynx only accepts a prepared local file URL"
            }
            File(uri)
        } else File(value)
        require(file.isAbsolute) { "Lynx only accepts an absolute prepared local file path" }
        return file
    }

    private fun reload(call: MethodCall, result: MethodChannel.Result) {
        loadGeneration += 1
        val generation = loadGeneration
        fileTask?.cancel(true)
        loadStarted = true
        try {
            destroyNativeView()
            val args = if (call.arguments == null) emptyMap() else {
                stringMap(call.arguments)
                    ?: throw IllegalArgumentException("reload requires string-keyed arguments")
            }
            val nextUrl = if (args.containsKey("url")) {
                args["url"] as? String ?: throw IllegalArgumentException("url must be a string")
            } else url
            val nextData = if (args.containsKey("initialData")) {
                stringMap(args["initialData"])
                    ?: throw IllegalArgumentException("initialData must be an object with string keys")
            } else initialData
            val file = preparedFile(nextUrl)
            url = nextUrl
            initialData = nextData
            createNativeView()
            val targetView = lynxView!!
            // Only prepared local bytes are read; the real file URL remains the SDK's source URL.
            fileTask = fileExecutor.submit {
                try {
                    val size = file.length()
                    require(file.isFile && size > 0 && size <= MAX_BUNDLE_BYTES.toLong()) {
                        "Prepared Lynx bundle is missing, empty or larger than 10 MiB"
                    }
                    val bytes = file.readBytes()
                    require(bytes.isNotEmpty() && bytes.size <= MAX_BUNDLE_BYTES) {
                        "Prepared Lynx bundle is empty or larger than 10 MiB"
                    }
                    val sourceUrl = Uri.fromFile(file).toString()
                    mainHandler.post {
                        if (!disposed && generation == loadGeneration && lynxView === targetView) {
                            try {
                                templateRequested = true
                                targetView.renderTemplateWithBaseUrl(bytes, nextData, sourceUrl)
                            } catch (error: Exception) {
                                fail(error.message ?: "Unable to render the Lynx bundle", generation)
                            } catch (error: LinkageError) {
                                fail(error.message ?: "Lynx native library failure", generation)
                            }
                        }
                    }
                } catch (error: Exception) {
                    mainHandler.post {
                        fail(error.message ?: "Unable to read the prepared Lynx bundle", generation)
                    }
                }
            }
            // Scheduling acknowledgement only; success is exclusively a LynxViewClient callback.
            result.success(true)
        } catch (error: Exception) {
            fail(error.message ?: "Unable to load the Lynx bundle", generation)
            result.error("lynx_load_failed", error.message, null)
        } catch (error: LinkageError) {
            fail(error.message ?: "Lynx native library failure", generation)
            result.error("lynx_native_unavailable", error.message, null)
        }
    }

    fun sendCustomEvent(eventName: String, data: Map<String, Any?>): Boolean {
        val target = lynxView ?: return false
        if (disposed || !loaded || eventName.isBlank()) return false
        target.sendGlobalEvent("onFlutterEvent", JavaOnlyArray.of(
            Arguments.makeNativeMap(mapOf("name" to eventName, "data" to data))
        ))
        return true
    }

    override fun getView(): View = rootLayout

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) {
            result.error("lynx_disposed", "Lynx view has been disposed", null)
            return
        }
        try {
            when (call.method) {
                "reload" -> reload(call, result)
                "updateData" -> {
                    val data = stringMap(call.arguments)
                        ?: throw IllegalArgumentException("updateData requires string-keyed data")
                    check(templateRequested) { "Lynx template has not been requested" }
                    lynxView!!.updateData(data)
                    initialData = initialData + data
                    result.success(true)
                }
                "sendCustomEvent" -> {
                    val name = call.argument<String>("eventName")
                        ?: throw IllegalArgumentException("eventName is required")
                    val data = stringMap(call.argument<Any?>("data"))
                        ?: throw IllegalArgumentException("event data must have string keys")
                    check(sendCustomEvent(name, data)) { "Lynx view is not loaded or event name is empty" }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("lynx_call_failed", error.message, null)
        }
    }

    override fun dispose() {
        if (disposed) return
        disposed = true
        loadGeneration += 1
        fileTask?.cancel(true)
        fileExecutor.shutdownNow()
        LynxPlatformViewManager.unregister(viewId, this)
        methodChannel.setMethodCallHandler(null)
        try {
            destroyNativeView()
        } finally {
            mainHandler.removeCallbacksAndMessages(null)
        }
    }

    private fun stringMap(value: Any?): Map<String, Any?>? {
        val map = value as? Map<*, *> ?: return null
        if (map.keys.any { it !is String }) return null
        @Suppress("UNCHECKED_CAST")
        return map as Map<String, Any?>
    }

    private fun parseAllowedModules(value: Any?): Set<String> {
        require(value is List<*> && value.size in 1..32) {
            "allowedModules must contain 1 to 32 module names"
        }
        return value.map { module ->
            require(module is String && MODULE_NAME.matches(module)) {
                "allowedModules contains an invalid module name"
            }
            module
        }.toSet()
    }

    private companion object {
        const val MAX_BUNDLE_BYTES = 10 * 1024 * 1024
        val MODULE_NAME = Regex("[A-Za-z0-9_-]{1,64}")
    }
}
