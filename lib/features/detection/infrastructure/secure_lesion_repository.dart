import 'dart:async';
import 'dart:convert';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/ar_geometry.dart';
import '../domain/class_label.dart';
import '../domain/inference_result.dart';
import '../domain/lesion_analysis.dart';
import '../domain/ports.dart';
import '../domain/scan_remote.dart';

/// Encrypted local persistence of [LesionAnalysis]. Uses SQLite for indexed
/// queries and AES-256-CBC for the sensitive payload column + image blob.
///
/// Schema v2 adds encrypted image storage for future cloud upload:
///   • `image_blob` — AES-256-CBC encrypted JPEG bytes (binary BLOB)
///   • `image_iv`   — IV for image blob decryption
///   • `image_hash` — SHA-256 hex of plaintext JPEG (queryable w/o decrypt)
///   • `pending_upload` — 1 = needs sync, 0 = uploaded (future feature)
///
/// The 256-bit key lives in the platform keystore (Keychain on iOS,
/// EncryptedSharedPreferences on Android) via `flutter_secure_storage`.
class SecureLesionRepository implements LesionRepositoryPort {
  SecureLesionRepository({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;
  Database? _db;
  enc.Encrypter? _encrypter;

  static const _keyAlias = 'skeen.detection.lesion_key_v1';
  static const _dbName = 'skeen_detection.db';
  static const _table = 'lesion_analysis';

  /// H02 (QA cycle 1): emits after every write that changes what the
  /// History / body-map projections should show (save, delete, pending
  /// deletion, upload flag, region edit, purge). The app root listens and
  /// invalidates those projections, so a screen never depends on the
  /// caller remembering to refresh it. `upsertCloudSnapshot` deliberately
  /// does NOT emit: it runs inside the History fetch itself and would
  /// otherwise trigger an endless refresh loop.
  final StreamController<void> _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  void _notifyChanged() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> initialize() async {
    if (_db != null) return;
    await _ensureKey();

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);

    _db = await openDatabase(
      path,
      version: 4,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_table (
            id                TEXT PRIMARY KEY,
            patient_id        TEXT NOT NULL,
            top_label         TEXT NOT NULL,
            confidence        REAL NOT NULL,
            captured_at       INTEGER NOT NULL,
            payload_iv        TEXT NOT NULL,
            payload_cipher    TEXT NOT NULL,
            image_blob        BLOB,
            image_iv          TEXT,
            image_hash        TEXT,
            pending_upload    INTEGER NOT NULL DEFAULT 0,
            pending_deletion  INTEGER NOT NULL DEFAULT 0,
            local_only        INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_lesion_patient ON $_table(patient_id, captured_at DESC)',
        );
        await db.execute(
          'CREATE INDEX idx_lesion_pending ON $_table(pending_upload) WHERE pending_upload = 1',
        );
        await db.execute(
          'CREATE INDEX idx_lesion_pending_del ON $_table(pending_deletion) WHERE pending_deletion = 1',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN image_blob BLOB',
          );
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN image_iv TEXT',
          );
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN image_hash TEXT',
          );
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN pending_upload INTEGER NOT NULL DEFAULT 0',
          );
          if (kDebugMode) debugPrint('SQLite migrated to v2 (image blob cols)');
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN pending_deletion INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_lesion_pending_del ON $_table(pending_deletion) WHERE pending_deletion = 1',
          );
          if (kDebugMode) debugPrint('SQLite migrated to v3 (pending_deletion)');
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN local_only INTEGER NOT NULL DEFAULT 0',
          );
          if (kDebugMode) debugPrint('SQLite migrated to v4 (local_only)');
        }
      },
    );
  }

  Future<void> _ensureKey() async {
    final stored = await _secureStorage.read(key: _keyAlias);
    final keyBytes = stored != null
        ? enc.Key.fromBase64(stored)
        : enc.Key.fromSecureRandom(32); // AES-256 = 32 bytes
    if (stored == null) {
      await _secureStorage.write(
        key: _keyAlias,
        value: keyBytes.base64,
      );
    }
    _encrypter = enc.Encrypter(enc.AES(keyBytes, mode: enc.AESMode.cbc));
  }

  @override
  Future<void> save(LesionAnalysis analysis, {Uint8List? jpegBytes}) async {
    final db = _requireDb();
    final iv = enc.IV.fromSecureRandom(16);
    final json = jsonEncode(analysis.toEncryptedJson());
    final encrypted = _encrypter!.encrypt(json, iv: iv);

    final row = <String, Object?>{
      'id': analysis.id,
      'patient_id': analysis.patientId,
      'top_label': analysis.topLabel.slug,
      'confidence': analysis.confidence,
      'captured_at': analysis.capturedAt.millisecondsSinceEpoch,
      'payload_iv': iv.base64,
      'payload_cipher': encrypted.base64,
      'pending_upload': analysis.pendingUpload ? 1 : 0,
      'local_only': analysis.localOnly ? 1 : 0,
    };

    // Encrypt image bytes separately (binary blob, not base64 in JSON).
    if (jpegBytes != null && jpegBytes.isNotEmpty) {
      final imageIv = enc.IV.fromSecureRandom(16);
      final encryptedImage = _encrypter!.encryptBytes(jpegBytes, iv: imageIv);
      row['image_blob'] = encryptedImage.bytes;
      row['image_iv'] = imageIv.base64;
      row['image_hash'] = analysis.imageHash;
    }

    await db.insert(
      _table,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notifyChanged();
  }

  @override
  Future<List<LesionAnalysis>> findByPatient(String patientId) async {
    final db = _requireDb();
    final rows = await db.query(
      _table,
      where: 'patient_id = ? AND pending_deletion = 0',
      whereArgs: [patientId],
      orderBy: 'captured_at DESC',
    );
    return rows.map((r) => _rowToAnalysis(r, includeImage: false)).toList();
  }

  @override
  Future<LesionAnalysis?> findById(String id,
      {bool includeImage = false}) async {
    final db = _requireDb();
    final rows = await db.query(_table, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _rowToAnalysis(rows.first, includeImage: includeImage);
  }

  @override
  Future<void> delete(String id) async {
    final db = _requireDb();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
    _notifyChanged();
  }

  @override
  Future<List<LesionAnalysis>> findPendingUpload(String patientId) async {
    final db = _requireDb();
    final rows = await db.query(
      _table,
      // local_only = 1 means the user opted out of cloud sync, so the row
      // must never enter the upload queue regardless of pending_upload.
      where: 'patient_id = ? AND pending_upload = 1 '
          'AND pending_deletion = 0 AND local_only = 0',
      whereArgs: [patientId],
      orderBy: 'captured_at ASC',
    );
    return rows.map((r) => _rowToAnalysis(r, includeImage: false)).toList();
  }

  @override
  Future<void> clearAll() async {
    if (_db == null) {
      // Nothing to clear if the DB was never opened in this session —
      // initialize so the file is created (and effectively empty) on disk
      // for any subsequent reads.
      await initialize();
    }
    final db = _requireDb();
    await db.delete(_table);
    _notifyChanged();
  }

  @override
  Future<void> upsertCloudSnapshot(ScanRemote remote) async {
    final db = _requireDb();
    // Cheap existence probe — avoids both the synth work and stomping on
    // a richer local copy. The detail view will still work because
    // ``findById`` reads whichever row is already there.
    final existing = await db.query(
      _table,
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [remote.id],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    // The cloud only stores top-label + confidence, so we fabricate a
    // 5-element score vector where the top class carries the entire
    // confidence mass. argmax still resolves to the right ClassLabel, so
    // the synthesized [InferenceResult] reproduces the same warning
    // bucket the backend assigned at capture time.
    ClassLabel topLabel;
    try {
      topLabel = ClassLabel.fromSlug(remote.topLabel);
    } catch (_) {
      // Cloud sent a label our enum doesn't know about (older record /
      // model drift) — fall back to nevus so the row at least renders
      // instead of crashing the detail screen.
      topLabel = ClassLabel.nevus;
    }
    final scores = List<double>.generate(
      ClassLabel.values.length,
      (i) => i == topLabel.index ? remote.confidence : 0.0,
    );

    final analysis = LesionAnalysis(
      id: remote.id,
      patientId: remote.userId,
      result: InferenceResult(scores: scores),
      anchor: null,
      // Bounding box drives the live AR overlay, not the detail card,
      // so placeholder geometry is fine for rehydrated cloud rows.
      boundingBox: const BoundingBox(
        left: 0,
        top: 0,
        width: 1,
        height: 1,
        frameWidth: 1,
        frameHeight: 1,
      ),
      capturedAt: remote.capturedAt,
      bodyRegion: remote.bodyPartLabel ?? remote.bodyRegion,
      distanceCm: remote.distanceCm,
      imageBytes: null,
      // Already in cloud — nothing to upload, nothing to mark local-only.
      pendingUpload: false,
      localOnly: false,
      imageHash: remote.imageHash,
    );

    await save(analysis); // no jpegBytes — image stays in the cloud
  }

  @override
  Future<void> markPendingDeletion(String id) async {
    final db = _requireDb();
    await db.update(
      _table,
      {'pending_deletion': 1, 'pending_upload': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    _notifyChanged();
  }

  @override
  Future<List<String>> findPendingDeletionIds() async {
    final db = _requireDb();
    final rows = await db.query(
      _table,
      columns: ['id'],
      where: 'pending_deletion = 1',
    );
    return rows.map((r) => r['id'] as String).toList(growable: false);
  }

  @override
  Future<void> markUploaded(String id) async {
    final db = _requireDb();
    await db.update(
      _table,
      {'pending_upload': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    _notifyChanged();
  }

  @override
  Future<void> updateBodyRegion(String id, String? bodyRegion) async {
    final db = _requireDb();
    final rows = await db.query(_table, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final row = rows.first;

    // Decrypt the encrypted blob, mutate the body-region key, re-encrypt
    // with a fresh IV. We can't just patch a column because bodyRegion
    // lives inside the AES-256 payload alongside the rest of the
    // metadata.
    final iv = enc.IV.fromBase64(row['payload_iv'] as String);
    final cipher = enc.Encrypted.fromBase64(row['payload_cipher'] as String);
    final json = _encrypter!.decrypt(cipher, iv: iv);
    final payload = jsonDecode(json) as Map<String, dynamic>;
    payload['bodyRegion'] = bodyRegion;
    final newIv = enc.IV.fromSecureRandom(16);
    final reencrypted = _encrypter!.encrypt(jsonEncode(payload), iv: newIv);

    await db.update(
      _table,
      {
        'payload_iv': newIv.base64,
        'payload_cipher': reencrypted.base64,
        // Re-flip pending_upload so the orchestrator re-syncs the doc
        // with the freshly-picked region. The backend uses ``set(merge)``
        // so the existing record is patched, not replaced.
        'pending_upload': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _notifyChanged();
  }

  LesionAnalysis _rowToAnalysis(Map<String, Object?> row,
      {required bool includeImage}) {
    final iv = enc.IV.fromBase64(row['payload_iv'] as String);
    final cipher = enc.Encrypted.fromBase64(row['payload_cipher'] as String);
    final json = _encrypter!.decrypt(cipher, iv: iv);

    Uint8List? imageBytes;
    if (includeImage) {
      final imageBlob = row['image_blob'];
      final imageIvStr = row['image_iv'] as String?;
      if (imageBlob != null && imageIvStr != null) {
        try {
          final imgIv = enc.IV.fromBase64(imageIvStr);
          final encImg = enc.Encrypted(imageBlob as Uint8List);
          imageBytes = Uint8List.fromList(
            _encrypter!.decryptBytes(encImg, iv: imgIv),
          );
        } catch (e) {
          if (kDebugMode) debugPrint('Image decrypt failed: $e');
        }
      }
    }

    return LesionAnalysis.fromRow(
      id: row['id'] as String,
      patientId: row['patient_id'] as String,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
        row['captured_at'] as int,
      ),
      decrypted: jsonDecode(json) as Map<String, dynamic>,
      pendingUpload: (row['pending_upload'] as int?) == 1,
      localOnly: (row['local_only'] as int?) == 1,
      imageBytes: imageBytes,
    );
  }

  Database _requireDb() {
    final db = _db;
    if (db == null) {
      throw StateError('SecureLesionRepository.initialize() must run first');
    }
    return db;
  }
}
