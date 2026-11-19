import 'package:skeen/core/localization/locale_controller.dart';
import 'body_region.dart';
import 'risk_level.dart';
import 'scan_history_entry.dart';

/// Time windows offered by the filter sheet. `all` disables the date filter.
enum ScanHistoryDateRange {
  all,
  last7Days,
  last30Days,
  last6Months;

  String get label {
    switch (this) {
      case ScanHistoryDateRange.all:
        return 'All time'.tr;
      case ScanHistoryDateRange.last7Days:
        return 'Last 7 days'.tr;
      case ScanHistoryDateRange.last30Days:
        return 'Last 30 days'.tr;
      case ScanHistoryDateRange.last6Months:
        return 'Last 6 months'.tr;
    }
  }

  /// Inclusive lower bound for the filter, or `null` when the range covers
  /// "all time".
  DateTime? earliest(DateTime now) {
    switch (this) {
      case ScanHistoryDateRange.all:
        return null;
      case ScanHistoryDateRange.last7Days:
        return now.subtract(const Duration(days: 7));
      case ScanHistoryDateRange.last30Days:
        return now.subtract(const Duration(days: 30));
      case ScanHistoryDateRange.last6Months:
        return DateTime(now.year, now.month - 6, now.day);
    }
  }
}

/// Composable filter applied on top of the search query in the history
/// screen. Empty sets mean "no constraint on this axis".
class ScanHistoryFilter {
  const ScanHistoryFilter({
    this.dateRange = ScanHistoryDateRange.all,
    this.regionGroups = const <BodyRegionGroup>{},
    this.riskLevels = const <RiskLevel>{},
  });

  final ScanHistoryDateRange dateRange;
  final Set<BodyRegionGroup> regionGroups;
  final Set<RiskLevel> riskLevels;

  static const ScanHistoryFilter empty = ScanHistoryFilter();

  bool get isEmpty =>
      dateRange == ScanHistoryDateRange.all &&
      regionGroups.isEmpty &&
      riskLevels.isEmpty;

  /// Number of axes constrained — drives the small "•N" badge on the
  /// filter button when any filter is active.
  int get activeCount {
    var n = 0;
    if (dateRange != ScanHistoryDateRange.all) n++;
    if (regionGroups.isNotEmpty) n++;
    if (riskLevels.isNotEmpty) n++;
    return n;
  }

  bool matches(ScanHistoryEntry entry, DateTime now) {
    final earliest = dateRange.earliest(now);
    if (earliest != null && entry.scannedAt.isBefore(earliest)) return false;
    if (regionGroups.isNotEmpty &&
        !regionGroups.contains(entry.region.group)) {
      return false;
    }
    if (riskLevels.isNotEmpty && !riskLevels.contains(entry.riskLevel)) {
      return false;
    }
    return true;
  }

  ScanHistoryFilter copyWith({
    ScanHistoryDateRange? dateRange,
    Set<BodyRegionGroup>? regionGroups,
    Set<RiskLevel>? riskLevels,
  }) {
    return ScanHistoryFilter(
      dateRange: dateRange ?? this.dateRange,
      regionGroups: regionGroups ?? this.regionGroups,
      riskLevels: riskLevels ?? this.riskLevels,
    );
  }
}
