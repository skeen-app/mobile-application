import 'package:skeen/core/localization/locale_controller.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_top_app_bar.dart';
import '../widgets/body_part_icon.dart' show BodyPartIcon;
import '../../application/lesion_summary_providers.dart';
import '../../application/scan_history_providers.dart';
import '../../application/scan_thumbnail_provider.dart';
import '../../domain/body_region.dart';
import '../../domain/lesion_summary.dart';
import '../../domain/risk_level.dart';
import '../../domain/scan_history_entry.dart';

/// Full-screen body map.
///
/// Top: chips that filter the dots by [BodyRegionGroup] (Head / Chest /
/// Legs / All) and by [LesionStatus] (Needs attention / Stable / All).
///
/// Middle: a large skeen silhouette that fills the available vertical
/// space, with every lesion painted as a colour-coded dot at its
/// recorded relative position. Tapping a dot opens a brand-themed
/// bottom-sheet with the scan thumbnail, body region, risk level pill
/// and date — plus a CTA that pushes the rich ScanDetailScreen so the
/// user can read the full AI verdict.
///
/// Bottom: a horizontal carousel of the most recent scans so the user
/// can drill in chronologically without scrubbing the map.
class BodyMapScreen extends ConsumerStatefulWidget {
  const BodyMapScreen({super.key});

  @override
  ConsumerState<BodyMapScreen> createState() => _BodyMapScreenState();
}

class _BodyMapScreenState extends ConsumerState<BodyMapScreen> {
  BodyRegionGroup? _regionFilter;
  LesionStatus? _statusFilter;

  static const double _figureAspect = 58 / 165;

