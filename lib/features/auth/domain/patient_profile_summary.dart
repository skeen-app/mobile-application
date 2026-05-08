/// Aggregates the dashboard counters surfaced on the profile screen
/// (registered moles + next checkup date).
class PatientProfileSummary {
  const PatientProfileSummary({
    required this.registeredMoles,
    required this.lastScanAt,
    this.earliestReminderAt,
  });

  /// Total number of lesions registered against the current user.
  final int registeredMoles;

  /// Most recent scan timestamp, or `null` when the user has not scanned yet.
  final DateTime? lastScanAt;

  /// Earliest *future* reminder for this user. Wins over the heuristic
  /// fallback below when present.
  final DateTime? earliestReminderAt;

  /// Resolves the next-checkup date with three layered rules:
  ///   1. The earliest scheduled reminder (user explicit intent wins).
  ///   2. Otherwise: 1 month after the last scan (same heuristic as
  ///      before).
  ///   3. Otherwise: ``null`` so the UI keeps "No scans yet".
  DateTime? get nextCheckupAt {
    if (earliestReminderAt != null) return earliestReminderAt;
    final last = lastScanAt;
    if (last == null) return null;
    return DateTime(last.year, last.month + 1, last.day);
  }

  /// True when [nextCheckupAt] came from a user-scheduled reminder rather
  /// than from the "+1 month" heuristic. Lets the UI distinguish the two
  /// cases visually if it wants.
  bool get hasExplicitReminder => earliestReminderAt != null;
}
