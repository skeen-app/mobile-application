import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/capture_telemetry.dart';
import '../domain/ports.dart';

/// Append-only JSON Lines sidecar for capture telemetry.
///
/// Deliberately separate from `SecureLesionRepository`:
///
///  • It must be able to record captures that never produced a scan — a
///    frame the skin gate rejected, or a capture that failed. Those rows are
///    study data (a guidance arm that yields fewer rejections is a result),
///    but they have no `LesionAnalysis` to hang off.
///  • Study instrumentation and the clinical record have different retention
///    and consent, so mixing them into one table would make it impossible to
///    delete one without the other.
///
/// JSON Lines because it is append-only, survives a partial write (a torn
/// last line costs one row, not the file), and drops straight into pandas or
/// R at analysis time.
class FileCaptureTelemetryRepository implements CaptureTelemetryPort {
  FileCaptureTelemetryRepository({this.fileName = 'capture_telemetry.jsonl'});

  final String fileName;
  File? _file;

  @override
  Future<void> initialize() async {
    if (_file != null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, fileName));
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      _file = file;
    } catch (e) {
      // Telemetry must never take the capture flow down with it: a device
      // that cannot write the sidecar still has to be able to scan.
      if (kDebugMode) debugPrint('Telemetry store unavailable: $e');
    }
  }

  @override
  Future<void> record(CaptureTelemetryRecord record) =>
      _append(record.toJson());

  @override
  Future<void> recordEligibility(DeviceEligibilityRecord record) =>
      _append(record.toJson());

  /// Both row shapes share the file and are told apart by their `kind` field,
  /// so an analyst can read the whole session from one artefact.
  Future<void> _append(Map<String, dynamic> row) async {
    await initialize();
    final file = _file;
    if (file == null) return;
    try {
      await file.writeAsString(
        '${jsonEncode(row)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Telemetry write failed: $e');
    }
  }

  @override
  Future<String> exportJsonl() async {
    await initialize();
    final file = _file;
    if (file == null) return '';
    try {
      return await file.readAsString();
    } catch (e) {
      if (kDebugMode) debugPrint('Telemetry read failed: $e');
      return '';
    }
  }

  @override
  Future<int> count() async {
    final contents = await exportJsonl();
    if (contents.isEmpty) return 0;
    return contents
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .length;
  }
}
