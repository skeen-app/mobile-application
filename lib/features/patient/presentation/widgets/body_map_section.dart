import 'package:skeen/core/localization/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/body_region.dart';
import '../../domain/lesion_summary.dart';

/// Aggregate body-map widget for the home dashboard.
///
/// Layers the silhouette SVG with data-driven dots painted at the normalized
/// coordinate of each `LesionSummary`, and shows per-group bars (Head/Chest/
/// Legs) on the right side.
class BodyMapSection extends StatelessWidget {
  const BodyMapSection({
    super.key,
    required this.summaries,
    required this.counts,
    required this.onCompleteView,
    required this.onAddNew,
    this.pendingSyncCount = 0,
  });

  final List<LesionSummary> summaries;
  final Map<BodyRegionGroup, int> counts;
  final VoidCallback onCompleteView;
  final VoidCallback onAddNew;

  /// Number of locally captured scans waiting to be uploaded to cloud.
  /// When > 0 a discreet badge is shown next to the section title so the
  /// user knows their offline scans are queued.
  final int pendingSyncCount;

  static const double _figureWidth = 58;
  static const double _figureHeight = 165;

  @override
  Widget build(BuildContext context) {
    final total = summaries.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'BODY MAP'.tr,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 12,
                letterSpacing: -0.12,
                color: AppColors.stroke,
              ),
            ),
            if (pendingSyncCount > 0) ...[
              const SizedBox(width: 8),
              _PendingSyncChip(count: pendingSyncCount),
            ],
            const Spacer(),
            GestureDetector(
              onTap: onCompleteView,
              behavior: HitTestBehavior.opaque,
              child: Text(
                'Complete view'.tr,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: 10,
                  letterSpacing: -0.1,
                  color: AppColors.naranja,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1240),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFF291859)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _figureWidth,
                height: _figureHeight,
                child: _BodyFigure(summaries: summaries),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$total',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 24,
                            height: 1.2,
                            letterSpacing: -0.24,
                            color: AppColors.hintText,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Padding(
                          padding: EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Registered moles'.tr,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w400,
                              fontSize: 10,
                              letterSpacing: -0.1,
                              color: AppColors.stroke,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _CountBar(
                      group: BodyRegionGroup.head,
                      count: counts[BodyRegionGroup.head] ?? 0,
                      total: total == 0 ? 1 : total,
                    ),
                    const SizedBox(height: 4),
                    _CountBar(
                      group: BodyRegionGroup.chest,
                      count: counts[BodyRegionGroup.chest] ?? 0,
                      total: total == 0 ? 1 : total,
                    ),
                    const SizedBox(height: 4),
                    _CountBar(
                      group: BodyRegionGroup.legs,
                      count: counts[BodyRegionGroup.legs] ?? 0,
                      total: total == 0 ? 1 : total,
                    ),
                    const SizedBox(height: 12),
                    const _Legend(),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _AddNewButton(onPressed: onAddNew),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BodyFigure extends StatelessWidget {
  const _BodyFigure({required this.summaries});
  final List<LesionSummary> summaries;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        SvgPicture.asset(
          'assets/images/home/body_figure_base.svg',
          fit: BoxFit.contain,
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            return CustomPaint(
              painter: _MoleDotsPainter(summaries: summaries),
              size: constraints.biggest,
            );
          },
        ),
      ],
    );
  }
}

class _MoleDotsPainter extends CustomPainter {
  _MoleDotsPainter({required this.summaries});
  final List<LesionSummary> summaries;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in summaries) {
      final paint = Paint()..color = _colorForStatus(s.status);
      final cx = s.relativePosition.x * size.width;
      final cy = s.relativePosition.y * size.height;
      final radius = s.status == LesionStatus.needsAttention ? 3.0 : 2.2;
      canvas.drawCircle(Offset(cx, cy), radius, paint);
    }
  }

  static Color _colorForStatus(LesionStatus status) {
    switch (status) {
      case LesionStatus.needsAttention:
        return const Color(0xFFE46A1D);
      case LesionStatus.stable:
        return const Color(0xFF9A7FEA);
    }
  }

  @override
  bool shouldRepaint(covariant _MoleDotsPainter old) =>
      old.summaries != summaries;
}

class _CountBar extends StatelessWidget {
  const _CountBar({
    required this.group,
    required this.count,
    required this.total,
  });

  final BodyRegionGroup group;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fraction = (count / total).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            group.label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w400,
              fontSize: 10,
              height: 1.5,
              letterSpacing: -0.1,
              color: Color(0xFFB5A9E9),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Stack(
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF261755),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              FractionallySizedBox(
                widthFactor: fraction,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: group.accent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 14,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w500,
              fontSize: 10,
              letterSpacing: -0.1,
              color: group.accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LegendDot(color: Color(0xFFE46A1D)),
        SizedBox(width: 6),
        Text(
          'Needs attention'.tr,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w400,
            fontSize: 8,
            letterSpacing: -0.08,
            color: AppColors.hintText,
          ),
        ),
        SizedBox(width: 14),
        _LegendDot(color: Color(0xFF9A7FEA)),
        SizedBox(width: 6),
        Text(
          'Stable'.tr,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w400,
            fontSize: 8,
            letterSpacing: -0.08,
            color: AppColors.hintText,
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _PendingSyncChip extends StatelessWidget {
  const _PendingSyncChip({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1F5C),
        border: Border.all(color: const Color(0xFF6B58C4)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_upload_outlined,
            size: 10,
            color: Color(0xFF9B8DEB),
          ),
          const SizedBox(width: 4),
          Text(
            '$count pending',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 9,
              letterSpacing: 0.2,
              color: Color(0xFF9B8DEB),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddNewButton extends StatelessWidget {
  const _AddNewButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2E1A62),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onPressed,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFF44248D)),
          ),
          child: Center(
            child: Text(
              '+ Add new mole'.tr,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
                fontSize: 10,
                height: 1.5,
                letterSpacing: -0.1,
                color: Color(0xFFA78BFA),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
