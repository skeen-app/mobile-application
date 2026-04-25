import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/body_region.dart';
import '../domain/lesion_summary.dart';
import '../infrastructure/repositories/lesion_summary_repository.dart';

final lesionSummaryRepositoryProvider = Provider<LesionSummaryRepository>((ref) {
  return LesionSummaryRepository();
});

/// All registered lesions for the current patient — drives both the body-map
/// dots and the per-region counts on the home dashboard.
final lesionSummariesProvider = FutureProvider<List<LesionSummary>>((ref) async {
  return ref.read(lesionSummaryRepositoryProvider).findAll();
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
