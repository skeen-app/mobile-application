import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logger/app_logger.dart';
import '../../auth/application/auth_controller.dart';
import '../../detection/application/providers.dart';
import '../../detection/application/sync_orchestrator.dart';
import '../domain/body_region.dart';
import '../domain/lesion_summary.dart';
import '../infrastructure/repositories/lesion_summary_repository.dart';

final lesionSummaryRepositoryProvider =
    Provider<LesionSummaryRepository?>((ref) {
  final user = ref.watch(authControllerProvider).user;
  if (user == null) return null;
  return LesionSummaryRepository(
    api: ref.watch(scansApiProvider),
    localRepository: ref.watch(lesionRepositoryProvider),
    tokenReader: () => ref.read(authControllerProvider).token?.value,
    patientId: user.id,
  );
});

/// All registered lesions for the current patient — drives both the body-map
/// dots and the per-region counts on the home dashboard.
final lesionSummariesProvider =
    FutureProvider<List<LesionSummary>>((ref) async {
  final repo = ref.watch(lesionSummaryRepositoryProvider);
  if (repo == null) return const [];
  AppLogger.info('Loading lesion summaries', tag: 'LesionSummaryProvider');
  try {
    return await repo.findAll();
  } catch (e, stack) {
    AppLogger.error(
      'Failed to load lesion summaries',
      tag: 'LesionSummaryProvider',
      error: e,
      stackTrace: stack,
    );
    return const [];
  }
});

/// Per-aggregate counts (Head / Chest / Legs) for the home body map bars.
final lesionGroupCountsProvider =
    Provider<AsyncValue<Map<BodyRegionGroup, int>>>((ref) {
  final summaries = ref.watch(lesionSummariesProvider);
  return summaries.whenData((items) {
    final counts = <BodyRegionGroup, int>{
      BodyRegionGroup.head: 0,
      BodyRegionGroup.chest: 0,
      BodyRegionGroup.legs: 0,
    };
    for (final s in items) {
      counts[s.region.group] = (counts[s.region.group] ?? 0) + 1;
    }
    return counts;
  });
});
