package com.taskfleet.room_scan

import android.content.Context
import android.opengl.GLSurfaceView
import android.view.View
import io.flutter.plugin.common.MessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Flutter PlatformView host for the ARCore camera surface.
 *
 * The actual GLSurfaceView and ARCore session are owned by the active
 * engine (see [com.taskfleet.room_scan.engine.ArCorePlaneTapEngine]) —
 * this view just provides a mountable container.
 */
class RoomScanPlatformView(context: Context, private val plugin: RoomScanPlugin) : PlatformView {
    private var glView: GLSurfaceView? = null
    private val host: android.widget.FrameLayout = android.widget.FrameLayout(context)

    init {
        plugin.onViewCreated(this)
    }

    fun mountGlView(view: GLSurfaceView) {
        if (glView != null && glView !== view) {
            host.removeView(glView)
        }
        if (glView !== view) {
            glView = view
            host.addView(
                view,
                android.widget.FrameLayout.LayoutParams(
                    android.widget.FrameLayout.LayoutParams.MATCH_PARENT,
                    android.widget.FrameLayout.LayoutParams.MATCH_PARENT
                )
            )
        }
    }

    fun unmountGlView() {
        glView?.let { host.removeView(it) }
        glView = null
    }

    override fun getView(): View = host

    override fun dispose() {
        plugin.onViewDestroyed(this)
        unmountGlView()
    }
}

class RoomScanViewFactory(
    codec: MessageCodec<Any?>,
    private val plugin: RoomScanPlugin
) : PlatformViewFactory(codec) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return RoomScanPlatformView(context, plugin)
    }
}
