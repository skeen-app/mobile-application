import 'package:skeen/core/localization/locale_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../detection/application/providers.dart';
import '../../detection/application/sync_orchestrator.dart';
import '../domain/scan_history_entry.dart';
import '../domain/scan_history_filter.dart';
import '../infrastructure/repositories/scan_history_repository.dart';

/// Repository binding — cloud-first via the new `/api/v1/scans` endpoint,
/// merged with any locally pending offline rows so the user always sees
/// their full history.
final scanHistoryRepositoryProvider = Provider<ScanHistoryRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final user = auth.user;
  if (user == null) return const EmptyScanHistoryRepository();
  return HttpScanHistoryRepository(
    api: ref.watch(scansApiProvider),
    localRepository: ref.watch(lesionRepositoryProvider),
    tokenReader: () => ref.read(authControllerProvider).token?.value,
    patientId: user.id,
  );
});

/// Raw, unfiltered list of scans for the authenticated user.
///
/// Watches [scanHistoryRepositoryProvider] (rather than reading it once)
/// so the future re-runs automatically when the auth state flips — a
/// fresh login after a sign-out rebuilds the repository with the new
/// user's patientId, and this provider must re-fetch instead of serving
/// the empty list it cached while the session was idle.
final scanHistoryProvider =
    FutureProvider<List<ScanHistoryEntry>>((ref) async {
  final repo = ref.watch(scanHistoryRepositoryProvider);
  return repo.findAll();
});

/// Free-text query bound to the search bar at the top of the screen.
final scanHistorySearchProvider = StateProvider<String>((ref) => '');

/// Active filter selection (date range, regions, risk levels).
final scanHistoryFilterProvider =
    StateProvider<ScanHistoryFilter>((ref) => ScanHistoryFilter.empty);

/// Search + filter applied on top of [scanHistoryProvider].
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
      // H08: labels are stored in English; match the translated label too
      // so a Spanish query ("brazo") finds "Left Arm".
      return entry.bodyPartLabel.toLowerCase().contains(query) ||
          entry.bodyPartLabel.tr.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
    return filtered;
  });
});
