package io.github.wajipu.flutter_lynx

import android.app.Activity
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import io.flutter.plugin.common.MethodChannel

/// 全屏小程序胶囊：挂在 Activity 窗口层，不跟 Lynx PlatformView 一起被 Flutter 重建。
object LynxHostCapsuleOverlay {
    private const val CAPSULE_WIDTH_DP = 87f
    private const val CAPSULE_HEIGHT_DP = 32f
    private const val CAPSULE_RIGHT_DP = 7f
    private const val CAPSULE_BELOW_STATUS_DP = 4f
    private const val BUTTON_WIDTH_DP = 43f
    private const val DIVIDER_WIDTH_DP = 1f

    private var activity: Activity? = null
    private var channel: MethodChannel? = null
    private var overlay: PassthroughFrameLayout? = null
    private var pendingDark: Boolean? = null

    fun bindChannel(channel: MethodChannel) {
        this.channel = channel
    }

    fun bindActivity(activity: Activity) {
        this.activity = activity
        pendingDark?.let { show(it) }
    }

    fun unbindActivity(activity: Activity) {
        if (this.activity === activity) {
            hide()
            this.activity = null
        }
    }

    fun show(dark: Boolean) {
        val host = activity ?: run {
            pendingDark = dark
            return
        }
        pendingDark = null
        val root = overlay ?: createOverlay(host).also { overlay = it }
        applyTheme(root, dark)
        attach(host, root)
        layoutCapsule(host, root)
    }

    fun setDark(dark: Boolean) {
        val root = overlay ?: return
        applyTheme(root, dark)
    }

    fun hide() {
        pendingDark = null
        overlay?.let { view ->
            (view.parent as? ViewGroup)?.removeView(view)
        }
    }

    /// 仅把已挂载的胶囊重新抬到窗口最上层；未挂载时保持隐藏，
    /// 显隐状态仍只由 Dart 侧 show/hide 控制。
    fun bringToFront() {
        val root = overlay ?: return
        val host = activity ?: return
        if (root.parent === host.window.decorView) {
            root.bringToFront()
        }
    }

    private fun createOverlay(host: Activity): PassthroughFrameLayout {
        val root = PassthroughFrameLayout(host).apply {
            isClickable = false
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val chrome = View(host).apply { tag = "chrome" }
        val divider = View(host).apply { tag = "divider" }
        val more = TextView(host).apply {
            tag = "more"
            text = "···"
            gravity = Gravity.CENTER
            includeFontPadding = false
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            contentDescription = "lynx_host_capsule_more"
        }
        val close = TextView(host).apply {
            tag = "close"
            text = "✕"
            gravity = Gravity.CENTER
            includeFontPadding = false
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            contentDescription = "lynx_host_capsule_close"
        }
        more.setOnClickListener { channel?.invokeMethod("onMore", null) }
        close.setOnClickListener {
            hide()
            channel?.invokeMethod("onClose", null)
        }
        root.addView(chrome)
        root.addView(divider)
        root.addView(more)
        root.addView(close)
        root.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            activity?.let { layoutCapsule(it, root) }
        }
        return root
    }

    private fun attach(host: Activity, root: PassthroughFrameLayout) {
        val decor = host.window.decorView as ViewGroup
        if (root.parent !== decor) {
            (root.parent as? ViewGroup)?.removeView(root)
            decor.addView(
                root,
                ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            )
        }
        root.bringToFront()
    }

    private fun layoutCapsule(host: Activity, root: PassthroughFrameLayout) {
        val density = host.resources.displayMetrics.density
        val width = (CAPSULE_WIDTH_DP * density).toInt()
        val height = (CAPSULE_HEIGHT_DP * density).toInt()
        val right = (CAPSULE_RIGHT_DP * density).toInt()
        val buttonWidth = (BUTTON_WIDTH_DP * density).toInt()
        val dividerWidth = (DIVIDER_WIDTH_DP * density).coerceAtLeast(1f).toInt()
        val status = host.window.decorView.rootWindowInsets?.stableInsetTop
            ?: host.resources.getIdentifier("status_bar_height", "dimen", "android").let { id ->
                if (id > 0) host.resources.getDimensionPixelSize(id) else 0
            }
        val top = status + (CAPSULE_BELOW_STATUS_DP * density).toInt()
        root.findViewWithTag<View>("chrome").layoutParams = FrameLayout.LayoutParams(width, height).apply {
            gravity = Gravity.TOP or Gravity.END
            topMargin = top
            marginEnd = right
        }
        root.findViewWithTag<View>("more").layoutParams = FrameLayout.LayoutParams(buttonWidth, height).apply {
            gravity = Gravity.TOP or Gravity.END
            topMargin = top
            marginEnd = right + buttonWidth + dividerWidth
        }
        root.findViewWithTag<View>("divider").layoutParams = FrameLayout.LayoutParams(dividerWidth, height - (16 * density).toInt()).apply {
            gravity = Gravity.TOP or Gravity.END
            topMargin = top + (8 * density).toInt()
            marginEnd = right + buttonWidth
        }
        root.findViewWithTag<View>("close").layoutParams = FrameLayout.LayoutParams(buttonWidth, height).apply {
            gravity = Gravity.TOP or Gravity.END
            topMargin = top
            marginEnd = right
        }
    }

    private fun applyTheme(root: PassthroughFrameLayout, dark: Boolean) {
        val density = root.resources.displayMetrics.density
        val fill = if (dark) 0xE61C1C1E.toInt() else 0xF2FFFFFF.toInt()
        val stroke = if (dark) 0x38FFFFFF else 0x1F000000
        val icon = if (dark) 0xEBFFFFFF.toInt() else 0xEB1F1F1F.toInt()
        val line = if (dark) 0x38FFFFFF else 0x1F000000
        val chrome = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = CAPSULE_HEIGHT_DP * density / 2f
            setColor(fill)
            setStroke((1 * density).coerceAtLeast(1f).toInt(), stroke)
        }
        root.findViewWithTag<View>("chrome").background = chrome
        root.findViewWithTag<View>("divider").setBackgroundColor(line)
        root.findViewWithTag<TextView>("more").setTextColor(icon)
        root.findViewWithTag<TextView>("close").setTextColor(icon)
    }
}

/// 铺满窗口但只拦截胶囊区域，避免挡住小程序内容。
private class PassthroughFrameLayout(context: android.content.Context) : FrameLayout(context) {
    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        val x = ev.x
        val y = ev.y
        for (index in 0 until childCount) {
            val child = getChildAt(index)
            if (child.visibility == VISIBLE &&
                x >= child.left &&
                x < child.right &&
                y >= child.top &&
                y < child.bottom
            ) {
                return super.dispatchTouchEvent(ev)
            }
        }
        return false
    }
}
