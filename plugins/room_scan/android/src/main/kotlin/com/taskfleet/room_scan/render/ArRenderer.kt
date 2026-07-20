package com.taskfleet.room_scan.render

import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.Matrix
import com.google.ar.core.Frame
import com.google.ar.core.Plane
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * Minimal GLES2 renderer for the ARCore scanner.
 *
 *   * `cameraTextureId` — OES external texture for the camera background.
 *   * `drawBackground`   — full-screen quad sampling the camera texture, UVs
 *                          come from `frame.transformCoordinates2d`.
 *   * `drawPlanes`       — translucent triangle fan per detected plane.
 *   * `drawTappedCorners` — small coloured square per corner tap, drawn at
 *                          the corner's world position.
 *   * `drawEdges`        — thin quad strips connecting consecutive corners
 *                          so the user can see the wall under construction.
 *   * `drawReticle`      — annulus marker at the current camera-centre
 *                          ray-cast hit; gives the user a precise target
 *                          before they tap.
 *
 * No textures, no shaders beyond the bare minimum. The HUD lives in
 * Flutter on top of the platform view.
 */
class ArRenderer {

    // ── Camera background ─────────────────────────────────────────────

    var cameraTextureId: Int = 0
        private set

    private var bgProgram: Int = 0
    private var bgPositionAttr: Int = 0
    private var bgTexCoordAttr: Int = 0
    private val bgQuadCoords: FloatBuffer = floatBuffer(
        floatArrayOf(
            -1f, -1f,
             1f, -1f,
            -1f,  1f,
             1f,  1f
        )
    )
    private val bgUvCoords: FloatBuffer = floatBuffer(FloatArray(8))

    // ── Plane visualisation ───────────────────────────────────────────

    private var planeProgram: Int = 0
    private var planePositionAttr: Int = 0
    private var planeMvpUniform: Int = 0
    private var planeColorUniform: Int = 0

    // ── Tapped-corner marker ──────────────────────────────────────────

    private var markerProgram: Int = 0
    private var markerPositionAttr: Int = 0
    private var markerMvpUniform: Int = 0
    private var markerColorUniform: Int = 0

    fun onSurfaceCreated() {
        GLES20.glClearColor(0f, 0f, 0f, 1f)

        // Camera texture.
        val ids = IntArray(1)
        GLES20.glGenTextures(1, ids, 0)
        cameraTextureId = ids[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR
        )

        bgProgram = compileProgram(BG_VERT, BG_FRAG)
        bgPositionAttr = GLES20.glGetAttribLocation(bgProgram, "a_position")
        bgTexCoordAttr = GLES20.glGetAttribLocation(bgProgram, "a_texCoord")

        planeProgram = compileProgram(SIMPLE_VERT, SIMPLE_FRAG)
        planePositionAttr = GLES20.glGetAttribLocation(planeProgram, "a_position")
        planeMvpUniform = GLES20.glGetUniformLocation(planeProgram, "u_mvp")
        planeColorUniform = GLES20.glGetUniformLocation(planeProgram, "u_color")

        markerProgram = planeProgram
        markerPositionAttr = planePositionAttr
        markerMvpUniform = planeMvpUniform
        markerColorUniform = planeColorUniform
    }

    fun onSurfaceChanged(width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
    }

    fun drawBackground(frame: Frame) {
        // Update UVs to match the device orientation.
        if (frame.hasDisplayGeometryChanged()) {
            val srcUvs = floatArrayOf(
                0f, 0f,
                1f, 0f,
                0f, 1f,
                1f, 1f
            )
            val dst = FloatArray(8)
            frame.transformCoordinates2d(
                com.google.ar.core.Coordinates2d.OPENGL_NORMALIZED_DEVICE_COORDINATES,
                FloatBuffer.wrap(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f)),
                com.google.ar.core.Coordinates2d.TEXTURE_NORMALIZED,
                FloatBuffer.wrap(dst).also {
                    it.put(srcUvs)
                    it.position(0)
                }
            )
            bgUvCoords.position(0)
            bgUvCoords.put(dst)
            bgUvCoords.position(0)
        }

        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glDepthMask(false)

        GLES20.glUseProgram(bgProgram)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
        val sampler = GLES20.glGetUniformLocation(bgProgram, "u_camera")
        GLES20.glUniform1i(sampler, 0)

