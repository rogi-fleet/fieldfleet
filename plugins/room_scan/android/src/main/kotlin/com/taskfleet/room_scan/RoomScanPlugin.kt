package com.taskfleet.room_scan

import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Config
import com.google.ar.core.Session
import com.taskfleet.room_scan.engine.ArCorePlaneTapEngine
import com.taskfleet.room_scan.engine.RoomScanEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec

/**
 * Bridges the Dart `RoomScanChannel` to the native ARCore engine.
 *
 * Mirrors the iOS plugin's channel contract one-for-one:
 *   `taskfleet/room_scan`         — MethodChannel (commands)
 *   `taskfleet/room_scan/events`  — EventChannel  (progress + result)
 *   `taskfleet/room_scan_view`    — platform view factory
 */
class RoomScanPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "taskfleet/room_scan"
        const val EVENT_CHANNEL = "taskfleet/room_scan/events"
        const val VIEW_TYPE = "taskfleet/room_scan_view"
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var applicationContext: Context? = null
    private var activity: Activity? = null

    private var engine: RoomScanEngine? = null
    private var activeView: RoomScanPlatformView? = null
    private var captureId: String? = null

    // ── FlutterPlugin ──────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel!!.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel!!.setStreamHandler(this)

        binding.platformViewRegistry.registerViewFactory(
            VIEW_TYPE,
            RoomScanViewFactory(StandardMessageCodec.INSTANCE, this)
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        applicationContext = null
        engine?.cancel()
        engine = null
    }

    // ── ActivityAware ──────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        engine?.stop()
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        engine?.cancel()
        engine = null
        activity = null
    }

    // ── Platform view callback ─────────────────────────────────────────

    internal fun onViewCreated(view: RoomScanPlatformView) {
        activeView = view
        engine?.attach(view)
    }

    internal fun onViewDestroyed(view: RoomScanPlatformView) {
        if (activeView === view) {
            engine?.detach()
            activeView = null
        }
    }

    // ── MethodChannel ──────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCapabilities" -> result.success(detectCapabilities())
            "start" -> {
                val id = call.argument<String>("captureId")
                if (id == null) {
                    result.error("bad_args", "captureId required", null)
                    return
                }
                startEngine(id)
                result.success(null)
            }
            "finish" -> {
                engine?.finish()
                result.success(null)
            }
            "stop" -> {
                engine?.stop()
                result.success(null)
            }
            "resume" -> {
                engine?.resume()
                result.success(null)
            }
            "undoLastTap" -> {
                // Tap engines return remaining count; engines without
                // discrete taps return -1 (Dart side no-ops on that).
                result.success(engine?.undoLastTap() ?: -1)
            }
            "cancel" -> {
                engine?.cancel()
                engine = null
                emit(mapOf("type" to "cancelled"))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startEngine(id: String) {
        val ctx = applicationContext ?: return
        val act = activity
        if (act == null) {
            emit(
                mapOf(
                    "type" to "error",
                    "kind" to "unknown",
                    "message" to "No activity available to start scan."
                )
            )
            return
        }
        captureId = id
        engine?.cancel()
        val newEngine = ArCorePlaneTapEngine(
            captureId = id,
            activity = act,
            emit = ::emit,
            depthRequested = isDepthSupported(ctx)
        )
        engine = newEngine
        activeView?.let { newEngine.attach(it) }
        newEngine.start()
    }

    private fun emit(payload: Map<String, Any?>) {
        val sink = this.sink ?: return
        mainHandler.post { sink.success(payload) }
    }

    // ── EventChannel ───────────────────────────────────────────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.sink = events
    }

    override fun onCancel(arguments: Any?) {
        this.sink = null
    }

    // ── Capabilities ───────────────────────────────────────────────────

    private fun detectCapabilities(): Map<String, Any?> {
        val ctx = applicationContext ?: return mapOf(
            "engine" to "none",
            "unsupportedReason" to "Plugin not attached."
        )
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            return mapOf(
                "engine" to "none",
                "unsupportedReason" to "Android 7.0 or later is required."
            )
        }
        val availability = try {
            ArCoreApk.getInstance().checkAvailability(ctx)
        } catch (t: Throwable) {
            return mapOf("engine" to "none", "unsupportedReason" to (t.message ?: "ARCore check failed"))
        }
        val supported = availability.isSupported || availability.isTransient
        if (!supported) {
            return mapOf(
                "engine" to "none",
                "unsupportedReason" to "ARCore is not available on this device."
            )
        }
        val depth = isDepthSupported(ctx)
        return mapOf(
            "engine" to if (depth) "arCoreDepth" else "arCorePlaneTap",
            "supportsMultiRoom" to false,
            "hasDepthSensor" to depth
        )
    }

    private fun isDepthSupported(ctx: Context): Boolean {
        return try {
            val session = Session(ctx)
            val supported = session.isDepthModeSupported(Config.DepthMode.AUTOMATIC)
            session.close()
            supported
        } catch (_: Throwable) {
            false
        }
    }
}
