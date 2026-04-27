import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/scan_history_entry.dart';
import '../domain/scan_history_filter.dart';
import '../infrastructure/repositories/scan_history_repository.dart';

/// Repository binding — swap to an HTTP implementation when the
/// `GET /me/scan-history` endpoint ships.
final scanHistoryRepositoryProvider = Provider<ScanHistoryRepository>((ref) {
  return const MockScanHistoryRepository();
});

/// Raw, unfiltered list of scans for the authenticated user.
final scanHistoryProvider =
    FutureProvider<List<ScanHistoryEntry>>((ref) async {
  return ref.read(scanHistoryRepositoryProvider).findAll();
});

/// Free-text query bound to the search bar at the top of the screen.
final scanHistorySearchProvider = StateProvider<String>((ref) => '');

/// Active filter selection (date range, regions, risk levels).
final scanHistoryFilterProvider =
    StateProvider<ScanHistoryFilter>((ref) => ScanHistoryFilter.empty);

/// Search + filter applied on top of [scanHistoryProvider]. Recomputes
/// when any of the three inputs changes; results are sorted newest-first.
final filteredScanHistoryProvider =
    Provider<AsyncValue<List<ScanHistoryEntry>>>((ref) {
  final entries = ref.watch(scanHistoryProvider);
  final query = ref.watch(scanHistorySearchProvider).trim().toLowerCase();
  final filter = ref.watch(scanHistoryFilterProvider);
  final now = DateTime.now();

  return entries.whenData((items) {
    final filtered = items.where((entry) {
      if (!filter.matches(entry, now)) return false;
      if (query.isEmpty) return true;
      return entry.bodyPartLabel.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
    return filtered;
  });
});
