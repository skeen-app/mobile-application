package com.skeen.skeen

import android.app.Activity
import android.content.Context
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.Handler
import android.os.Looper
import com.google.ar.core.Anchor
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Config
import com.google.ar.core.Coordinates2d
import com.google.ar.core.Frame
import com.google.ar.core.Plane
import com.google.ar.core.Point
import com.google.ar.core.Pose
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.UnavailableException
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap

/**
 * Bridges the Detection bounded context's ArSessionPort to ARCore.
 *
 * Threading model:
 *   • [updateSession] is the ONLY caller of Session.update(); it runs on the
 *     GL thread (driven by [ArCoreView]) and stores the latest [Frame] in a
 *     volatile field.
 *   • All MethodChannel calls (hitTest, projectToScreen, depth sampling) read
 *     from [lastFrame] — never call session.update() off the GL thread.
 *   • Anchors live in a thread-safe map keyed by id so the Dart side can
 *     project their *current* tracked pose every frame, mimicking the
 *     Pokémon-GO style "popup pegado a la piel".
 */
class SkeenArPlugin(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private var session: Session? = null
    private var depthSupported: Boolean = false
    private var distanceSink: EventChannel.EventSink? = null
    private val handler = Handler(Looper.getMainLooper())
    private val sampleRateMs = 100L
    private var samplingRunnable: Runnable? = null
    private var pendingTexId: Int? = null
    private var isRunning = false
    private var flashOn = false

    @Volatile private var lastFrame: Frame? = null

    private val anchors = ConcurrentHashMap<String, Anchor>()

    var activity: Activity? = null
        set(value) {
            field = value
            // ARCore install prompts require an Activity reference.
        }

    private var displayWidth = 0
    private var displayHeight = 0
    private var displayRotation = 0

    // ── Lifecycle delegated from MainActivity ─────────────────────────

    fun onActivityResume() {
        val s = session ?: return
        try {
            val texId = pendingTexId
            if (texId != null) s.setCameraTextureName(texId)
            s.resume()
            isRunning = true
        } catch (e: Throwable) {
            // ARCore may throw CameraNotAvailableException — swallow; the
            // user can retry by reopening the screen.
        }
    }

    fun onActivityPause() {
        try {
            session?.pause()
            isRunning = false
        } catch (_: Throwable) {}
    }

    // ── MethodChannel ─────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probeCapabilities" -> result.success(probeCapabilities())
            "start" -> {
                start()
                result.success(null)
            }
            "stop" -> {
                stop()
                result.success(null)
            }
            "hitTest" -> {
                val x = (call.argument<Double>("x") ?: 0.5)
                val y = (call.argument<Double>("y") ?: 0.5)
                result.success(hitTest(x.toFloat(), y.toFloat()))
            }
            "projectToScreen" -> {
                val map = call.arguments as? Map<*, *>
                result.success(projectToScreen(map))
            }
            "anchorState" -> {
                val id = call.argument<String>("id")
                result.success(anchorState(id))
            }
            "captureFrame" -> {
                Thread {
                    val bytes = captureFrame()
                    handler.post { result.success(bytes) }
                }.start()
            }
            "setFlash" -> {
                val on = call.argument<Boolean>("on") ?: false
                setFlashTorch(on)
                result.success(null)
            }
            "setZoom" -> result.success(null)
            "removeAnchor" -> {
                val id = call.argument<String>("id")
                if (id != null) {
                    anchors.remove(id)?.detach()
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun probeCapabilities(): Map<String, Any> {
        val availability = ArCoreApk.getInstance().checkAvailability(context)
        val hasArSupport = availability.isSupported
        val hasDepth = try {
            val tmp = Session(context)
            val supported = tmp.isDepthModeSupported(Config.DepthMode.AUTOMATIC)
            tmp.close()
            supported
        } catch (e: UnavailableException) {
            false
        } catch (e: Throwable) {
            false
        }
        depthSupported = hasDepth
        return mapOf(
            "hasArSupport" to hasArSupport,
            "hasDepthSensor" to hasDepth
        )
    }

    private fun start() {
        if (session != null) return
        val act = activity
        try {
            // Trigger ARCore install if missing — first call returns
            // INSTALL_REQUESTED, second call returns INSTALLED.
            if (act != null) {
                when (ArCoreApk.getInstance().requestInstall(act, true)) {
                    ArCoreApk.InstallStatus.INSTALL_REQUESTED -> return
                    ArCoreApk.InstallStatus.INSTALLED -> Unit
                    null -> Unit
                }
            }

            val s = Session(context)
            val config = Config(s).apply {
                if (s.isDepthModeSupported(Config.DepthMode.AUTOMATIC)) {
                    depthMode = Config.DepthMode.AUTOMATIC
                    depthSupported = true
                }
                planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
                focusMode = Config.FocusMode.AUTO
                lightEstimationMode = Config.LightEstimationMode.AMBIENT_INTENSITY
                updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
            }
            s.configure(config)
            session = s

            // Camera texture is bound from the GL thread; resume happens
            // either there or in onActivityResume once both texId and
            // session exist.
            pendingTexId?.let { s.setCameraTextureName(it) }
            try {
                s.resume()
                isRunning = true
            } catch (_: Throwable) {
                // Will retry from onActivityResume / GL thread setCameraTextureName.
            }
            startDepthSampling()
        } catch (_: Throwable) {
            session = null
        }
    }

    private fun stop() {
        samplingRunnable?.let { handler.removeCallbacks(it) }
        samplingRunnable = null
        anchors.values.forEach { it.detach() }
        anchors.clear()
        try {
            session?.pause()
            session?.close()
        } catch (_: Throwable) {}
        session = null
        lastFrame = null
        isRunning = false
    }

    // ── GL thread API (called by ArCoreView) ──────────────────────────

    fun setCameraTextureName(texId: Int) {
        pendingTexId = texId
        val s = session ?: return
        try {
            s.setCameraTextureName(texId)
            if (!isRunning) {
                s.resume()
                isRunning = true
            }
        } catch (_: Throwable) {}
    }

    fun setDisplayGeometry(width: Int, height: Int) {
        displayWidth = width
        displayHeight = height
        // The Flutter screen locks to portrait while AR is open, so we
        // always pass Surface.ROTATION_0. This avoids the camera image
        // appearing landscape-stretched when the platform-view's hosting
        // surface was created with a different rotation than the display.
        displayRotation = 0
        try {
            session?.setDisplayGeometry(displayRotation, width, height)
            // Force a fresh transform on the next frame.
            cachedTexCoords = null
        } catch (_: Throwable) {}
    }

    /** Called on the GL thread once per frame. Returns the latest [Frame]. */
    fun updateSession(): Frame? {
        return try {
            val s = session ?: return null
            val frame = s.update()
            lastFrame = frame
            frame
        } catch (_: Throwable) {
            null
        }
    }

    /**
     * Maps the fullscreen NDC quad vertices into texture coordinates that
     * sample the camera image with the correct rotation AND aspect ratio.
     *
     * The previous API (`transformDisplayUvCoords`) only handled rotation —
     * if the viewport aspect didn't match the camera image aspect the feed
     * appeared stretched. `transformCoordinates2d` from NDC → TEXTURE is the
     * supported replacement and handles both.
     *
     * Recomputed only when [Frame.hasDisplayGeometryChanged] flips, then
     * cached for subsequent frames.
     */
    private val ndcQuadCoords = floatArrayOf(
        -1f, -1f,
        -1f, 1f,
        1f, -1f,
        1f, 1f
    )
    private var cachedTexCoords: FloatArray? = null

    fun getTransformedTexCoords(@Suppress("UNUSED_PARAMETER") fallback: FloatArray): FloatArray {
        val frame = lastFrame
        val cached = cachedTexCoords
        if (frame != null && (cached == null || frame.hasDisplayGeometryChanged())) {
            try {
                val ndc = ByteBuffer.allocateDirect(ndcQuadCoords.size * 4)
                    .order(ByteOrder.nativeOrder()).asFloatBuffer()
                ndc.put(ndcQuadCoords); ndc.position(0)
                val out = ByteBuffer.allocateDirect(ndcQuadCoords.size * 4)
                    .order(ByteOrder.nativeOrder()).asFloatBuffer()
                frame.transformCoordinates2d(
                    Coordinates2d.OPENGL_NORMALIZED_DEVICE_COORDINATES,
                    ndc,
                    Coordinates2d.TEXTURE_NORMALIZED,
                    out
                )
                val arr = FloatArray(ndcQuadCoords.size)
                out.position(0); out.get(arr)
                cachedTexCoords = arr
                return arr
            } catch (_: Throwable) {
                // fall through to last known mapping
            }
        }
        return cached ?: floatArrayOf(0f, 1f, 0f, 0f, 1f, 1f, 1f, 0f)
    }

    // ── Anchor / projection ───────────────────────────────────────────

    /**
     * Hit-test the (normalized) screen point and create a *real* tracked
     * [Anchor] when a Plane / Point / DepthPoint is found. The Anchor is
     * stored in [anchors] so subsequent projection calls follow its tracked
     * pose — this is what makes the popup stick to the skin.
     */
    private fun hitTest(nx: Float, ny: Float): Map<String, Any>? {
        val frame = lastFrame ?: return null
        val s = session ?: return null
        return try {
            val w = displayWidth.toFloat().takeIf { it > 0 } ?: 1080f
            val h = displayHeight.toFloat().takeIf { it > 0 } ?: 1920f
            val results = frame.hitTest(nx * w, ny * h)
            val preferred = results.firstOrNull { hr ->
                val t = hr.trackable
                (t is Plane && t.isPoseInPolygon(hr.hitPose)) ||
                    t is Point ||
                    t.javaClass.simpleName == "DepthPoint"
            } ?: results.firstOrNull()

            // Skin is curved → ARCore rarely produces a plane hit. When no
            // hit lands, synthesize a session-level anchor at ~15 cm in
            // front of the camera. ARCore still tracks it relative to the
            // world, so the popup follows phone motion just like a real
            // raycast anchor.
            val anchor: Anchor = if (preferred != null) {
                preferred.createAnchor()
            } else {
                val cam = frame.camera.pose
                val zAxis = cam.zAxis
                val forwardDist = 0.15f
                val tx = cam.tx() - zAxis[0] * forwardDist
                val ty = cam.ty() - zAxis[1] * forwardDist
                val tz = cam.tz() - zAxis[2] * forwardDist
                s.createAnchor(Pose.makeTranslation(tx, ty, tz))
            }

            val id = "anchor-${System.nanoTime()}"
            anchors[id] = anchor
            poseToMap(anchor.pose, id)
        } catch (_: Throwable) {
            null
        }
    }

    /**
     * Project an anchor (by id) — or a static world pose — into normalized
     * screen coords [0..1]. Returns visible=false when behind camera or not
     * currently tracked.
     */
    private fun projectToScreen(map: Map<*, *>?): Map<String, Any>? {
        if (map == null) return null
        val frame = lastFrame ?: return null
        val camera = frame.camera
        if (camera.trackingState != TrackingState.TRACKING) {
            return mapOf("visible" to false)
        }

        val pose = (map["id"] as? String)?.let { id ->
            anchors[id]?.let { if (it.trackingState == TrackingState.TRACKING) it.pose else null }
        } ?: run {
            val tx = (map["tx"] as Number).toFloat()
            val ty = (map["ty"] as Number).toFloat()
            val tz = (map["tz"] as Number).toFloat()
            Pose.makeTranslation(tx, ty, tz)
        }

        val proj = FloatArray(16); camera.getProjectionMatrix(proj, 0, 0.1f, 100.0f)
        val view = FloatArray(16); camera.getViewMatrix(view, 0)
        val world = floatArrayOf(pose.tx(), pose.ty(), pose.tz(), 1f)
        val viewSpace = multiplyMV(view, world)
        // viewSpace.z < 0 means in front of camera in OpenGL convention
        val inFront = viewSpace[2] < 0
        val clip = multiplyMV(proj, viewSpace)
        if (clip[3] == 0f) return mapOf("visible" to false)
        val ndcX = clip[0] / clip[3]
        val ndcY = clip[1] / clip[3]
        val visibleNdc = ndcX in -1f..1f && ndcY in -1f..1f && inFront
        return mapOf(
            "visible" to visibleNdc,
            "sx" to (ndcX * 0.5f + 0.5f),
            "sy" to (1f - (ndcY * 0.5f + 0.5f))
        )
    }

    private fun anchorState(id: String?): Map<String, Any> {
        val a = id?.let { anchors[it] }
        val state = a?.trackingState?.name ?: "NONE"
        return mapOf("state" to state, "exists" to (a != null))
    }

    // ── Flash (torch) ─────────────────────────────────────────────────
    // ARCore ≥1.40 supports Config.FlashMode.TORCH which lets the session
    // own the camera *and* drive the torch. Reconfigure the session in place.

    private fun setFlashTorch(on: Boolean) {
        flashOn = on
        val s = session ?: return
        try {
            val cfg = s.config
            cfg.flashMode = if (on) Config.FlashMode.TORCH else Config.FlashMode.OFF
            s.configure(cfg)
        } catch (_: Throwable) {
            // Older ARCore versions may not expose FlashMode — flash will
            // still work via the camera plugin path on those devices.
        }
    }

    // ── Depth sampling ────────────────────────────────────────────────

    private fun startDepthSampling() {
        samplingRunnable?.let { handler.removeCallbacks(it) }
        val tick = object : Runnable {
            override fun run() {
                val frame = lastFrame
                if (frame != null) {
                    var cm: Double = Double.NaN
                    var depthEstimated = true
                    if (depthSupported) {
                        try {
                            val depth = frame.acquireDepthImage16Bits()
                            val plane = depth.planes[0]
                            val width = depth.width
                            val height = depth.height
                            val cx = width / 2
                            val cy = height / 2
                            val rowStride = plane.rowStride
                            val pixelStride = plane.pixelStride
                            val buf = plane.buffer
                            val offset = cy * rowStride + cx * pixelStride
                            val mm = (buf.order(ByteOrder.nativeOrder())
                                .getShort(offset).toInt() and 0xFFFF)
                            depth.close()
                            cm = mm / 10.0
                            depthEstimated = false
                        } catch (_: Throwable) {
                            cm = Double.NaN
                            depthEstimated = true
                        }
                    }
                    // Pixel intensity ∈ [0,1]; multiply by 255 so the Dart
                    // brightness scoring (0–255 mean Y) stays unchanged.
                    val pixelIntensity = try {
                        frame.lightEstimate?.pixelIntensity ?: -1f
                    } catch (_: Throwable) { -1f }
                    val brightness255 = if (pixelIntensity >= 0f) {
                        (pixelIntensity * 255f).toDouble()
                    } else Double.NaN
                    val tracking = try {
                        frame.camera.trackingState.name
                    } catch (_: Throwable) { "STOPPED" }

                    distanceSink?.success(mapOf(
                        "cm" to cm,
                        "estimated" to depthEstimated,
                        "brightness" to brightness255,
                        "tracking" to tracking
                    ))
                }
                handler.postDelayed(this, sampleRateMs)
            }
        }
        samplingRunnable = tick
        handler.postDelayed(tick, sampleRateMs)
    }

    // ── Frame capture (used as fallback when camera plugin isn't present) ──

    private fun captureFrame(): ByteArray? {
        val frame = lastFrame ?: return null
        return try {
            val image = frame.acquireCameraImage()
            val yBuffer = image.planes[0].buffer
            val uBuffer = image.planes[1].buffer
            val vBuffer = image.planes[2].buffer
            val ySize = yBuffer.remaining()
            val uSize = uBuffer.remaining()
            val vSize = vBuffer.remaining()
            val nv21 = ByteArray(ySize + uSize + vSize)
            yBuffer.get(nv21, 0, ySize)
            vBuffer.get(nv21, ySize, vSize)
            uBuffer.get(nv21, ySize + vSize, uSize)
            val width = image.width
            val height = image.height
            image.close()
            val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, null)
            val out = ByteArrayOutputStream()
            yuvImage.compressToJpeg(Rect(0, 0, width, height), 90, out)
            out.toByteArray()
        } catch (_: Throwable) {
            null
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────

    private fun poseToMap(pose: Pose, id: String): Map<String, Any> {
        val t = FloatArray(3); pose.getTranslation(t, 0)
        val r = FloatArray(4); pose.getRotationQuaternion(r, 0)
        return mapOf(
            "id" to id,
            "tx" to t[0].toDouble(),
            "ty" to t[1].toDouble(),
            "tz" to t[2].toDouble(),
            "qx" to r[0].toDouble(),
            "qy" to r[1].toDouble(),
            "qz" to r[2].toDouble(),
            "qw" to r[3].toDouble()
        )
    }

    private fun multiplyMV(m: FloatArray, v: FloatArray): FloatArray {
        val out = FloatArray(4)
        for (i in 0..3) {
            out[i] = m[i] * v[0] + m[i + 4] * v[1] + m[i + 8] * v[2] + m[i + 12] * v[3]
        }
        return out
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        distanceSink = events
    }

    override fun onCancel(arguments: Any?) {
        distanceSink = null
    }
}