        GLES20.glEnableVertexAttribArray(bgPositionAttr)
        GLES20.glVertexAttribPointer(bgPositionAttr, 2, GLES20.GL_FLOAT, false, 0, bgQuadCoords)
        GLES20.glEnableVertexAttribArray(bgTexCoordAttr)
        GLES20.glVertexAttribPointer(bgTexCoordAttr, 2, GLES20.GL_FLOAT, false, 0, bgUvCoords)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(bgPositionAttr)
        GLES20.glDisableVertexAttribArray(bgTexCoordAttr)

        GLES20.glDepthMask(true)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
    }

    fun drawPlanes(planes: Collection<Plane>, projection: FloatArray, view: FloatArray) {
        if (planes.isEmpty()) return
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glUseProgram(planeProgram)
        GLES20.glUniform4f(planeColorUniform, 0.36f, 0.71f, 1f, 0.22f)

        val mvp = FloatArray(16)
        val viewProjection = FloatArray(16)
        Matrix.multiplyMM(viewProjection, 0, projection, 0, view, 0)

        for (plane in planes) {
            val polygon = plane.polygon ?: continue
            polygon.rewind()
            val count = polygon.remaining() / 2
            if (count < 3) continue
            // Plane polygon is XZ in plane-local space; lift to world via the
            // plane's centre pose, with y = 0 in plane frame.
            val planeMatrix = FloatArray(16)
            plane.centerPose.toMatrix(planeMatrix, 0)
            Matrix.multiplyMM(mvp, 0, viewProjection, 0, planeMatrix, 0)
            GLES20.glUniformMatrix4fv(planeMvpUniform, 1, false, mvp, 0)

            val vbo = FloatArray(count * 3)
            for (i in 0 until count) {
                vbo[i * 3] = polygon.get(i * 2)
                vbo[i * 3 + 1] = 0f
                vbo[i * 3 + 2] = polygon.get(i * 2 + 1)
            }
            val buf = floatBuffer(vbo)
            GLES20.glEnableVertexAttribArray(planePositionAttr)
            GLES20.glVertexAttribPointer(planePositionAttr, 3, GLES20.GL_FLOAT, false, 0, buf)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_FAN, 0, count)
            GLES20.glDisableVertexAttribArray(planePositionAttr)
        }

        GLES20.glDisable(GLES20.GL_BLEND)
    }

    /**
     * Draws a small yellow square per tapped XZ corner. Cheap and pose-
     * correct without needing per-marker model matrices.
     */
    fun drawTappedCorners(
        cornersXZ: List<FloatArray>,
        floorY: Float,
        projection: FloatArray,
        view: FloatArray
    ) {
        if (cornersXZ.isEmpty()) return
        GLES20.glUseProgram(markerProgram)
        GLES20.glUniform4f(markerColorUniform, 1f, 0.79f, 0f, 1f)

        val vp = FloatArray(16)
        Matrix.multiplyMM(vp, 0, projection, 0, view, 0)
        val mvp = FloatArray(16)
        val markerHalf = 0.04f

        for (corner in cornersXZ) {
            val x = corner[0]
            val z = corner[1]
            val model = FloatArray(16)
            Matrix.setIdentityM(model, 0)
            Matrix.translateM(model, 0, x, floorY + 0.005f, z)
            Matrix.multiplyMM(mvp, 0, vp, 0, model, 0)
            GLES20.glUniformMatrix4fv(markerMvpUniform, 1, false, mvp, 0)

            val verts = floatArrayOf(
                -markerHalf, 0f, -markerHalf,
                 markerHalf, 0f, -markerHalf,
                -markerHalf, 0f,  markerHalf,
                 markerHalf, 0f,  markerHalf
            )
            val buf = floatBuffer(verts)
            GLES20.glEnableVertexAttribArray(markerPositionAttr)
            GLES20.glVertexAttribPointer(markerPositionAttr, 3, GLES20.GL_FLOAT, false, 0, buf)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GLES20.glDisableVertexAttribArray(markerPositionAttr)
        }
    }

    /**
     * Draws a thin green quad strip between each consecutive pair of
     * tapped corners — i.e. the wall the user is in the middle of laying
     * down. We don't close the loop (no edge from last to first) until
     * the user explicitly finishes, since that edge often isn't a real
     * wall.
     *
     * The quad is laid flat on the floor plane: ±EDGE_HALF_WIDTH
     * perpendicular to the corner-to-corner vector, at `floorY + lift`.
     */
    fun drawEdges(
        cornersXZ: List<FloatArray>,
        floorY: Float,
        projection: FloatArray,
        view: FloatArray
    ) {
        if (cornersXZ.size < 2) return
        GLES20.glUseProgram(markerProgram)
        // Green, matches iOS SceneKit cylinder colour.
        GLES20.glUniform4f(markerColorUniform, 0.2f, 0.84f, 0.29f, 1f)

        val vp = FloatArray(16)
        Matrix.multiplyMM(vp, 0, projection, 0, view, 0)

        val identity = FloatArray(16).also { Matrix.setIdentityM(it, 0) }
        val mvp = FloatArray(16)
        Matrix.multiplyMM(mvp, 0, vp, 0, identity, 0)
        GLES20.glUniformMatrix4fv(markerMvpUniform, 1, false, mvp, 0)

        val edgeHalfWidth = 0.012f
        val lift = 0.003f // sit just under corner markers so they read in front

        for (i in 0 until cornersXZ.size - 1) {
            val a = cornersXZ[i]
            val b = cornersXZ[i + 1]
            val dx = b[0] - a[0]
            val dz = b[1] - a[1]
            val len = kotlin.math.sqrt(dx * dx + dz * dz)
            if (len < 1e-3) continue
            // Perpendicular in XZ, scaled to ±edgeHalfWidth.
            val px = -dz / len * edgeHalfWidth
            val pz = dx / len * edgeHalfWidth

            val verts = floatArrayOf(
                a[0] - px, floorY + lift, a[1] - pz,
                a[0] + px, floorY + lift, a[1] + pz,
                b[0] - px, floorY + lift, b[1] - pz,
                b[0] + px, floorY + lift, b[1] + pz
            )
            val buf = floatBuffer(verts)
            GLES20.glEnableVertexAttribArray(markerPositionAttr)
            GLES20.glVertexAttribPointer(markerPositionAttr, 3, GLES20.GL_FLOAT, false, 0, buf)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GLES20.glDisableVertexAttribArray(markerPositionAttr)
        }
    }

    /**
     * Draws a white annulus at the screen-centre raycast hit. Gives the
     * user a precise target before they tap — without it, accuracy on
     * walls and corners is poor because the user has to guess where the
     * camera's centre maps to.
     *
     * Pass `null` when no plane intersects the centre ray; the reticle
     * is simply not drawn that frame.
     */
    fun drawReticle(
        hit: FloatArray?,
        projection: FloatArray,
        view: FloatArray
    ) {
        if (hit == null || hit.size < 3) return
        val mesh = reticleMesh ?: buildReticleMesh().also { reticleMesh = it }

        GLES20.glUseProgram(markerProgram)
        GLES20.glUniform4f(markerColorUniform, 1f, 1f, 1f, 0.85f)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)

        val vp = FloatArray(16)
        Matrix.multiplyMM(vp, 0, projection, 0, view, 0)
        val model = FloatArray(16)
        Matrix.setIdentityM(model, 0)
        Matrix.translateM(model, 0, hit[0], hit[1] + 0.006f, hit[2])
        val mvp = FloatArray(16)
        Matrix.multiplyMM(mvp, 0, vp, 0, model, 0)
        GLES20.glUniformMatrix4fv(markerMvpUniform, 1, false, mvp, 0)

        GLES20.glEnableVertexAttribArray(markerPositionAttr)
        GLES20.glVertexAttribPointer(
            markerPositionAttr, 3, GLES20.GL_FLOAT, false, 0, mesh
        )
        GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, RETICLE_VERT_COUNT)
        GLES20.glDisableVertexAttribArray(markerPositionAttr)

        GLES20.glDisable(GLES20.GL_BLEND)
    }

    private var reticleMesh: FloatBuffer? = null

    /**
     * Generates an XZ-plane annulus with [RETICLE_SEGMENTS] subdivisions.
     * Each segment is two triangles (6 vertices) forming a thin ring
     * between [RETICLE_INNER_R] and [RETICLE_OUTER_R]. Cached after the
     * first draw — the mesh never changes.
     */
    private fun buildReticleMesh(): FloatBuffer {
        val verts = FloatArray(RETICLE_VERT_COUNT * 3)
        var w = 0
        for (i in 0 until RETICLE_SEGMENTS) {
            val a0 = i * 2.0 * Math.PI / RETICLE_SEGMENTS
            val a1 = (i + 1) * 2.0 * Math.PI / RETICLE_SEGMENTS
            val cos0 = kotlin.math.cos(a0).toFloat()
            val sin0 = kotlin.math.sin(a0).toFloat()
            val cos1 = kotlin.math.cos(a1).toFloat()
            val sin1 = kotlin.math.sin(a1).toFloat()

            val ix0 = RETICLE_INNER_R * cos0
            val iz0 = RETICLE_INNER_R * sin0
            val ox0 = RETICLE_OUTER_R * cos0
            val oz0 = RETICLE_OUTER_R * sin0
            val ix1 = RETICLE_INNER_R * cos1
            val iz1 = RETICLE_INNER_R * sin1
            val ox1 = RETICLE_OUTER_R * cos1
            val oz1 = RETICLE_OUTER_R * sin1

            // Triangle 1: inner0, outer0, inner1
            verts[w++] = ix0; verts[w++] = 0f; verts[w++] = iz0
            verts[w++] = ox0; verts[w++] = 0f; verts[w++] = oz0
            verts[w++] = ix1; verts[w++] = 0f; verts[w++] = iz1
            // Triangle 2: inner1, outer0, outer1
            verts[w++] = ix1; verts[w++] = 0f; verts[w++] = iz1
            verts[w++] = ox0; verts[w++] = 0f; verts[w++] = oz0
            verts[w++] = ox1; verts[w++] = 0f; verts[w++] = oz1
        }
        return floatBuffer(verts)
    }

    // ── Shader helpers ────────────────────────────────────────────────

    private fun compileProgram(vertSrc: String, fragSrc: String): Int {
        val v = compileShader(GLES20.GL_VERTEX_SHADER, vertSrc)
        val f = compileShader(GLES20.GL_FRAGMENT_SHADER, fragSrc)
        val program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, v)
        GLES20.glAttachShader(program, f)
        GLES20.glLinkProgram(program)
        val link = IntArray(1)
        GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, link, 0)
        if (link[0] == 0) {
            val log = GLES20.glGetProgramInfoLog(program)
            GLES20.glDeleteProgram(program)
            throw RuntimeException("GLES program link failed: $log")
        }
        return program
    }

    private fun compileShader(type: Int, src: String): Int {
        val s = GLES20.glCreateShader(type)
        GLES20.glShaderSource(s, src)
        GLES20.glCompileShader(s)
        val ok = IntArray(1)
        GLES20.glGetShaderiv(s, GLES20.GL_COMPILE_STATUS, ok, 0)
        if (ok[0] == 0) {
            val log = GLES20.glGetShaderInfoLog(s)
            GLES20.glDeleteShader(s)
            throw RuntimeException("GLES shader compile failed: $log")
        }
        return s
    }

    private fun floatBuffer(data: FloatArray): FloatBuffer {
        val bb = ByteBuffer.allocateDirect(data.size * 4).order(ByteOrder.nativeOrder())
        return bb.asFloatBuffer().apply {
            put(data)
            position(0)
        }
    }

    companion object {
        private const val RETICLE_SEGMENTS = 24
        private const val RETICLE_INNER_R = 0.040f
        private const val RETICLE_OUTER_R = 0.052f
        private const val RETICLE_VERT_COUNT = RETICLE_SEGMENTS * 6


        private const val BG_VERT = """
            attribute vec2 a_position;
            attribute vec2 a_texCoord;
            varying vec2 v_texCoord;
            void main() {
                v_texCoord = a_texCoord;
                gl_Position = vec4(a_position, 0.0, 1.0);
            }
        """

        private const val BG_FRAG = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            uniform samplerExternalOES u_camera;
            varying vec2 v_texCoord;
            void main() {
                gl_FragColor = texture2D(u_camera, v_texCoord);
            }
        """

        private const val SIMPLE_VERT = """
            attribute vec3 a_position;
            uniform mat4 u_mvp;
            void main() {
                gl_Position = u_mvp * vec4(a_position, 1.0);
            }
        """

        private const val SIMPLE_FRAG = """
            precision mediump float;
            uniform vec4 u_color;
            void main() {
                gl_FragColor = u_color;
            }
        """
    }
}
