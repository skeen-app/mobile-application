import 'dart:async';
import 'dart:convert';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/lesion_analysis.dart';
import '../domain/ports.dart';

/// Encrypted local persistence of [LesionAnalysis]. Uses SQLite for indexed
/// queries and AES-256-CBC for the sensitive payload column.
///
/// Why hybrid (plaintext index columns + encrypted blob) instead of full
/// SQLCipher: the project depends on `sqflite`, which has no built-in
/// SQLCipher binding on all platforms. Encrypting only the payload column
/// gives us the AES-256 confidentiality the spec asked for while keeping
/// the dependency surface small and queryable. The 256-bit key lives in
/// the platform keystore (Keychain on iOS, EncryptedSharedPreferences on
/// Android) via `flutter_secure_storage`.
///
/// Migration path: when SQLCipher integration is approved, the column
/// schema stays the same — only the encryption layer flips off.
class SecureLesionRepository implements LesionRepositoryPort {
  SecureLesionRepository({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;
  Database? _db;
  enc.Encrypter? _encrypter;

  static const _keyAlias = 'skeen.detection.lesion_key_v1';
  static const _dbName = 'skeen_detection.db';
  static const _table = 'lesion_analysis';

  @override
  Future<void> initialize() async {
    if (_db != null) return;
    await _ensureKey();

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_table (
            id              TEXT PRIMARY KEY,
            patient_id      TEXT NOT NULL,
            top_label       TEXT NOT NULL,
            confidence      REAL NOT NULL,
            captured_at     INTEGER NOT NULL,
            payload_iv      TEXT NOT NULL,
            payload_cipher  TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_lesion_patient ON $_table(patient_id, captured_at DESC)',
        );
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
  Future<void> save(LesionAnalysis analysis) async {
    final db = _requireDb();
    final iv = enc.IV.fromSecureRandom(16);
    final json = jsonEncode(analysis.toEncryptedJson());
    final encrypted = _encrypter!.encrypt(json, iv: iv);

    await db.insert(
      _table,
      {
        'id': analysis.id,
        'patient_id': analysis.patientId,
        'top_label': analysis.topLabel.slug,
        'confidence': analysis.confidence,
        'captured_at': analysis.capturedAt.millisecondsSinceEpoch,
        'payload_iv': iv.base64,
        'payload_cipher': encrypted.base64,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<LesionAnalysis>> findByPatient(String patientId) async {
    final db = _requireDb();
    final rows = await db.query(
      _table,
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'captured_at DESC',
    );
    return rows.map(_rowToAnalysis).toList();
  }

  @override
  Future<LesionAnalysis?> findById(String id) async {
    final db = _requireDb();
    final rows = await db.query(_table, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _rowToAnalysis(rows.first);
  }

  @override
  Future<void> delete(String id) async {
    final db = _requireDb();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  LesionAnalysis _rowToAnalysis(Map<String, Object?> row) {
    final iv = enc.IV.fromBase64(row['payload_iv'] as String);
    final cipher = enc.Encrypted.fromBase64(row['payload_cipher'] as String);
    final json = _encrypter!.decrypt(cipher, iv: iv);
    return LesionAnalysis.fromRow(
      id: row['id'] as String,
      patientId: row['patient_id'] as String,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
        row['captured_at'] as int,
      ),
      decrypted: jsonDecode(json) as Map<String, dynamic>,
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