  @override
  Widget build(BuildContext context) {
    final summariesAsync = ref.watch(lesionSummariesProvider);
    final historyAsync = ref.watch(scanHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            SkeenTopAppBar(
              title: 'Complete body map'.tr,
              subtitle: 'track your moles'.tr,
              showBack: true,
            ),
            Expanded(
              child: summariesAsync.when(
                loading: _LoadingState.new,
                error: (_, _) => const _ErrorState(),
                data: (allSummaries) {
                  final filtered = _applyFilters(allSummaries);
                  return CustomScrollView(
                    physics: const ClampingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: _FiltersBar(
                          regionFilter: _regionFilter,
                          statusFilter: _statusFilter,
                          onRegionChanged: (g) =>
                              setState(() => _regionFilter = g),
                          onStatusChanged: (s) =>
                              setState(() => _statusFilter = s),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _StatsRow(
                          total: allSummaries.length,
                          shown: filtered.length,
                          needsAttention: filtered
                              .where(
                                (s) => s.status == LesionStatus.needsAttention,
                              )
                              .length,
                          stable: filtered
                              .where((s) => s.status == LesionStatus.stable)
                              .length,
                        ),
                      ),
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding:
                              const EdgeInsets.fromLTRB(20, 8, 20, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: filtered.isEmpty
                                    ? _EmptyFigureState(
                                        hasFilters: _regionFilter != null ||
                                            _statusFilter != null,
                                      )
                                    : Center(
                                        child: AspectRatio(
                                          aspectRatio: _figureAspect,
                                          child: _BodyFigure(
                                            summaries: filtered,
                                            onDotTap: _openDetailSheet,
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 12),
                              const _LegendRow(),
                              const SizedBox(height: 16),
                              _RecentScansStrip(
                                historyAsync: historyAsync,
                                regionFilter: _regionFilter,
                                onTapEntry: _openDetailSheetForEntry,
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            SkeenBottomNav(
              activeTab: SkeenNavTab.home,
              onTabSelected: _onTabSelected,
            ),
          ],
        ),
      ),
    );
  }

  List<LesionSummary> _applyFilters(List<LesionSummary> summaries) {
    return summaries.where((s) {
      if (_regionFilter != null && s.region.group != _regionFilter) {
        return false;
      }
      if (_statusFilter != null && s.status != _statusFilter) return false;
      return true;
    }).toList();
  }

  void _openDetailSheet(LesionSummary summary) {
    final history = ref.read(scanHistoryProvider).value ?? const [];
    ScanHistoryEntry? entry;
    for (final e in history) {
      if (e.id == summary.id) {
        entry = e;
        break;
      }
    }
    if (entry == null) {
      // The dot is rendered from the local-only summary projection but
      // the rich history entry isn't in cache yet (e.g. user just
      // opened the screen offline). Fall back to navigating directly to
      // the detail screen which has its own three-path resolver.
      _pushScanDetail(summary.id, remoteImageUrl: null, bodyRegion: null);
      return;
    }
    final captured = entry;
    _showSheet(
      builder: (ctx) => _ScanDetailSheet(
        entry: captured,
        onOpenFull: () {
          Navigator.of(ctx).pop();
          _pushScanDetail(
            captured.id,
            remoteImageUrl: captured.thumbnailUrl,
            bodyRegion: captured.bodyPartLabel,
          );
        },
      ),
    );
  }

  void _openDetailSheetForEntry(ScanHistoryEntry entry) {
    _showSheet(
      builder: (ctx) => _ScanDetailSheet(
        entry: entry,
        onOpenFull: () {
          Navigator.of(ctx).pop();
          _pushScanDetail(
            entry.id,
            remoteImageUrl: entry.thumbnailUrl,
            bodyRegion: entry.bodyPartLabel,
          );
        },
      ),
    );
  }

  void _showSheet({required WidgetBuilder builder}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: builder,
    );
  }

  void _pushScanDetail(
    String scanId, {
    String? remoteImageUrl,
    String? bodyRegion,
  }) {
    context.pushNamed(
      'scan-detail',
      pathParameters: {'scanId': scanId},
      extra: {
        'remoteImageUrl': remoteImageUrl,
        'bodyRegion': bodyRegion,
      },
    );
  }

  void _onTabSelected(SkeenNavTab tab) {
    switch (tab) {
      case SkeenNavTab.home:
        context.goNamed('home');
      case SkeenNavTab.history:
        context.goNamed('history');
      case SkeenNavTab.scan:
        context.pushNamed('scan-a-mole');
      case SkeenNavTab.experts:
        context.goNamed('experts');
      case SkeenNavTab.profile:
        context.goNamed('profile');
    }
  }
}

// ──────────────────────────────────────────────────────────────────────
// Filters bar — region group + status chips
// ──────────────────────────────────────────────────────────────────────

class _FiltersBar extends StatelessWidget {
  const _FiltersBar({
    required this.regionFilter,
    required this.statusFilter,
    required this.onRegionChanged,
    required this.onStatusChanged,
  });

  final BodyRegionGroup? regionFilter;
  final LesionStatus? statusFilter;
  final ValueChanged<BodyRegionGroup?> onRegionChanged;
  final ValueChanged<LesionStatus?> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FilterGroupLabel(label: 'REGION'.tr),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All'.tr,
                  selected: regionFilter == null,
                  accent: AppColors.violetaLink,
                  onTap: () => onRegionChanged(null),
                ),
                for (final g in BodyRegionGroup.values) ...[
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: g.label.tr,
                    selected: regionFilter == g,
                    accent: g.accent,
                    onTap: () => onRegionChanged(g),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _FilterGroupLabel(label: 'STATUS'.tr),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All'.tr,
                  selected: statusFilter == null,
                  accent: AppColors.violetaLink,
                  onTap: () => onStatusChanged(null),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Needs attention'.tr,
                  selected: statusFilter == LesionStatus.needsAttention,
                  accent: AppColors.naranja,
                  onTap: () => onStatusChanged(LesionStatus.needsAttention),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Stable'.tr,
                  selected: statusFilter == LesionStatus.stable,
                  accent: AppColors.violetaLink,
                  onTap: () => onStatusChanged(LesionStatus.stable),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _FilterGroupLabel extends StatelessWidget {
  const _FilterGroupLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontFamily: 'Poppins',
        fontWeight: FontWeight.w600,
        fontSize: 10,
        letterSpacing: 1.2,
        color: AppColors.stroke,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.18)
                : const Color(0xFF1A1240),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.7)
                  : const Color(0xFF291859),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 12,
              letterSpacing: -0.12,
              color: selected ? accent : AppColors.hintText,
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Stats summary row
// ──────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.total,
    required this.shown,
    required this.needsAttention,
    required this.stable,
  });

  final int total;
  final int shown;
  final int needsAttention;
  final int stable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1240),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF291859)),
        ),
        child: Row(
          children: [
            _Stat(
              value: shown == total
                  ? '$total'
                  : '$shown / $total',
              label: 'Total'.tr,
              color: AppColors.violetaClaro,
            ),
            const _Divider(),
            _Stat(
              value: '$needsAttention',
              label: 'Needs attention'.tr,
              color: AppColors.naranja,
            ),
            const _Divider(),
            _Stat(
              value: '$stable',
              label: 'Stable'.tr,
              color: AppColors.violetaLink,
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 18,
              letterSpacing: -0.18,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w500,
              fontSize: 9,
              letterSpacing: 0.8,
              color: AppColors.stroke,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFF291859),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Body figure with tappable dots
// ──────────────────────────────────────────────────────────────────────

class _BodyFigure extends StatelessWidget {
  const _BodyFigure({
    required this.summaries,
    required this.onDotTap,
  });

  final List<LesionSummary> summaries;
  final void Function(LesionSummary) onDotTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _handleTap(details.localPosition, size),
          child: Stack(
            fit: StackFit.expand,
            children: [
              SvgPicture.asset(
                'assets/images/home/body_figure_base.svg',
                fit: BoxFit.contain,
              ),
              CustomPaint(
                painter: _BodyMapDotsPainter(summaries: summaries),
                size: size,
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleTap(Offset localPosition, Size size) {
    // Generous touch target — visual radius is 4-6 pt but fingers need
    // ~24 pt to land reliably. We pick the closest dot within range so
    // crowded regions still resolve to the intended lesion.
    const hitRadius = 22.0;
    LesionSummary? closest;
    double bestDistance = double.infinity;
    for (final s in summaries) {
      final cx = s.relativePosition.x * size.width;
      final cy = s.relativePosition.y * size.height;
      final dx = localPosition.dx - cx;
      final dy = localPosition.dy - cy;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d <= hitRadius && d < bestDistance) {
        bestDistance = d;
        closest = s;
      }
    }
    if (closest != null) onDotTap(closest);
  }
}

class _BodyMapDotsPainter extends CustomPainter {
  _BodyMapDotsPainter({required this.summaries});
  final List<LesionSummary> summaries;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in summaries) {
      final cx = s.relativePosition.x * size.width;
      final cy = s.relativePosition.y * size.height;
      final isAttention = s.status == LesionStatus.needsAttention;
      final color = isAttention
          ? const Color(0xFFE46A1D)
          : const Color(0xFF9A7FEA);
      final radius = isAttention ? 6.0 : 4.5;

      // Soft halo — gives the dot weight against the silhouette without
      // demanding a stroke that would distort small marks.
      final halo = Paint()
        ..color = color.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(Offset(cx, cy), radius + 4, halo);

      final core = Paint()..color = color;
      canvas.drawCircle(Offset(cx, cy), radius, core);

      // White inner highlight gives the dot dimension at this larger
      // scale (the home dashboard renders flat 2.2 pt dots so this is
      // only worth it on the complete view).
      final highlight = Paint()
        ..color = Colors.white.withValues(alpha: 0.35);
      canvas.drawCircle(
        Offset(cx - radius * 0.35, cy - radius * 0.35),
        radius * 0.32,
        highlight,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BodyMapDotsPainter old) =>
      old.summaries != summaries;
}

// ──────────────────────────────────────────────────────────────────────
// Recent scans horizontal strip
// ──────────────────────────────────────────────────────────────────────

class _RecentScansStrip extends ConsumerWidget {
  const _RecentScansStrip({
    required this.historyAsync,
    required this.regionFilter,
    required this.onTapEntry,
  });

  final AsyncValue<List<ScanHistoryEntry>> historyAsync;
  final BodyRegionGroup? regionFilter;
  final void Function(ScanHistoryEntry) onTapEntry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'RECENT SCANS'.tr,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 10,
                letterSpacing: 1.2,
                color: AppColors.stroke,
              ),
            ),
            const Spacer(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => GoRouter.of(context).goNamed('history'),
              child: Text(
                'See all'.tr,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                  letterSpacing: -0.1,
                  color: AppColors.naranja,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 96,
          child: historyAsync.when(
            loading: () => const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.violetaClaro,
                  ),
                ),
              ),
            ),
            error: (_, _) => Center(
              child: Text(
                'Could not load recent scans'.tr,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: AppColors.hintText,
                ),
              ),
            ),
            data: (entries) {
              final filtered = entries
                  .where((e) =>
                      regionFilter == null ||
                      e.region.group == regionFilter)
                  .toList()
                ..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
              final recent = filtered.take(8).toList();
              if (recent.isEmpty) {
                return _RecentEmpty(
                  hasFilter: regionFilter != null,
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: recent.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (ctx, i) {
                  final e = recent[i];
                  return _RecentScanCard(
                    entry: e,
                    onTap: () => onTapEntry(e),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RecentEmpty extends StatelessWidget {
  const _RecentEmpty({required this.hasFilter});
  final bool hasFilter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        hasFilter
            ? 'No scans for this region yet'.tr
            : 'No scans yet — capture your first mole'.tr,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          color: AppColors.hintText,
        ),
      ),
    );
  }
}

class _RecentScanCard extends ConsumerWidget {
  const _RecentScanCard({required this.entry, required this.onTap});
  final ScanHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cropped = ref.watch(scanThumbnailProvider(entry.id));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 86,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1240),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: entry.riskLevel.accent.withValues(alpha: 0.45),
            ),
          ),
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _Thumb(
                    cropped: cropped.value,
                    remoteUrl: entry.thumbnailUrl,
                    fallbackLabel: entry.bodyPartLabel,
                    accent: entry.region.group.accent,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                entry.riskLevel.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 9,
                  letterSpacing: 0.6,
                  color: entry.riskLevel.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.cropped,
    required this.remoteUrl,
    required this.fallbackLabel,
    required this.accent,
  });

  final dynamic cropped; // Uint8List?
  final String? remoteUrl;
  final String fallbackLabel;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (cropped != null) {
      return Image.memory(
        cropped,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    if (remoteUrl != null && remoteUrl!.isNotEmpty) {
      return Image.network(
        remoteUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _PlaceholderThumb(
          accent: accent,
          label: fallbackLabel,
        ),
      );
    }
    return _PlaceholderThumb(accent: accent, label: fallbackLabel);
  }
}

