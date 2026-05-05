import 'package:uuid/uuid.dart';

import '../domain/ar_geometry.dart';
import '../domain/inference_result.dart';
import '../domain/lesion_analysis.dart';

/// Anti-corruption layer between the raw model output and the persistable
/// `LesionAnalysis` aggregate. Lives in `application/` because it composes
/// domain types from sources that span the Detection context (inference
/// result + AR anchor) and the Patient context (patientId).
class DetectionResultMapper {
  DetectionResultMapper({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  LesionAnalysis toAnalysis({
    required InferenceResult result,
    required BoundingBox boundingBox,
    required String patientId,
    WorldAnchor? anchor,
    String? bodyRegion,
    double? distanceCm,
    DateTime? capturedAt,
  }) {
    return LesionAnalysis(
      id: _uuid.v4(),
      patientId: patientId,
      result: result,
      anchor: anchor,
      boundingBox: boundingBox,
      capturedAt: capturedAt ?? DateTime.now(),
      bodyRegion: bodyRegion,
      distanceCm: distanceCm,
    );
  }
}
