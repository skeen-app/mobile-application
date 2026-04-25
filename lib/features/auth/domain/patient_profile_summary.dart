/// Aggregates the dashboard counters surfaced on the profile screen
/// (registered moles + next checkup date).
///
/// Owned by the Auth/Profile context — even though the underlying scan data
/// belongs to the Patient context, it crosses into Auth for the user-facing
/// dashboard. The fields are sourced from a single backend GET in the long
/// run; for now the repository derives them from local data.
class PatientProfileSummary {
  const PatientProfileSummary({
    required this.registeredMoles,
    required this.lastScanAt,
  });

  /// Total number of lesions registered against the current user.
  final int registeredMoles;

  /// Most recent scan timestamp, or `null` when the user has not scanned yet.
  final DateTime? lastScanAt;

  /// Heuristic next-checkup date: 1 month after the last scan. `null` when
  /// no scan exists yet.
  DateTime? get nextCheckupAt {
    final last = lastScanAt;
    if (last == null) return null;
    return DateTime(last.year, last.month + 1, last.day);
  }
}
