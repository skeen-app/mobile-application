import 'package:skeen/core/localization/locale_controller.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/body_region.dart';
import '../../domain/risk_level.dart';
import '../../domain/scan_history_filter.dart';

/// Bottom sheet that lets the user narrow the history by date range, body
/// region group, and risk level. Pop value:
///   - `ScanHistoryFilter` → user pressed Apply (or Reset → empty filter)
///   - `null`              → user dismissed without applying
Future<ScanHistoryFilter?> showScanHistoryFilterSheet(
  BuildContext context, {
  required ScanHistoryFilter current,
}) {
  return showModalBottomSheet<ScanHistoryFilter>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _FilterSheet(initial: current),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});
  final ScanHistoryFilter initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ScanHistoryDateRange _dateRange;
  late Set<BodyRegionGroup> _regionGroups;
  late Set<RiskLevel> _riskLevels;

  @override
  void initState() {
    super.initState();
    _dateRange = widget.initial.dateRange;
    _regionGroups = {...widget.initial.regionGroups};
    _riskLevels = {...widget.initial.riskLevels};
  }

  void _toggleRegion(BodyRegionGroup g) {
    setState(() {
      if (!_regionGroups.add(g)) _regionGroups.remove(g);
    });
  }

  void _toggleRisk(RiskLevel r) {
    setState(() {
      if (!_riskLevels.add(r)) _riskLevels.remove(r);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1A44),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF2F1B66)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
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
              Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(
                  'Filters'.tr,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    letterSpacing: -0.16,
                    color: AppColors.violetaClaro,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Combine date, body region and risk to narrow the list.'.tr,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.hintText,
                  ),
                ),
              ),
              const _SectionLabel('Date range'),
              _DateRangeChips(
                value: _dateRange,
                onChanged: (v) => setState(() => _dateRange = v),
              ),
              const _SectionLabel('Body region'),
              _RegionChips(
                selected: _regionGroups,
                onToggle: _toggleRegion,
              ),
              const _SectionLabel('Risk level'),
              _RiskChips(
                selected: _riskLevels,
                onToggle: _toggleRisk,
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context)
                            .pop(ScanHistoryFilter.empty),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(99),
                            side: BorderSide(
                              color: AppColors.violeta.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                        child: Text(
                          'Reset'.tr,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                            color: AppColors.violeta,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.violeta,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop(
                            ScanHistoryFilter(
                              dateRange: _dateRange,
                              regionGroups: {..._regionGroups},
                              riskLevels: {..._riskLevels},
                            ),
                          );
                        },
                        child: Text(
                          'Apply'.tr,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 12,
          letterSpacing: 0.6,
          color: Color(0xFF8B76E1),
        ),
      ),
    );
  }
}

class _DateRangeChips extends StatelessWidget {
  const _DateRangeChips({required this.value, required this.onChanged});
  final ScanHistoryDateRange value;
  final ValueChanged<ScanHistoryDateRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final r in ScanHistoryDateRange.values)
            _Chip(
              label: r.label,
              selected: r == value,
              onTap: () => onChanged(r),
            ),
        ],
      ),
    );
  }
}

class _RegionChips extends StatelessWidget {
  const _RegionChips({required this.selected, required this.onToggle});
  final Set<BodyRegionGroup> selected;
  final ValueChanged<BodyRegionGroup> onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final g in BodyRegionGroup.values)
            _Chip(
              label: g.label,
              selected: selected.contains(g),
              accent: g.accent,
              onTap: () => onToggle(g),
            ),
        ],
      ),
    );
  }
}

class _RiskChips extends StatelessWidget {
  const _RiskChips({required this.selected, required this.onToggle});
  final Set<RiskLevel> selected;
  final ValueChanged<RiskLevel> onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final r in RiskLevel.values)
            _Chip(
              label: r.label,
              selected: selected.contains(r),
              accent: r.accent,
              onTap: () => onToggle(r),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final base = accent ?? AppColors.violeta;
    return Material(
      color: selected ? base.withValues(alpha: 0.18) : const Color(0xFF0A0732),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected
                  ? base.withValues(alpha: 0.6)
                  : const Color(0xFF2F1B66),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w500,
              fontSize: 13,
              color: selected ? base : AppColors.violetaClaro,
            ),
          ),
        ),
      ),
    );
  }
}
