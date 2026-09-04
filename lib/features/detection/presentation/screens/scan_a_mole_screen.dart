import 'package:skeen/core/localization/locale_controller.dart';
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_top_app_bar.dart';
import '../../../../core/widgets/tutorial_controller.dart';
import '../../../patient/application/lesion_summary_providers.dart';
import '../../../patient/application/scan_history_providers.dart';
import '../../application/detection_controller.dart';
import '../../application/experiment_session.dart';
import '../../application/providers.dart';
import '../../application/readiness_evaluator.dart';
import '../../application/sync_orchestrator.dart';
import '../../domain/capture_crop_config.dart';
import '../../domain/capture_quality.dart';
import '../../domain/capture_roi.dart';
import '../../domain/capture_telemetry.dart';
import '../../domain/device_eligibility.dart';
import '../../domain/ports.dart';
import '../../infrastructure/scan_camera_service.dart';
import '../widgets/body_region_picker.dart';
import '../widgets/camera_controls.dart';
import '../widgets/capture_guide_overlay.dart';
import '../widgets/floating_diagnosis_label.dart';
import '../widgets/not_skin_detected_dialog.dart';
import '../widgets/scan_capture_button.dart';

/// Fallback scan screen for devices without AR/depth sensor support.
/// Integrates full inline TFLite inference via DetectionController — same
/// pipeline as ArScanScreen, but without AR anchor positioning.
/// The floating diagnosis label centers in the viewport instead.
class ScanAMoleScreen extends ConsumerStatefulWidget {
  const ScanAMoleScreen({super.key});

  @override
  ConsumerState<ScanAMoleScreen> createState() => _ScanAMoleScreenState();
}

