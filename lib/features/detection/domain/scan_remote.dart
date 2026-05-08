/// Wire DTO for `/api/v1/scans/*` responses. Lives in `domain/` because the
/// patient + detection contexts both need to read it (scan list, stats,
/// detail screen). The HTTP repository maps this into the local domain
/// types (`ScanHistoryEntry`, `LesionSummary`, etc.).
class ScanRemote {
  const ScanRemote({
    required this.id,
    required this.userId,
    required this.topLabel,
    required this.confidence,
    required this.riskLevel,
    required this.capturedAt,
    required this.imageUploaded,
    required this.createdAt,
    required this.updatedAt,
    this.bodyRegion,
    this.bodyPartLabel,
    this.distanceCm,
    this.imageHash,
    this.imageObjectPath,
    this.imageDownloadUrl,
    this.relativePositionX,
    this.relativePositionY,
  });

  final String id;
  final String userId;
  final String topLabel;
  final double confidence;
  final String riskLevel;
  final String? bodyRegion;
  final String? bodyPartLabel;
  final DateTime capturedAt;
  final double? distanceCm;
  final String? imageHash;
  final String? imageObjectPath;
  final bool imageUploaded;
  final String? imageDownloadUrl;
  final double? relativePositionX;
  final double? relativePositionY;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ScanRemote.fromJson(Map<String, dynamic> json) {
    DateTime parse(String key) => DateTime.parse(json[key] as String);
    double? num2d(Object? v) => v == null ? null : (v as num).toDouble();
    return ScanRemote(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      topLabel: json['top_label'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      riskLevel: json['risk_level'] as String,
      bodyRegion: json['body_region'] as String?,
      bodyPartLabel: json['body_part_label'] as String?,
      capturedAt: parse('captured_at'),
      distanceCm: num2d(json['distance_cm']),
      imageHash: json['image_hash'] as String?,
      imageObjectPath: json['image_object_path'] as String?,
      imageUploaded: json['image_uploaded'] as bool? ?? false,
      imageDownloadUrl: json['image_download_url'] as String?,
      relativePositionX: num2d(json['relative_position_x']),
      relativePositionY: num2d(json['relative_position_y']),
      createdAt: parse('created_at'),
      updatedAt: parse('updated_at'),
    );
  }
}
