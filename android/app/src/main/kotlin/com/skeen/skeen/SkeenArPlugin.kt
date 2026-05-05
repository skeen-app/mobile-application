package com.skeen.skeen

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Pose
import com.google.ar.core.Session
import com.google.ar.core.exceptions.UnavailableException
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.sqrt

/**
 * Bridges the Detection bounded context's ArSessionPort to ARCore.
 *
 * Surfaces three capabilities to Dart:
 *   1. probeCapabilities — reports AR + Depth API support
 *   2. EventChannel("…/distance") — streams cm-to-skin readings (Depth API
 *      sampled at the screen-center pixel, throttled to ~10 Hz)
 *   3. hitTest / projectToScreen / captureFrame / setFlash / setZoom
 *
 * Depth-less devices: probeCapabilities returns hasDepthSensor=false; the
 * router screen mounts the plain camera fallback instead of the AR view.
 *
 * NOTE: this plugin is method-channel only — it does not own a PlatformView.
 * The CameraPreview surface is managed by the existing `camera` plugin so
 * the AR overlay can sit on top of the same preview the fallback uses.
 * Hit-tests and depth come from a parallel ARCore Session that consumes
 * frames internally without rendering its own surface.
 */
class SkeenArPlugin(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private var session: Session? = null
    private var depthSupported: Boolean = false
    private var distanceSink: EventChannel.EventSink? = null
    private val handler = Handler(Looper.getMainLooper())
    private val sampleRateMs = 100L
    private var samplingRunnable: Runnable? = null

    var activity: Activity? = null

    override fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
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
            "captureFrame" -> result.success(captureFrame())
            "setFlash" -> {
                // Camera plugin owns the device camera in this build, so
                // flash toggling is handled Dart-side via CameraController.
                result.success(null)
            }
            "setZoom" -> result.success(null)
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
        try {
            val s = Session(context)
            val config = Config(s).apply {
                if (depthSupported) {
                    depthMode = Config.DepthMode.AUTOMATIC
                }
                planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
                focusMode = Config.FocusMode.AUTO
            }
            s.configure(config)
            s.resume()
            session = s
            startDepthSampling()
        } catch (e: Throwable) {
            // Surface as null distance reading; Dart side already handles
            // CaptureDistance.unknown() as a graceful state.
        }
    }

    private fun stop() {
        samplingRunnable?.let { handler.removeCallbacks(it) }
        samplingRunnable = null
        session?.pause()
        session?.close()
        session = null
    }

    /**
     * Polls the depth image at the screen-center pixel ~10× per second.
     * The Depth API returns millimeters in the 16-bit channel; we convert
     * to centimeters before pushing to Dart.
     */
    private fun startDepthSampling() {
        if (!depthSupported) return
        val tick = object : Runnable {
            override fun run() {
                val s = session ?: return
                try {
                    val frame: Frame = s.update()
                    val depth = frame.acquireDepthImage16Bits()
                    val plane = depth.planes[0]
                    val width = depth.width
                    val height = depth.height
                    val centerX = width / 2
                    val centerY = height / 2
                    val rowStride = plane.rowStride
                    val pixelStride = plane.pixelStride
                    val buf = plane.buffer
                    val offset = centerY * rowStride + centerX * pixelStride
                    val mm = (buf.order(ByteOrder.nativeOrder())
                        .getShort(offset).toInt() and 0xFFFF)
                    depth.close()
                    val cm = mm / 10.0
                    distanceSink?.success(
                        mapOf("cm" to cm, "estimated" to false)
                    )
                } catch (e: Throwable) {
                    distanceSink?.success(
                        mapOf("cm" to Double.NaN, "estimated" to true)
                    )
                }
                handler.postDelayed(this, sampleRateMs)
            }
        }
        samplingRunnable = tick
        handler.post(tick)
    }

    /**
     * Hit-test against detected planes at the given normalized screen point.
     * Returns the world pose of the first plane hit, or null.
     */
    private fun hitTest(nx: Float, ny: Float): Map<String, Any>? {
        val s = session ?: return null
        return try {
            val frame = s.update()
            // ARCore expects pixel coords in the active display dimensions;
            // approximate from normalized coords using the depth image size.
            val w = 1080f
            val h = 1920f
            val results = frame.hitTest(nx * w, ny * h)
            val hit = results.firstOrNull() ?: return null
            poseToMap(hit.hitPose, "hit-${System.nanoTime()}")
        } catch (e: Throwable) {
            null
        }
    }

    private fun projectToScreen(map: Map<*, *>?): Map<String, Any>? {
        val s = session ?: return null
        if (map == null) return null
        return try {
            val frame = s.update()
            val camera = frame.camera
            val proj = FloatArray(16)
            val view = FloatArray(16)
            camera.getProjectionMatrix(proj, 0, 0.1f, 100.0f)
            camera.getViewMatrix(view, 0)
            val tx = (map["tx"] as Number).toFloat()
            val ty = (map["ty"] as Number).toFloat()
            val tz = (map["tz"] as Number).toFloat()
            val world = floatArrayOf(tx, ty, tz, 1f)
            val viewSpace = multiplyMV(view, world)
            val clip = multiplyMV(proj, viewSpace)
            if (clip[3] == 0f) return mapOf("visible" to false)
            val ndcX = clip[0] / clip[3]
            val ndcY = clip[1] / clip[3]
            val ndcZ = clip[2] / clip[3]
            val visible = ndcZ in -1f..1f
            mapOf(
                "visible" to visible,
                "sx" to (ndcX * 0.5f + 0.5f),
                "sy" to (1f - (ndcY * 0.5f + 0.5f))
            )
        } catch (e: Throwable) {
            null
        }
    }

    private fun captureFrame(): ByteArray? {
        // Frame capture for inference is owned by the Dart `camera` plugin
        // (it already runs the preview surface). Returning null here lets
        // the controller fall through to that path.
        return null
    }

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
