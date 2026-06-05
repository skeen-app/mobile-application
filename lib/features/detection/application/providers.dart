import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/ports.dart';
import '../domain/triage_decision_policy.dart';
import '../infrastructure/ar_session_service.dart';
import '../infrastructure/capture_cropper.dart';
import '../infrastructure/scan_camera_service.dart';
import '../infrastructure/secure_lesion_repository.dart';
import '../infrastructure/tflite_inference_service.dart';
import '../infrastructure/tflite_skin_gate_service.dart';
import 'coordinate_translator.dart';
import 'detection_result_mapper.dart';
import 'readiness_evaluator.dart';

/// DI roots for the Detection bounded context. Kept in `application/` so
/// presentation only ever talks to the domain ports — never directly to
/// `infrastructure/` types.

final inferenceServiceProvider = Provider<InferenceServicePort>((ref) {
  final svc = TfliteInferenceService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// Cascade stage-1: lightweight skin / not-skin filter that runs before
/// the cancer classifier. Kept as its own provider so the upload-photo
/// flow can reuse the same instance without having to reach into the
/// detection controller.
final skinGateServiceProvider = Provider<SkinGateServicePort>((ref) {
  final svc = TfliteSkinGateService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// Conservative three-tier triage policy. Pure domain service; derives a
/// [DiagnosisResult] from the classifier scores without touching persistence
/// or the [WarningLevel] palette.
final triageDecisionPolicyProvider = Provider<TriageDecisionPolicy>((ref) {
  return const TriageDecisionPolicy();
});

/// Guide-box cropper (FASE 2). Flag-gated in `capture_crop_config.dart`;
/// crops the captured frame to the centered guide region before the cascade
/// so both models see a tighter, more dermatoscopic input.
final captureCropperProvider = Provider<CaptureCropperPort>((ref) {
  return const ImageCaptureCropper();
});

final arSessionProvider = Provider<ArSessionPort>((ref) {
  final svc = ArSessionService();
  ref.onDispose(svc.stop);
  return svc;
});

/// Concrete camera service — presentation layer needs the CameraController
/// getter for the preview widget, so we keep a typed provider.
final scanCameraServiceProvider = Provider<ScanCameraService>((ref) {
  final svc = ScanCameraService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// Port-typed camera provider for the application layer (DetectionController).
final scanCameraPortProvider = Provider<ScanCameraServicePort>((ref) {
  return ref.watch(scanCameraServiceProvider);
});

final coordinateTranslatorProvider = Provider<CoordinateTranslator>((ref) {
  return CoordinateTranslator(ref.watch(arSessionProvider));
});

final detectionResultMapperProvider = Provider<DetectionResultMapper>((ref) {
  return DetectionResultMapper();
});

final lesionRepositoryProvider = Provider<LesionRepositoryPort>((ref) {
  final repo = SecureLesionRepository();
  // Initialization is async; callers should `await ref.read(...).initialize()`
  // once before first use (the AR scan screen does this on mount).
  return repo;
});

/// One-shot capability probe shared between the scan router screen and any
/// debug surface that wants to know what the device supports.
final arCapabilitiesProvider = FutureProvider<ArCapabilities>((ref) async {
  final session = ref.watch(arSessionProvider);
  return session.probeCapabilities();
});

/// Readiness evaluator that combines camera + AR streams.
/// NOT auto-dispose — the screen manages start/stop lifecycle manually,
/// and ref.read() in initState would trigger premature disposal with
/// auto-dispose (since nothing ref.watch()es this provider in build).
final readinessEvaluatorProvider = Provider<ReadinessEvaluator>((ref) {
  final camera = ref.watch(scanCameraServiceProvider);
  final evaluator = ReadinessEvaluator(camera: camera);
  ref.onDispose(evaluator.dispose);
  return evaluator;
});
