import 'package:skeen/core/localization/locale_controller.dart';
import 'package:flutter/material.dart';

/// One scheduled reminder. Local-only — alarms live with the device.
class Reminder {
  const Reminder({
    required this.id,
    required this.type,
    required this.scheduledAt,
    required this.repeat,
    required this.title,
    required this.createdAt,
    this.scanId,
    this.note,
    this.fired = false,
  });

  final String id;
  final ReminderType type;

  /// Scan id for [ReminderType.rescan]. Null otherwise.
  final String? scanId;

  /// When the OS notification should fire (local time).
  final DateTime scheduledAt;
  final ReminderRepeat repeat;

  /// User-facing label shown both in the OS notification and the in-app
  /// activity log. Generated from the type + body part for previous-mole
  /// reminders, or "New mole scan" / "Self-examination" for the others.
  final String title;
  final String? note;
  final DateTime createdAt;

  /// True when a one-time reminder has already fired and was reconciled.
  /// Recurring reminders never set this — they advance ``scheduledAt``
  /// instead.
  final bool fired;

  /// Stable integer id needed by ``flutter_local_notifications``. We
  /// derive it from the UUID hash so we can cancel by id without
  /// persisting a separate counter.
  int get notificationId => id.hashCode & 0x7fffffff;

  Reminder copyWith({
    DateTime? scheduledAt,
    ReminderRepeat? repeat,
    String? title,
    String? note,
    bool? fired,
    String? scanId,
    ReminderType? type,
  }) {
    return Reminder(
      id: id,
      type: type ?? this.type,
      scanId: scanId ?? this.scanId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      repeat: repeat ?? this.repeat,
      title: title ?? this.title,
      note: note ?? this.note,
      createdAt: createdAt,
      fired: fired ?? this.fired,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'scanId': scanId,
        'scheduledAt': scheduledAt.toIso8601String(),
        'repeat': repeat.name,
        'title': title,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
        'fired': fired,
      };

  factory Reminder.fromJson(Map<String, dynamic> json) {
    return Reminder(
      id: json['id'] as String,
      type: ReminderType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ReminderType.newScan,
      ),
      scanId: json['scanId'] as String?,
      scheduledAt: DateTime.parse(json['scheduledAt'] as String),
      repeat: ReminderRepeat.values.firstWhere(
        (e) => e.name == json['repeat'],
        orElse: () => ReminderRepeat.none,
      ),
      title: json['title'] as String,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      fired: json['fired'] as bool? ?? false,
    );
  }
}

enum ReminderType {
  newScan,
  rescan,
  selfExamination;

  String get displayLabel {
    switch (this) {
      case ReminderType.newScan:
        return 'Scan a new mole'.tr;
      case ReminderType.rescan:
        return 'Re-scan a previous mole'.tr;
      case ReminderType.selfExamination:
        return 'Self-examination'.tr;
    }
  }

  IconData get icon {
    switch (this) {
      case ReminderType.newScan:
        return Icons.add_a_photo_outlined;
      case ReminderType.rescan:
        return Icons.refresh_outlined;
      case ReminderType.selfExamination:
        return Icons.self_improvement_outlined;
    }
  }

  String get description {
    switch (this) {
      case ReminderType.newScan:
        return 'Capture a new lesion you want to track.'.tr;
      case ReminderType.rescan:
        return 'Re-capture an existing lesion to compare changes.'.tr;
      case ReminderType.selfExamination:
        return 'A nudge to visually check your skin from head to toe.'.tr;
    }
  }
}

enum ReminderRepeat {
  none,
  monthly,
  quarterly;

  String get displayLabel {
    switch (this) {
      case ReminderRepeat.none:
        return 'One-time'.tr;
      case ReminderRepeat.monthly:
        return 'Every month'.tr;
      case ReminderRepeat.quarterly:
        return 'Every 3 months'.tr;
    }
  }
}