class _ScanAMoleScreenState extends ConsumerState<ScanAMoleScreen>
    with WidgetsBindingObserver {
  late final ScanCameraService _camera;
  late final ReadinessEvaluator _evaluator;
  late final CaptureTelemetryPort _telemetry;
  StreamSubscription<CaptureReadiness>? _readinessSub;

  CaptureQuality _quality = CaptureQuality.initial;
  CaptureReadiness _readiness = CaptureReadiness.initializing;
  bool _showShutterFlash = false;
  String? _initError;
  bool _permissionPermanentlyDenied = false;
  Size _previewSize = Size.zero;

  /// Side of the on-screen guide square, resolved from the laid-out preview.
  /// Feeds both the overlay and the ROI so the region the user frames is
  /// exactly the region the metrics describe.
  double _guideBoxSide = kGuideBoxLogicalPx;
  CaptureRoi? _appliedRoi;

  // ── Gate + auto-capture ──────────────────────────────────────────────
  /// Dwell the gate must stay green before the shutter fires itself.
  ///
  /// This is the mechanism the study expects to produce the measurable
  /// difference: the tap itself is a motion impulse at exactly the moment
  /// the frame is being taken, and removing it removes that blur source.
  /// 600 ms is long enough to outlast the wobble from the user settling into
  /// position, short enough that a steady hand is not asked to hold an
  /// unnatural pose.
  static const int kAutoCaptureDwellMs = 600;

  Timer? _gateTicker;
  DateTime? _greenSince;
  double _autoProgress = 0;
  final Uuid _uuid = const Uuid();

  // Pinch-to-zoom state
  double _currentZoom = 1.0;
  double _maxZoom = 5.0;
  double _baseZoom = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _camera = ref.read(scanCameraServiceProvider);
    _evaluator = ref.read(readinessEvaluatorProvider);
    _telemetry = ref.read(captureTelemetryProvider);
    _telemetry.initialize();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      // Camera permission gate: the camera plugin throws when permission
      // is denied. Re-prompting here covers the new-user case where the
      // permission was declined at onboarding — the user grants now and
      // the camera lights up immediately, without needing to navigate
      // away and back.
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (!mounted) return;
        setState(() {
          _permissionPermanentlyDenied = status.isPermanentlyDenied;
          _initError = status.isPermanentlyDenied
              ? 'Camera access is blocked. Enable it from system settings to scan.'
                  .tr
              : 'Camera permission is required to scan.'.tr;
        });
        return;
      }

      await _camera.initialize();
      _maxZoom = await _camera.getMaxZoom();

      // Push the ROI before the metric stream starts so the very first
      // measurement already describes the guide box and not the whole frame.
      _syncRoi();

      // start() is awaited because it now cancels any previous subscriptions
      // first — see ReadinessEvaluator.start.
      await _evaluator.start();

      _readinessSub = _evaluator.readiness.listen((r) {
        if (!mounted) return;
        setState(() {
          _readiness = r;
          _quality = r.lighting;
        });
        ref.read(detectionControllerProvider.notifier).updateReadiness(r);
        // This surface has no AR scene-mapping ticker, so nothing used to
        // advance the controller out of [DetectionPhase.mapping]: the
        // shutter stayed inert (captureAndClassify returns on its `ready`
        // guard) and CaptureGuideOverlay never mounted. A readiness event
        // is proof the image stream is delivering frames — exactly the
        // "camera is live" signal this surface can gate on.
        _promoteToReadyWhenLive();
      });

      _startGateTicker();

      if (mounted) {
        setState(() {
          _initError = null;
          _permissionPermanentlyDenied = false;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Camera init failed: $e');
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  /// Whether the blocking guidance is actually in force right now.
  ///
  /// Fail-closed while the hardware probe is still running: an unresolved
  /// eligibility must hold the shutter, never open it, or a guided-arm
  /// participant could slip an ungated capture through during the probe
  /// window and contaminate the intervention.
  ///
  /// Resolved-ineligible turns guidance OFF rather than leaving a gate that
  /// can never open. Study participants never reach that state — they are
  /// shown the exclusion screen — so this only covers ordinary users on a
  /// device that cannot run the guidance.
  bool _guidanceInForce() {
    final session = ref.read(experimentSessionProvider);
    if (!session.isGuided) return false;
    final eligibility = ref.read(deviceEligibilityProvider).valueOrNull;
    if (eligibility == null) return true;
    return eligibility.isEligible;
  }

  /// Derives the metric ROI from the **real** preview↔frame mapping and
  /// pushes it to the camera service.
  ///
  /// Replaces the blind 0.55 constant: the preview renders `BoxFit.cover`, so
  /// the fraction of the frame the guide box covers depends on the widget's
  /// aspect and the sensor's, and only the layout knows both. Re-pushed only
  /// when it actually changes, since this runs from `build`.
  void _syncRoi() {
    final preview = _camera.previewFrameSize;
    if (preview == null || _previewSize == Size.zero) return;
    final roi = CaptureRoi.fromPreviewGeometry(
      widgetSize: _previewSize,
      frameSize: CaptureRoi.displayFrameSize(preview),
      guideBoxSide: _guideBoxSide,
    );
    if (roi == _appliedRoi) return;
    _appliedRoi = roi;
    _camera.setRoi(roi);
  }

  /// Drives the auto-shutter dwell.
  ///
  /// Runs on its own 50 ms timer rather than off the ~3 Hz readiness stream:
  /// at 333 ms granularity a 600 ms dwell would actually fire somewhere
  /// between 600 and 933 ms, which is too loose for the study's independent
  /// variable and makes the progress ring visibly steppy.
  void _startGateTicker() {
    _gateTicker?.cancel();
    _gateTicker = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _onGateTick(),
    );
  }

  void _onGateTick() {
    if (!mounted) return;
    final guided = _guidanceInForce();
    final phase = ref.read(detectionControllerProvider).phase;

    // The control arm has no gate and no auto-shutter by design — it is the
    // comparator, so it must behave like a plain camera.
    if (!guided || phase != DetectionPhase.ready || !_readiness.isReady) {
      if (_greenSince != null || _autoProgress != 0) {
        setState(() {
          _greenSince = null;
          _autoProgress = 0;
        });
      }
      return;
    }

    final since = _greenSince ??= DateTime.now();
    final heldMs = DateTime.now().difference(since).inMilliseconds;

    if (heldMs >= kAutoCaptureDwellMs) {
      _greenSince = null;
      setState(() => _autoProgress = 0);
      _fireCapture(CaptureTrigger.automatic);
      return;
    }

    final progress = (heldMs / kAutoCaptureDwellMs).clamp(0.0, 1.0);
    if ((progress - _autoProgress).abs() > 0.01) {
      setState(() => _autoProgress = progress);
    }
  }

  /// Fallback-surface equivalent of the AR screen's scene-mapping ticker.
  ///
  /// The AR path unlocks capture once ARCore reports a stable TRACKING
  /// streak; there is no tracking state here, so the equivalent proof that
  /// the surface is live is the camera controller being initialized *and*
  /// the image stream emitting (the caller only runs this from a readiness
  /// event, which the stream produces).
  ///
  /// [DetectionController.completeMapping] is a no-op unless the phase is
  /// still `mapping`, so this is safe to call on every readiness event —
  /// and that repetition is deliberate: it also re-promotes the phase after
  /// [DetectionController.restartMapping] sends the flow back to `mapping`
  /// on a skin-gate rejection.
  void _promoteToReadyWhenLive() {
    if (!_camera.isReady) return;
    ref.read(detectionControllerProvider.notifier).completeMapping();
  }

  /// Skin-gate rejection handler — mirrors `ArScanScreen._showNotSkinDialog`.
  /// Without this the fallback surface stranded the user in the terminal
  /// `notSkinRejected` phase with no way back to `ready`.
  Future<void> _showNotSkinDialog() async {
    await NotSkinDetectedDialog.show(context);
    if (!mounted) return;
    // Whatever the dismiss path (CTA or back gesture), return the flow to
    // the mapping phase so the next attempt re-runs the readiness gate.
    // restartMapping() restarts the image stream, so the readiness listener
    // fires again and [_promoteToReadyWhenLive] re-opens the shutter.
    await ref.read(detectionControllerProvider.notifier).restartMapping();
  }

  /// Empty-state retry CTA — opens system settings when the permission is
  /// permanently denied (OS won't show its dialog again), otherwise reruns
  /// the bootstrap which will re-request permission.
  Future<void> _retryBootstrap() async {
    if (_permissionPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    if (mounted) {
      setState(() {
        _initError = null;
        _permissionPermanentlyDenied = false;
      });
    }
    await _bootstrap();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _camera.controller;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // Only release the camera when it was actually live. Skipping this
      // when controller is null also avoids a NoSuchMethodError on a
      // bootstrap that never reached initialize() (permission denied).
      if (controller != null) _camera.dispose();
    } else if (state == AppLifecycleState.resumed) {
      // Always retry on resume — handles BOTH the normal background-
      // foreground cycle (reattach the camera) AND the post-permission-
      // dialog case where a previous bootstrap aborted with _initError.
      _bootstrap();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gateTicker?.cancel();
    _readinessSub?.cancel();
    // The evaluator is provider-scoped and outlives this screen, so its
    // sensor subscriptions have to be released here or the gyroscope keeps
    // streaming after the user leaves the scanner.
    _evaluator.stop();
    _camera.dispose();
    super.dispose();
  }

  /// Capture pipeline — routed entirely through DetectionController which
  /// handles AE/AF lock, capture, inference, persistence, and stream restart.
  ///
  /// Two things wrap it here, and neither touches the pipeline itself:
  /// the **gate**, which refuses a capture the readiness vector says would be
  /// bad, and the **telemetry**, which records the vector that decision was
  /// made on.
  Future<void> _fireCapture(CaptureTrigger trigger) async {
    final detection = ref.read(detectionControllerProvider);

    if (detection.phase == DetectionPhase.presented) {
      _navigateToTriage(detection);
      return;
    }
    if (detection.phase != DetectionPhase.ready) return;

    final session = ref.read(experimentSessionProvider);

    // The gate is the study's independent variable, so it has to actually
    // block — including a deliberate tap. In the control arm it does not
    // exist at all.
    if (_guidanceInForce() && !_readiness.isReady) return;

    // Snapshot BEFORE the capture: these are the conditions the shutter
    // fired under. Reading them afterwards would capture the post-capture
    // state, when the stream has been paused and restarted.
    final readinessAtShutter = _readiness;
    final metricsAtShutter = _evaluator.lastMetrics;
    final roiAtShutter = _camera.roi;
    final calibrator = _evaluator.calibrator;
    final sharpnessNormalized = calibrator.normalized;
    final sharpnessObservedMax = calibrator.observedMax;
    final sharpnessCalibrating = calibrator.isCalibrating;

    setState(() => _showShutterFlash = true);
    Future.delayed(const Duration(milliseconds: 140), () {
      if (mounted) setState(() => _showShutterFlash = false);
    });

    final controller = ref.read(detectionControllerProvider.notifier);
    await controller.captureAndClassify(
      previewSize: _previewSize,
      // The region the models get is the region the box drew and the gate
      // measured — one derivation, not three.
      roi: roiAtShutter,
    );
    if (!mounted) return;

    final after = ref.read(detectionControllerProvider);
    final outcome = switch (after.phase) {
      DetectionPhase.notSkinRejected => CaptureOutcome.rejectedNotSkin,
      DetectionPhase.failed => CaptureOutcome.failed,
      _ => after.savedAnalysisId != null
          ? CaptureOutcome.saved
          : CaptureOutcome.failed,
    };

    // Recorded for every attempt, including rejections and failures: an arm
    // that produces fewer unusable frames is itself the result being
    // measured, and those attempts never reach the lesion repository.
    await _telemetry.record(
      CaptureTelemetryRecord.fromSnapshot(
        id: _uuid.v4(),
        participantId: session.participantId,
        condition: session.condition,
        trigger: trigger,
        outcome: outcome,
        readiness: readinessAtShutter,
        metrics: metricsAtShutter,
        roi: roiAtShutter,
        sharpnessNormalized: sharpnessNormalized,
        sharpnessObservedMax: sharpnessObservedMax,
        sharpnessCalibrating: sharpnessCalibrating,
        analysisId: after.savedAnalysisId,
      ),
    );
  }

  Future<void> _navigateToTriage(DetectionState state) async {
    if (state.savedAnalysisId == null || state.capturedImageBytes == null) {
      return;
    }
    final region = await BodyRegionPicker.show(context);
    if (!mounted) return;
    if (region != null) {
      final repo = ref.read(lesionRepositoryProvider);
      await repo.updateBodyRegion(state.savedAnalysisId!, region);
      ref.invalidate(scanHistoryProvider);
      ref.invalidate(lesionSummariesProvider);
      // The capture flow already uploaded this row to the cloud BEFORE the
      // region was picked, so the picked region must be patched up. Push it
      // through uploadOne (not the debounced syncNow): uploadOne skips the
      // 5s debounce + running-lock, so the region can't be silently dropped
      // — which is what made tagged scans read back at the chest default.
      final tagged = await repo.findById(state.savedAnalysisId!);
      if (tagged != null) {
        ref.read(syncOrchestratorProvider).uploadOne(tagged);
      }
    }
    if (!mounted) return;
    ref.read(tutorialControllerProvider.notifier).advanceToReport();
    context.pushReplacementNamed(
      'triage-result',
      extra: {
        'analysisId': state.savedAnalysisId!,
        'capturedImageBytes': state.capturedImageBytes!,
        'bodyRegion': region,
      },
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final newZoom = (_baseZoom * details.scale).clamp(1.0, _maxZoom);
    if ((newZoom - _currentZoom).abs() > 0.05) {
      setState(() => _currentZoom = newZoom);
      // Dispatch through controller — handles both camera + AR session
      ref.read(detectionControllerProvider.notifier).setZoom(newZoom);
    }
  }

  /// Flash toggle — dispatches through DetectionController which sends to
  /// both the camera plugin (physical torch) and AR session (native sync).
  Future<void> _toggleFlash() async {
    final state = ref.read(detectionControllerProvider);
    await ref.read(detectionControllerProvider.notifier).setFlash(!state.flashOn);
  }

  @override
  Widget build(BuildContext context) {
    // Skin-gate rejection → educational modal, then back to mapping. Mirrors
    // the same listener in ArScanScreen so BOTH capture surfaces recover
    // from the terminal notSkinRejected phase. The listener runs once per
    // transition, not on every rebuild.
    ref.listen<DetectionState>(detectionControllerProvider, (prev, next) {
      final wasRejected = prev?.phase == DetectionPhase.notSkinRejected;
      final isRejected = next.phase == DetectionPhase.notSkinRejected;
      if (isRejected && !wasRejected) {
        _showNotSkinDialog();
      }
    });
    // Watched (not just read) so the screen rebuilds when the hardware probe
    // resolves and the gate/shutter state settles with it.
    final eligibility = ref.watch(deviceEligibilityProvider).valueOrNull;
    final session = ref.watch(experimentSessionProvider);
    final ineligible = eligibility != null && !eligibility.isEligible;

    // A study device that cannot run the guided arm is EXCLUDED, explicitly
    // and on the record — not left with a shutter that silently never opens.
    if (ineligible && session.isStudyDevice) {
      return _StudyIneligibleScreen(missing: eligibility.missing);
    }

    final detection = ref.watch(detectionControllerProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SkeenTopAppBar(
              title: 'Scan a mole'.tr,
              subtitle: 'AI analysis in seconds'.tr,
            ),
            if (ineligible) const _GuidanceUnavailableBanner(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _buildPreviewSurface(detection),
                ),
              ),
            ),
            _buildBottomControls(detection),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewSurface(DetectionState detection) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.indigo,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF291859), width: 2),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          _previewSize = Size(constraints.maxWidth, constraints.maxHeight);
          _guideBoxSide = resolveGuideBoxSide(_previewSize.shortestSide);
          _syncRoi();
          return GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_initError != null)
                  _CameraUnavailable(
                    message: _initError!,
                    onRetry: _retryBootstrap,
                    permanentlyDenied: _permissionPermanentlyDenied,
                  )
                else if (_camera.isReady)
                  _FittedPreview(controller: _camera.controller!)
                else
                  const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.violetaClaro,
                      ),
                    ),
                  ),
                // Capture guide: subtle target frame + 3 chips (light /
                // focus / distance). No-AR fallback has no depth sensor
                // so distance defaults to the sweet-spot constant — the
                // chip stays in the "ok" state, matching the readiness
                // gate above.
                // Guidance exists only in the guided arm — the control arm
                // has to look and behave like a plain camera for the
                // comparison to mean anything.
                if (detection.phase == DetectionPhase.ready && _guidanceInForce())
                  CaptureGuideOverlay(
                    readiness: _readiness,
                    boxSide: _guideBoxSide,
                    autoCaptureProgress: _autoProgress,
                  ),

                // Subtle disclaimer: AR is not available on this device.
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        border: Border.all(
                          color: AppColors.violetaOscuro.withValues(alpha: 0.6),
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 12,
                            color: AppColors.hintText,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'AR not supported on this device'.tr,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w500,
                              fontSize: 10.5,
                              letterSpacing: 0.1,
                              color: AppColors.hintText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Floating diagnosis label (centered, no AR anchor)
                if (detection.result != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 80),
                      child: FloatingDiagnosisLabel(
                        result: detection.result!,
                        onTap: () => _navigateToTriage(detection),
                      ),
                    ),
                  ),

                // (Old checklist removed — folded into CaptureGuideOverlay)

                // Flash toggle
                Positioned(
                  top: 16,
                  right: 16,
                  child: CameraFlashButton(
                    isOn: detection.flashOn,
                    onTap: _toggleFlash,
                  ),
                ),

                // Zoom indicator
                if (_currentZoom > 1.05)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.background.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_currentZoom.toStringAsFixed(1)}×',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: AppColors.violetaClaro,
                        ),
                      ),
                    ),
                  ),

                // Shutter flash
                AnimatedOpacity(
                  opacity: _showShutterFlash ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Container(color: Colors.white),
                ),

                // Analyzing / uploading overlay
                if (detection.phase == DetectionPhase.analyzing ||
                    detection.phase == DetectionPhase.standardizing ||
                    detection.phase == DetectionPhase.gating ||
                    detection.phase == DetectionPhase.uploading)
                  Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.violetaClaro,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            switch (detection.phase) {
                              DetectionPhase.standardizing =>
                                'Standardizing image…',
                              DetectionPhase.uploading =>
                                'Uploading to cloud…',
                              _ => 'Running on-device analysis…',
                            },
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: AppColors.violetaClaro,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomControls(DetectionState detection) {
    final guided = _guidanceInForce();
    final isPresented = detection.phase == DetectionPhase.presented;
    final isBusy = detection.phase == DetectionPhase.capturing ||
        detection.phase == DetectionPhase.analyzing ||
        detection.phase == DetectionPhase.standardizing ||
        // Without `gating` the shutter looked re-enabled while the
        // skin-gate ran, inviting a second tap right before the
        // rejection dialog. Matches the AR screen's busy set.
        detection.phase == DetectionPhase.gating ||
        detection.phase == DetectionPhase.uploading;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 8),
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
                isCapturing: isBusy,
                // Blocked while any check is red in the guided arm. This is
                // the intervention: the user cannot take a bad photo.
                enabled: !guided || _readiness.isReady,
                onPressed: () => _fireCapture(CaptureTrigger.manual),
              ),
              if (isPresented)
                _SecondaryAction(
                  icon: Icons.refresh,
                  label: 'Scan again',
                  onTap: () async {
                    await ref
                        .read(detectionControllerProvider.notifier)
                        .reset();
                  },
                )
              else
                const SizedBox(width: 60),
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
  const _CameraUnavailable({
    required this.message,
    this.onRetry,
    this.permanentlyDenied = false,
  });

  final String message;
  final VoidCallback? onRetry;
  // When true the retry CTA opens system settings instead of re-prompting
  // (the OS won't show its native dialog after two denials).
  final bool permanentlyDenied;

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
          Text(
            'Camera unavailable'.tr,
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
          if (onRetry != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: Icon(
                permanentlyDenied ? Icons.settings_outlined : Icons.refresh,
                size: 18,
              ),
              label: Text(
                permanentlyDenied
                    ? 'Open settings'.tr
                    : 'Grant camera access'.tr,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.violeta,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown to a **study participant** whose device cannot run the guided arm.
///
/// The point is that the exclusion is visible and attributable. Previously the
/// same device simply presented a shutter that never unlocked: the participant
/// gave up, and the study recorded nothing — an invisible, device-tier
/// correlated dropout that would have reshaped the sample.
class _StudyIneligibleScreen extends StatelessWidget {
  const _StudyIneligibleScreen({required this.missing});

  final Set<EligibilityRequirement> missing;

  String _reasonFor(EligibilityRequirement requirement) =>
      switch (requirement) {
        EligibilityRequirement.camera => 'No usable camera was found.'.tr,
        EligibilityRequirement.gyroscope =>
          'This device has no gyroscope, so camera shake cannot be measured.'
              .tr,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            SkeenTopAppBar(
              title: 'Scan a mole'.tr,
              subtitle: 'Device check'.tr,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.naranja.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.phonelink_erase_outlined,
                        size: 34,
                        color: AppColors.naranja,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'This device is not compatible with the study'.tr,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        letterSpacing: -0.18,
                        color: AppColors.violetaClaro,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final requirement in missing)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _reasonFor(requirement),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                            height: 1.5,
                            color: AppColors.hintText,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      'Please let the study coordinator know so another '
                              'device can be assigned.'
                          .tr,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        height: 1.5,
                        color: AppColors.hintText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown to an ordinary (non-study) user on a device that cannot run the
/// guidance. They keep a working camera; what they lose is the assistance, and
/// they are told so rather than left with a gate that can never open.
class _GuidanceUnavailableBanner extends StatelessWidget {
  const _GuidanceUnavailableBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.naranja.withValues(alpha: 0.12),
          border: Border.all(color: AppColors.naranja.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 15, color: AppColors.naranja),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Capture assistance is unavailable on this device.'.tr,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: 11.5,
                  color: AppColors.naranja,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
