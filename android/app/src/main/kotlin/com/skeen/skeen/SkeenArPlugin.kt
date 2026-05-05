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

import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import java.io.ByteArrayOutputStream

/**
 * Bridges the Detection bounded context's ArSessionPort to ARCore.
 * Modified to support a native GLSurfaceView PlatformView.
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

    // For GLSurfaceView integration
    private var displayWidth = 0
    private var displayHeight = 0
    private var displayRotation = 0

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
            "captureFrame" -> {
                // Return in background thread to not block UI
                Thread {
                    val bytes = captureFrame()
                    handler.post { result.success(bytes) }
                }.start()
            }
            "setFlash" -> result.success(null)
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

    private var pendingTexId: Int? = null
    private var isStarted = false

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
            session = s
            isStarted = true

            pendingTexId?.let {
                s.setCameraTextureName(it)
                s.resume()
            }
            startDepthSampling()
        } catch (e: Throwable) {
            // Error handling
        }
    }

    private fun stop() {
        samplingRunnable?.let { handler.removeCallbacks(it) }
        samplingRunnable = null
        session?.pause()
        session?.close()
        session = null
    }

    fun setCameraTextureName(texId: Int) {
        pendingTexId = texId
        if (isStarted) {
            val s = session
            s?.setCameraTextureName(texId)
            s?.resume()
        }
    }

    fun setDisplayGeometry(width: Int, height: Int) {
        displayWidth = width
        displayHeight = height
        displayRotation = activity?.windowManager?.defaultDisplay?.rotation ?: 0
        session?.setDisplayGeometry(displayRotation, width, height)
    }

    fun updateSession(): Frame? {
        return try {
            session?.update()
        } catch (e: Throwable) {
            null
        }
    }

    fun getTransformedTexCoords(coords: FloatArray): FloatArray {
        val frame = try { session?.update() } catch (e: Throwable) { null }
        if (frame == null || !frame.hasDisplayGeometryChanged()) {
            return coords
        }
        val buffer = ByteBuffer.allocateDirect(coords.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        buffer.put(coords)
        buffer.position(0)
        
        val transformed = ByteBuffer.allocateDirect(coords.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        frame.transformDisplayUvCoords(buffer, transformed)
        
        val out = FloatArray(coords.size)
        transformed.position(0)
        transformed.get(out)
        return out
    }

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

    private fun hitTest(nx: Float, ny: Float): Map<String, Any>? {
        val s = session ?: return null
        return try {
            val frame = s.update()
            val w = displayWidth.toFloat().takeIf { it > 0 } ?: 1080f
            val h = displayHeight.toFloat().takeIf { it > 0 } ?: 1920f
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
        val s = session ?: return null
        return try {
            val frame = s.update()
            val image = frame.acquireCameraImage()
            
            // Convert YUV_420_888 to NV21 for JPEG compression
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
        } catch (e: Throwable) {
            null
        }
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
