import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/ports.dart';
import '../infrastructure/ar_session_service.dart';
import '../infrastructure/secure_lesion_repository.dart';
import '../infrastructure/tflite_inference_service.dart';
import 'coordinate_translator.dart';
import 'detection_result_mapper.dart';

/// DI roots for the Detection bounded context. Kept in `application/` so
/// presentation only ever talks to the domain ports — never directly to
/// `infrastructure/` types.

final inferenceServiceProvider = Provider<InferenceServicePort>((ref) {
  final svc = TfliteInferenceService();
  ref.onDispose(svc.dispose);
  return svc;
});

final arSessionProvider = Provider<ArSessionPort>((ref) {
  final svc = ArSessionService();
  ref.onDispose(svc.dispose);
  return svc;
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
