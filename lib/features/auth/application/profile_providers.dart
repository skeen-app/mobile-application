import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../patient/application/lesion_summary_providers.dart';
import '../../reminders/application/reminders_controller.dart';
import '../domain/patient_profile_summary.dart';
import 'auth_controller.dart';

/// Computes the registered-moles count + next-checkup date for the
/// profile dashboard from local sources.
///
///   - Moles count → on-device lesion repository.
///   - Next checkup → earliest scheduled reminder, falling back to the
///     "+1 month after last scan" heuristic when nothing is scheduled.
final profileSummaryProvider =
    FutureProvider<PatientProfileSummary>((ref) async {
  final user = ref.watch(authControllerProvider.select((s) => s.user));
  // Watch (not read) so the projection re-runs when the repository
  // rebuilds on a sign-out/login boundary — otherwise the dashboard
  // tile keeps the empty list it cached while the session was idle.
  final repo = ref.watch(lesionSummaryRepositoryProvider);
  final lesions = repo == null ? const [] : await repo.findAll();

  // Watch the reminders list so the tile recomputes when one is created
  // or removed.
  ref.watch(remindersControllerProvider);
  final earliest =
      ref.read(remindersControllerProvider.notifier).nextUpcoming?.scheduledAt;

  return PatientProfileSummary(
    registeredMoles: lesions.length,
    lastScanAt: user?.lastScanAt,
    earliestReminderAt: earliest,
  );
});
