package com.skeen.skeen

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var arPlugin: SkeenArPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val plugin = SkeenArPlugin(applicationContext).also {
            it.activity = this
            arPlugin = it
        }

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "skeen.detection/ar_view",
            ArCoreViewFactory(plugin)
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "skeen.detection/ar"
        ).setMethodCallHandler(plugin)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "skeen.detection/ar/distance"
        ).setStreamHandler(plugin)

        // Pinhole intrinsics for the marker-based pose (WP-1). Both keys
        // are mandatory Camera2 characteristics on every hardware level, so
        // a null here means a genuinely broken HAL, not a low-end device.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "skeen.detection/camera_intrinsics"
        ).setMethodCallHandler { call, result ->
            if (call.method == "read") {
                result.success(readBackCameraIntrinsics())
            } else {
                result.notImplemented()
            }
        }
    }

    /**
     * Focal length (mm) and physical sensor size (mm) of the first
     * back-facing camera — the same selection rule the `camera` plugin
     * applies, so the numbers describe the stream the detector sees.
     */
    private fun readBackCameraIntrinsics(): Map<String, Any>? {
        return try {
            val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val id = manager.cameraIdList.firstOrNull { cid ->
                manager.getCameraCharacteristics(cid)
                    .get(CameraCharacteristics.LENS_FACING) ==
                    CameraCharacteristics.LENS_FACING_BACK
            } ?: return null
            val c = manager.getCameraCharacteristics(id)
            val focals = c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
            val size = c.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
            if (focals == null || focals.isEmpty() || size == null) return null
            val active = c.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
            mapOf(
                "focalMm" to focals[0].toDouble(),
                "sensorWidthMm" to size.width.toDouble(),
                "sensorHeightMm" to size.height.toDouble(),
                "activeWidth" to (active?.width() ?: 0),
                "activeHeight" to (active?.height() ?: 0)
            )
        } catch (_: Throwable) {
            null
        }
    }

    override fun onResume() {
        super.onResume()
        arPlugin?.onActivityResume()
    }

    override fun onPause() {
        arPlugin?.onActivityPause()
        super.onPause()
    }
}
