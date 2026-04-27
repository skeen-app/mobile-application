import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_star_field.dart';
import '../../../../core/widgets/skeen_top_app_bar.dart';
import '../../application/scan_history_providers.dart';
import '../../domain/scan_history_entry.dart';
import '../widgets/scan_history_card.dart';
import '../widgets/scan_history_filter_sheet.dart';
import '../widgets/scan_history_search_bar.dart';

/// Clinical / scan history — Patient bounded context.
///
/// Reachable via two entry points that share the same widget:
///   - Bottom-nav `History` tab → `goNamed('history')` (no back stack).
///   - Profile → "Medical History" row → `pushNamed('history')` (back to
///     Profile).
///
/// Data source today is [MockScanHistoryRepository]; once the backend
/// exposes `GET /me/scan-history` the only thing that needs to change is
/// the binding in `scanHistoryRepositoryProvider`.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.text = ref.read(scanHistorySearchProvider);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    final current = ref.read(scanHistoryFilterProvider);
    final result = await showScanHistoryFilterSheet(context, current: current);
    if (result == null || !mounted) return;
    ref.read(scanHistoryFilterProvider.notifier).state = result;
  }

  void _onTabSelected(SkeenNavTab tab) {
    switch (tab) {
      case SkeenNavTab.home:
        context.goNamed('home');
      case SkeenNavTab.history:
        return;
      case SkeenNavTab.scan:
        context.pushNamed('scan-a-mole');
      case SkeenNavTab.experts:
        context.goNamed('experts');
      case SkeenNavTab.profile:
        context.goNamed('profile');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(scanHistoryFilterProvider);
    final filteredAsync = ref.watch(filteredScanHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.55,
                child: SkeenStarField(seed: 41, density: 16),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SkeenTopAppBar(
                  title: 'Your history',
                  subtitle: 'all your analysis',
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ScanHistorySearchBar(
                          controller: _searchController,
                          onChanged: (q) => ref
                              .read(scanHistorySearchProvider.notifier)
                              .state = q,
                          onFilterPressed: _openFilters,
                          activeFilterCount: filter.activeCount,
                        ),
                        const SizedBox(height: 20),
                        Expanded(
                          child: _HistoryList(filteredAsync: filteredAsync),
                        ),
                      ],
                    ),
                  ),
                ),
                SkeenBottomNav(
                  activeTab: SkeenNavTab.history,
                  onTabSelected: _onTabSelected,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.filteredAsync});
  final AsyncValue<List<ScanHistoryEntry>> filteredAsync;

  @override
  Widget build(BuildContext context) {
    return filteredAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.violeta,
        ),
      ),
      error: (error, _) => const _ErrorState(),
      data: (entries) {
        if (entries.isEmpty) return const _EmptyState();
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 8),
          itemCount: entries.length,
          separatorBuilder: (_, _) => const SizedBox(height: 16),
          itemBuilder: (context, i) => ScanHistoryCard(
            entry: entries[i],
            onTap: () {
              // TODO(detection): push scan detail screen once it exists.
            },
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.violeta.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off,
                size: 28,
                color: AppColors.violeta,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No matches',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: AppColors.violetaClaro,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Try a different search term or clear the active filters.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w400,
                fontSize: 13,
                height: 1.5,
                color: AppColors.hintText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'Could not load your history. Pull to retry once the backend is up.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            color: AppColors.hintText,
          ),
        ),
      ),
    );
  }
}
