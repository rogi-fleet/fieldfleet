package com.taskfleet.room_scan.engine

import android.app.Activity
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import android.view.MotionEvent
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.HitResult
import com.google.ar.core.Plane
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.UnavailableException
import com.taskfleet.room_scan.RoomScanPlatformView
import com.taskfleet.room_scan.bridge.TapPolygonBridge
import com.taskfleet.room_scan.render.ArRenderer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/**
 * ARCore-backed engine. Two flavours:
 *
 *  * `arCoreDepth`     — Depth API enabled, hit-tests use the depth texture
 *                        so taps stick to walls and floors at expected distance.
 *  * `arCorePlaneTap`  — plane detection only, hit-tests fall back to ARCore
 *                        plane raycasts.
 *
 * Both produce the same FloorPlanScanResult shape: a single room polygon
 * with the user-tapped corners in XZ floor coordinates.
 */
class ArCorePlaneTapEngine(
    private val captureId: String,
    private val activity: Activity,
    private val emit: (Map<String, Any?>) -> Unit,
    private val depthRequested: Boolean
) : RoomScanEngine, GLSurfaceView.Renderer {

    private val renderer = ArRenderer()
    private var session: Session? = null
    private var glView: GLSurfaceView? = null
    private var mountedView: RoomScanPlatformView? = null

    private val tappedPointsXZMeters: MutableList<FloatArray> = mutableListOf()
    private var floorY: Float? = null
    private var pendingTap: TapEvent? = null
    private var hasReportedNormalTracking = false

    private data class TapEvent(val x: Float, val y: Float)

    override fun attach(view: RoomScanPlatformView) {
        mountedView = view
        glView?.let { view.mountGlView(it) }
    }

    override fun detach() {
        mountedView?.unmountGlView()
        mountedView = null
    }

    override fun start() {
        try {
            ensureSession()
            session?.resume()
            glView?.onResume()
            emit(
                mapOf(
                    "type" to "guidance",
                    "message" to "Point the camera at the floor",
                    "severity" to "info"
                )
            )
        } catch (e: UnavailableException) {
            emit(
                mapOf(
                    "type" to "error",
                    "kind" to "unsupportedDevice",
                    "message" to (e.message ?: "ARCore unavailable")
                )
            )
        } catch (e: Throwable) {
            emit(
                mapOf(
                    "type" to "error",
                    "kind" to "unknown",
                    "message" to e.message
                )
            )
        }
    }

    override fun finish() {
        val polygon = tappedPointsXZMeters.toList()
        if (polygon.size < 3) {
            emit(
                mapOf(
                    "type" to "error",
                    "kind" to "insufficientFeatures",
                    "message" to "Tap at least three corners before finishing."
                )
            )
            return
        }
        glView?.onPause()
        session?.pause()
        val engineName = if (depthRequested) "arCoreDepth" else "arCorePlaneTap"
        val payload = TapPolygonBridge.toJson(
            polygon = polygon,
            captureId = captureId,
            engine = engineName
        )
        emit(mapOf("type" to "complete", "result" to payload))
    }

    override fun stop() {
        try {
            glView?.onPause()
            session?.pause()
        } catch (_: Throwable) {
        }
    }

    override fun undoLastTap(): Int {
        if (tappedPointsXZMeters.isEmpty()) return 0
        tappedPointsXZMeters.removeAt(tappedPointsXZMeters.size - 1)
        // The renderer redraws from the corners list every frame, so no
        // node-level removal is needed here — unlike iOS SceneKit, the
        // GLES path doesn't keep persistent draw objects per tap.
        emit(
            mapOf(
                "type" to "progress",
                "walls" to (tappedPointsXZMeters.size - 1).coerceAtLeast(0),
                "openings" to 0,
                "objects" to 0
            )
        )
        return tappedPointsXZMeters.size
    }

    override fun resume() {
        try {
            session?.resume()
            glView?.onResume()
            emit(
                mapOf(
                    "type" to "guidance",
                    "message" to "Resumed — keep tapping corners",
                    "severity" to "info"
                )
            )
        } catch (e: Throwable) {
            emit(
                mapOf(
                    "type" to "error",
                    "kind" to "trackingLost",
                    "message" to (e.message ?: "Could not resume ARCore session")
                )
            )
        }
    }

    override fun cancel() {
        try {
            glView?.onPause()
            session?.pause()
            session?.close()
        } catch (_: Throwable) {
        }
        session = null
        mountedView?.unmountGlView()
        glView = null
        tappedPointsXZMeters.clear()
        floorY = null
    }

    private fun ensureSession() {
        if (session != null && glView != null) return
        val s = Session(activity)
        val config = Config(s).apply {
            planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
            updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
            if (depthRequested && s.isDepthModeSupported(Config.DepthMode.AUTOMATIC)) {
                depthMode = Config.DepthMode.AUTOMATIC
            }
        }
        s.configure(config)
        session = s

        val view = GLSurfaceView(activity).apply {
            preserveEGLContextOnPause = true
            setEGLContextClientVersion(2)
            setEGLConfigChooser(8, 8, 8, 8, 16, 0)
            setRenderer(this@ArCorePlaneTapEngine)
            renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
            setOnTouchListener { _, ev ->
                if (ev.action == MotionEvent.ACTION_UP) {
                    pendingTap = TapEvent(ev.x, ev.y)
                }
                true
            }
        }
        glView = view
        mountedView?.mountGlView(view)
    }

    // ── GLSurfaceView.Renderer ─────────────────────────────────────────

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        renderer.onSurfaceCreated()
        val session = this.session ?: return
        session.setCameraTextureName(renderer.cameraTextureId)
    }

    private var surfaceWidth: Int = 0
    private var surfaceHeight: Int = 0

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        renderer.onSurfaceChanged(width, height)
        surfaceWidth = width
        surfaceHeight = height
        val session = this.session ?: return
        session.setDisplayGeometry(activity.windowManager.defaultDisplay.rotation, width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        val session = this.session ?: return
        try {
            session.setCameraTextureName(renderer.cameraTextureId)
            val frame: Frame = session.update()
            val camera = frame.camera

            renderer.drawBackground(frame)

            if (camera.trackingState != TrackingState.TRACKING) {
                if (hasReportedNormalTracking) {
                    emit(
                        mapOf(
                            "type" to "guidance",
                            "message" to "Tracking limited — move slowly",
                            "severity" to "warn"
                        )
                    )
                    hasReportedNormalTracking = false
                }
                return
            }
            if (!hasReportedNormalTracking) {
                emit(
                    mapOf(
                        "type" to "guidance",
                        "message" to "Tap each corner of the room",
                        "severity" to "info"
                    )
                )
                hasReportedNormalTracking = true
            }

            val projection = FloatArray(16)
            val view = FloatArray(16)
            camera.getProjectionMatrix(projection, 0, 0.1f, 100f)
            camera.getViewMatrix(view, 0)

            val planes = session.getAllTrackables(Plane::class.java)
                .filter { it.trackingState == TrackingState.TRACKING && it.subsumedBy == null }
            renderer.drawPlanes(planes, projection, view)

            // Continuous screen-centre hit-test — drives the reticle.
            // We accept hits on horizontal planes only; everything else
            // (estimated, depth-only points) the reticle stays hidden.
            val reticleHit = if (surfaceWidth > 0 && surfaceHeight > 0) {
                centreHit(frame)
            } else null

            renderer.drawTappedCorners(tappedPointsXZMeters, floorY ?: 0f, projection, view)
            renderer.drawEdges(tappedPointsXZMeters, floorY ?: 0f, projection, view)
            renderer.drawReticle(reticleHit, projection, view)

            pendingTap?.let { tap ->
                pendingTap = null
                val hit = pickHit(frame, tap.x, tap.y)
                if (hit == null) {
                    emit(
                        mapOf(
                            "type" to "guidance",
                            "message" to "No floor detected — try another spot",
                            "severity" to "warn"
                        )
                    )
                } else {
                    registerTap(hit)
                }
            }
        } catch (t: Throwable) {
            emit(
                mapOf(
                    "type" to "error",
                    "kind" to "unknown",
                    "message" to t.message
                )
            )
        }
    }

    /**
     * Cheap, every-frame hit-test for the reticle. Returns the world XYZ
     * of the first tracked-plane hit at the screen centre, or null if
     * nothing is hit (which is what we want — reticle hides itself).
     *
     * Uses the same hit-test as taps so the user can trust that what
     * the reticle shows is what a tap will register.
     */
    private fun centreHit(frame: Frame): FloatArray? {
        val cx = surfaceWidth / 2f
        val cy = surfaceHeight / 2f
        val hit = pickHit(frame, cx, cy) ?: return null
        val t = FloatArray(3)
        hit.hitPose.getTranslation(t, 0)
        return t
    }

    private fun pickHit(frame: Frame, x: Float, y: Float): HitResult? {
        // ARCore returns hits sorted by distance. We prefer hits on tracked
        // horizontal planes; if depth is on, the first hit *is* depth-aware.
        val hits = frame.hitTest(x, y)
        return hits.firstOrNull { hit ->
            val trackable = hit.trackable
            (trackable is Plane &&
                    trackable.type == Plane.Type.HORIZONTAL_UPWARD_FACING &&
                    trackable.isPoseInPolygon(hit.hitPose)) ||
                    (trackable !is Plane && hit.distance < 5f)
        }
    }

    private fun registerTap(hit: HitResult) {
        val pose = hit.hitPose
        val t = FloatArray(3)
        pose.getTranslation(t, 0)
        if (floorY == null) {
            floorY = t[1]
        }
        tappedPointsXZMeters.add(floatArrayOf(t[0], t[2]))
        emit(
            mapOf(
                "type" to "progress",
                "walls" to (tappedPointsXZMeters.size - 1).coerceAtLeast(0),
                "openings" to 0,
                "objects" to 0
            )
        )
    }

    @Suppress("unused")
    private fun debugMatrix(label: String, m: FloatArray) {
        // Kept for ad-hoc debugging; not called in production.
        val s = StringBuilder().append(label).append(":\n")
        for (i in 0 until 4) {
            for (j in 0 until 4) s.append(m[i * 4 + j]).append(' ')
            s.append('\n')
        }
        android.util.Log.d("RoomScan", s.toString())
        Matrix.setIdentityM(m, 0)
    }
}
