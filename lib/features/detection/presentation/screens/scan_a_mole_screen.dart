import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_top_app_bar.dart';
import '../../domain/capture_quality.dart';
import '../../infrastructure/scan_camera_service.dart';
import '../widgets/ar_reticle_overlay.dart';
import '../widgets/camera_controls.dart';
import '../widgets/scan_capture_button.dart';
import '../widgets/scan_quality_hint.dart';

/// Live AR-guided mole capture screen (Figma `escaner` 149:125).
///
/// Opens the rear camera as soon as it mounts, overlays the skeen reticle,
/// streams a luminance signal from the camera plugin into [CaptureQuality]
/// to coach non-expert users on lighting/framing, then exposes a shutter
/// that hands the resulting [XFile] back to the caller via `context.pop`.
/// Inference itself is downstream of this screen — capture only.
class ScanAMoleScreen extends StatefulWidget {
  const ScanAMoleScreen({super.key});

  @override
  State<ScanAMoleScreen> createState() => _ScanAMoleScreenState();
}

class _ScanAMoleScreenState extends State<ScanAMoleScreen>
    with WidgetsBindingObserver {
  final ScanCameraService _service = ScanCameraService();
  StreamSubscription<double>? _brightnessSub;

  CaptureQuality _quality = CaptureQuality.initial;
  bool _isCapturing = false;
  bool _showShutterFlash = false;
  bool _flashOn = false;
  double _zoom = 1.0;
  double _maxZoom = 5.0;
  String? _initError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _service.initialize();
      _brightnessSub = _service.brightness.listen((value) {
        if (!mounted) return;
        setState(() => _quality = CaptureQuality.fromBrightness(value));
      });
      final ctl = _service.controller;
      if (ctl != null) {
        try {
          _maxZoom = (await ctl.getMaxZoomLevel()).clamp(1.0, 8.0);
        } catch (_) {/* keep default */}
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (kDebugMode) debugPrint('Camera init failed: $e');
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  Future<void> _toggleFlash() async {
    final ctl = _service.controller;
    if (ctl == null) return;
    final next = !_flashOn;
    try {
      await ctl.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _flashOn = next);
    } catch (e) {
      if (kDebugMode) debugPrint('Flash toggle failed: $e');
    }
  }

  Future<void> _setZoom(double value) async {
    final ctl = _service.controller;
    if (ctl == null) return;
    final clamped = value.clamp(1.0, _maxZoom);
    try {
      await ctl.setZoomLevel(clamped);
      if (mounted) setState(() => _zoom = clamped);
    } catch (e) {
      if (kDebugMode) debugPrint('Zoom failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Camera resources must be released when the app backgrounds, otherwise
    // the OS will tear them down for us and crash the next resume.
    final controller = _service.controller;
    if (controller == null) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _service.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _bootstrap();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _brightnessSub?.cancel();
    _service.dispose();
    super.dispose();
  }

  Future<void> _handleCapture() async {
    if (_isCapturing) return;
    setState(() {
      _isCapturing = true;
      _showShutterFlash = true;
    });

    // Brief white flash to mimic a shutter — purely aesthetic feedback.
    Future.delayed(const Duration(milliseconds: 140), () {
      if (mounted) setState(() => _showShutterFlash = false);
    });

    final file = await _service.capture();
    if (!mounted) return;

    setState(() => _isCapturing = false);

    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Capture failed — please try again')),
      );
      return;
    }

    // Hand the captured file back to the caller. Downstream screens (upload
    // / inference) decide what to do with it; this screen's job ends here.
    if (context.canPop()) {
      context.pop(file.path);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Photo saved: ${file.name}')),
      );
    }
  }

  Future<void> _handleTapToFocus(TapDownDetails details, Size previewSize) {
    final dx = (details.localPosition.dx / previewSize.width).clamp(0.0, 1.0);
    final dy = (details.localPosition.dy / previewSize.height).clamp(0.0, 1.0);
    return _service.focusAt(Offset(dx, dy));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SkeenTopAppBar(
              title: 'Scan a mole',
              subtitle: 'AI analysis in seconds',
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _buildPreviewSurface(),
                ),
              ),
            ),
            _buildBottomControls(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewSurface() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.indigo,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF291859), width: 2),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            fit: StackFit.expand,
            children: [
              if (_initError != null)
                _CameraUnavailable(message: _initError!)
              else if (_service.isReady)
                GestureDetector(
                  onTapDown: (d) => _handleTapToFocus(d, size),
                  child: _FittedPreview(controller: _service.controller!),
                )
              else
                const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.violetaClaro,
                    ),
                  ),
                ),
              ArReticleOverlay(quality: _quality),
              Positioned(
                top: 16,
                right: 16,
                child: CameraFlashButton(
                  isOn: _flashOn,
                  onTap: _toggleFlash,
                ),
              ),
              Positioned(
                top: 70,
                right: 16,
                bottom: 16,
                child: CameraZoomSlider(
                  value: _zoom,
                  min: 1.0,
                  max: _maxZoom,
                  onChanged: _setZoom,
                ),
              ),
              AnimatedOpacity(
                opacity: _showShutterFlash ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: Container(color: Colors.white),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          ScanQualityHint(quality: _quality),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SecondaryAction(
                icon: Icons.photo_library_outlined,
                label: 'Gallery',
                onTap: () => context.pushNamed('upload-photo'),
              ),
              ScanCaptureButton(
                quality: _quality,
                isCapturing: _isCapturing,
                onPressed: _handleCapture,
              ),
              _SecondaryAction(
                icon: Icons.tune_rounded,
                label: 'Calibrate',
                onTap: () => context.pushNamed('calibrate'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FittedPreview extends StatelessWidget {
  const _FittedPreview({required this.controller});
  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final preview = controller.value.previewSize;
    if (preview == null) return CameraPreview(controller);
    // The plugin reports preview size in landscape orientation, so swap
    // axes to derive the portrait aspect ratio used by the viewfinder.
    final aspect = preview.height / preview.width;
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: 100,
        height: 100 / aspect,
        child: CameraPreview(controller),
      ),
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.indigo.withValues(alpha: 0.65),
                border: Border.all(color: AppColors.violetaOscuro),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.violetaClaro, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
                fontSize: 11,
                letterSpacing: -0.11,
                color: AppColors.hintText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            color: AppColors.hintText,
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text(
            'Camera unavailable',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: AppColors.violetaClaro,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: AppColors.hintText,
            ),
          ),
        ],
      ),
    );
  }
}