class _PlaceholderThumb extends StatelessWidget {
  const _PlaceholderThumb({required this.accent, required this.label});
  final Color accent;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.2),
            const Color(0xFF0A0732),
          ],
        ),
      ),
      child: Center(
        child: BodyPartIcon.fromLabel(
          label: label,
          color: accent.withValues(alpha: 0.9),
          size: 22,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Legend, empty, loading, error states
// ──────────────────────────────────────────────────────────────────────

class _LegendRow extends StatelessWidget {
  const _LegendRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LegendDot(color: const Color(0xFFE46A1D), label: 'Needs attention'.tr),
        const SizedBox(width: 22),
        _LegendDot(color: const Color(0xFF9A7FEA), label: 'Stable'.tr),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            color: AppColors.hintText,
          ),
        ),
      ],
    );
  }
}

class _EmptyFigureState extends StatelessWidget {
  const _EmptyFigureState({required this.hasFilters});
  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasFilters ? Icons.filter_alt_off_outlined : Icons.healing_outlined,
            size: 48,
            color: AppColors.hintText,
          ),
          const SizedBox(height: 14),
          Text(
            hasFilters
                ? 'No moles match these filters'.tr
                : 'No moles registered yet'.tr,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppColors.violetaClaro,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              hasFilters
                  ? 'Try clearing the region or status filters above.'.tr
                  : 'Capture your first scan and it will appear here.'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                height: 1.4,
                color: AppColors.hintText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(AppColors.violetaClaro),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: AppColors.hintText,
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load your body map'.tr,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AppColors.violetaClaro,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Detail bottom-sheet
// ──────────────────────────────────────────────────────────────────────

class _ScanDetailSheet extends ConsumerWidget {
  const _ScanDetailSheet({
    required this.entry,
    required this.onOpenFull,
  });

  final ScanHistoryEntry entry;
  final VoidCallback onOpenFull;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cropped = ref.watch(scanThumbnailProvider(entry.id));
    final accent = entry.region.group.accent;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1A44),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF2F1B66)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.indigoClaro,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0732),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.35),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _Thumb(
                      cropped: cropped.value,
                      remoteUrl: entry.thumbnailUrl,
                      fallbackLabel: entry.bodyPartLabel,
                      accent: accent,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.bodyPartLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            letterSpacing: -0.2,
                            color: Color(0xFFE2DFFF),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDate(entry.scannedAt),
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w400,
                            fontSize: 12,
                            color: AppColors.hintText,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _RiskPill(level: entry.riskLevel),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onOpenFull,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: Text('See full analysis'.tr),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.violeta,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime at) {
    final day = at.day.toString().padLeft(2, '0');
    final month = _months[at.month - 1];
    return '$month $day, ${at.year}';
  }
}

class _RiskPill extends StatelessWidget {
  const _RiskPill({required this.level});
  final RiskLevel level;

  @override
  Widget build(BuildContext context) {
    final color = level.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        level.label.tr,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }
}
