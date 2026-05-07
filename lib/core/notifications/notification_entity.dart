import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// One row of activity recorded for the signed-in user. Local-only —
/// persisted via SharedPreferences with a 20-item FIFO cap.
///
/// `type` drives the icon/colour and the navigation target. `payload`
/// carries the few extra IDs we need for routing (e.g., the scan id) so
/// the row stays self-contained and the list screen doesn't have to
/// pattern-match on titles.
@immutable
class NotificationEntity {
  const NotificationEntity({
    required this.id,
    required this.type,
    required this.title,
    required this.createdAt,
    this.subtitle,
    this.isRead = false,
    this.payload = const {},
  });

  final String id;
  final NotificationType type;
  final String title;
  final String? subtitle;
  final DateTime createdAt;
  final bool isRead;
  final Map<String, dynamic> payload;

  NotificationCategory get category => type.category;

  NotificationEntity markRead() => copyWith(isRead: true);

  NotificationEntity copyWith({
    String? id,
    NotificationType? type,
    String? title,
    String? subtitle,
    DateTime? createdAt,
    bool? isRead,
    Map<String, dynamic>? payload,
  }) {
    return NotificationEntity(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      payload: payload ?? this.payload,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'subtitle': subtitle,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'isRead': isRead,
        'payload': payload,
      };

  factory NotificationEntity.fromJson(Map<String, dynamic> json) {
    return NotificationEntity(
      id: json['id'] as String,
      type: NotificationType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => NotificationType.scanSyncedToCloud,
      ),
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isRead: json['isRead'] as bool? ?? false,
      payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

/// Visual + behaviour bucket. Drives icon, accent colour, default
/// navigation target and ordering hints (risk-alerts pin to the top of
/// the list when freshly arrived).
enum NotificationType {
  passwordChanged,
  scanCompleted,
  predictionReady,
  highRiskDetected,
  profileEdited,
  avatarUpdated,
  scanSyncedToCloud,
  modelUpdateInstalled,
  reminderCheckup;

  NotificationCategory get category {
    switch (this) {
      case NotificationType.passwordChanged:
      case NotificationType.profileEdited:
      case NotificationType.avatarUpdated:
        return NotificationCategory.account;
      case NotificationType.scanCompleted:
      case NotificationType.predictionReady:
        return NotificationCategory.scan;
      case NotificationType.highRiskDetected:
        return NotificationCategory.riskAlert;
      case NotificationType.scanSyncedToCloud:
      case NotificationType.modelUpdateInstalled:
        return NotificationCategory.system;
      case NotificationType.reminderCheckup:
        return NotificationCategory.reminder;
    }
  }
}

enum NotificationCategory {
  account,
  scan,
  riskAlert,
  system,
  reminder;

  IconData get icon {
    switch (this) {
      case NotificationCategory.account:
        return Icons.shield_outlined;
      case NotificationCategory.scan:
        return Icons.medical_information_outlined;
      case NotificationCategory.riskAlert:
        return Icons.warning_amber_rounded;
      case NotificationCategory.system:
        return Icons.cloud_done_outlined;
      case NotificationCategory.reminder:
        return Icons.event_outlined;
    }
  }

  Color get accent {
    switch (this) {
      case NotificationCategory.account:
        return AppColors.violeta;
      case NotificationCategory.scan:
        return AppColors.turquesa;
      case NotificationCategory.riskAlert:
        return AppColors.fucsia;
      case NotificationCategory.system:
        return AppColors.naranja;
      case NotificationCategory.reminder:
        return AppColors.violetaClaro;
    }
  }

  String get label {
    switch (this) {
      case NotificationCategory.account:
        return 'Account';
      case NotificationCategory.scan:
        return 'Scan';
      case NotificationCategory.riskAlert:
        return 'Risk alert';
      case NotificationCategory.system:
        return 'System';
      case NotificationCategory.reminder:
        return 'Reminder';
    }
  }
}
