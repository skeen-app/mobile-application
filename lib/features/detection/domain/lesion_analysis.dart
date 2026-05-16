import 'package:flutter/foundation.dart';

import 'ar_geometry.dart';
import 'class_label.dart';
import 'inference_result.dart';

/// Aggregate root persisted by `LesionRepositoryPort`. Combines the AI
/// output, the AR anchor that produced it, the rough on-screen bounding box,
/// and the patient context — everything needed to re-render the floating
/// label later or list it in history.
///
/// Stored encrypted on disk (AES-256). Index fields ([id], [capturedAt],
/// [patientId], [topLabelSlug]) stay in plaintext on the row so we can query
/// without decrypting; [encryptedPayload] holds the rest.
@immutable
class LesionAnalysis {
  const LesionAnalysis({
    required this.id,
    required this.patientId,
    required this.result,
    required this.anchor,
    required this.boundingBox,
    required this.capturedAt,
    this.bodyRegion,
    this.distanceCm,
    this.imageBytes,
    this.pendingUpload = false,
    this.localOnly = false,
    this.imageHash,
  });

  final String id;
  final String patientId;
  final InferenceResult result;
  final WorldAnchor? anchor;
  final BoundingBox boundingBox;
  final DateTime capturedAt;

  /// Optional body region tag (Head / Chest / Legs / …). Selected by the
  /// user in the post-capture body-region picker.
  final String? bodyRegion;

  /// The raw JPEG bytes of the captured image. Stored AES-256-CBC encrypted
  /// in SQLite for future cloud upload / re-training. Null when loaded
  /// without image data (e.g. history list view that only needs metadata).
  final Uint8List? imageBytes;

  /// Whether this record is pending upload to the cloud. Defaults to false;
  /// set to true only when the user opts-in for data sharing.
  final bool pendingUpload;

  /// True when the user captured this scan with cloud-sync disabled. The
  /// row stays on-device forever (or until logout purges it) and the UI
  /// surfaces it with a "Not synced" badge so the user understands the
  /// difference from rows queued behind a network outage.
  final bool localOnly;

  /// SHA-256 hex digest of the raw JPEG for dedup + integrity verification.
  final String? imageHash;

  /// Capture distance at the moment of the shot (cm). Useful both as
  /// quality metadata and for future scale-aware features.
  final double? distanceCm;

  ClassLabel get topLabel => result.topLabel;
  double get confidence => result.confidence;

  /// JSON shape that the encrypted blob carries. Plaintext columns
  /// ([id], [capturedAt], [patientId], topLabelSlug) are written separately
  /// by the repository so they can be indexed without decryption.
  Map<String, dynamic> toEncryptedJson() => {
        'inference': result.toJson(),
        'anchor': anchor?.toJson(),
        'bbox': {
          'l': boundingBox.left,
          't': boundingBox.top,
          'w': boundingBox.width,
          'h': boundingBox.height,
          'fw': boundingBox.frameWidth,
          'fh': boundingBox.frameHeight,
        },
        'bodyRegion': bodyRegion,
        'distanceCm': distanceCm,
        'imageHash': imageHash,
      };

  static LesionAnalysis fromRow({
    required String id,
    required String patientId,
    required DateTime capturedAt,
    required Map<String, dynamic> decrypted,
    bool pendingUpload = false,
    bool localOnly = false,
    Uint8List? imageBytes,
  }) {
    final bbox = decrypted['bbox'] as Map<String, dynamic>;
    return LesionAnalysis(
      id: id,
      patientId: patientId,
      result: InferenceResult.fromJson(
        (decrypted['inference'] as Map).cast<String, dynamic>(),
      ),
      anchor: decrypted['anchor'] == null
          ? null
          : WorldAnchor.fromJson(
              (decrypted['anchor'] as Map).cast<String, dynamic>(),
            ),
      boundingBox: BoundingBox(
        left: (bbox['l'] as num).toDouble(),
        top: (bbox['t'] as num).toDouble(),
        width: (bbox['w'] as num).toDouble(),
        height: (bbox['h'] as num).toDouble(),
        frameWidth: (bbox['fw'] as num).toDouble(),
        frameHeight: (bbox['fh'] as num).toDouble(),
      ),
      capturedAt: capturedAt,
      bodyRegion: decrypted['bodyRegion'] as String?,
      distanceCm: (decrypted['distanceCm'] as num?)?.toDouble(),
      imageBytes: imageBytes,
      pendingUpload: pendingUpload,
      localOnly: localOnly,
      imageHash: decrypted['imageHash'] as String?,
    );
  }
}
