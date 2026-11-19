import 'package:skeen/core/localization/locale_controller.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Brand-themed date + time picker rendered as a bottom sheet. Blocks past
/// instants and returns ``null`` when dismissed. Designed to match the
/// dark/violet skeen palette so it doesn't feel like the OS default.
Future<DateTime?> showSkeenDateTimePicker({
  required BuildContext context,
  required DateTime initial,
  DateTime? minimum,
}) async {
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _SkeenDateTimePickerSheet(
      initial: initial,
      minimum: minimum ?? DateTime.now(),
    ),
  );
}

class _SkeenDateTimePickerSheet extends StatefulWidget {
  const _SkeenDateTimePickerSheet({
    required this.initial,
    required this.minimum,
  });

  final DateTime initial;
  final DateTime minimum;

  @override
  State<_SkeenDateTimePickerSheet> createState() =>
      _SkeenDateTimePickerSheetState();
}

class _SkeenDateTimePickerSheetState extends State<_SkeenDateTimePickerSheet> {
  late DateTime _focusedMonth;
  late DateTime _selectedDate;
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial.isBefore(widget.minimum)
        ? widget.minimum
        : widget.initial;
    _focusedMonth = DateTime(initial.year, initial.month);
    _selectedDate = DateTime(initial.year, initial.month, initial.day);
    _hour = initial.hour;
    _minute = initial.minute;
  }

  DateTime get _composed => DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _hour,
        _minute,
      );

  bool get _isValid => !_composed.isBefore(widget.minimum);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: AppColors.violetaOscuro),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hintText.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Pick a date & time'.tr,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 17,
                color: AppColors.violetaClaro,
              ),
            ),
            const SizedBox(height: 14),
            _MonthHeader(
              month: _focusedMonth,
              minimum: widget.minimum,
              onPrev: () => setState(() {
                _focusedMonth =
                    DateTime(_focusedMonth.year, _focusedMonth.month - 1);
              }),
              onNext: () => setState(() {
                _focusedMonth =
                    DateTime(_focusedMonth.year, _focusedMonth.month + 1);
              }),
            ),
            const SizedBox(height: 8),
            _CalendarGrid(
              focusedMonth: _focusedMonth,
              selected: _selectedDate,
              minimum: widget.minimum,
              onSelect: (date) => setState(() {
                _selectedDate = date;
                if (_composed.isBefore(widget.minimum)) {
                  _hour = widget.minimum.hour;
                  _minute = widget.minimum.minute;
                }
              }),
            ),
            const SizedBox(height: 16),
            _TimeWheels(
              hour: _hour,
              minute: _minute,
              onHourChanged: (h) => setState(() => _hour = h),
              onMinuteChanged: (m) => setState(() => _minute = m),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.violetaClaro,
                      side: const BorderSide(color: Color(0xFF44248D)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text('Cancel'.tr),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _isValid
                        ? () => Navigator.of(context).pop(_composed)
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.violeta,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text('Confirm'.tr),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Subwidgets ────────────────────────────────────────────────────────

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.minimum,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime month;
  final DateTime minimum;
  final VoidCallback onPrev;
  final VoidCallback onNext;


  @override
  Widget build(BuildContext context) {
    final canGoPrev =
        DateTime(month.year, month.month - 1).isAfter(
      DateTime(minimum.year, minimum.month - 1, 0),
    );
    return Row(
      children: [
        IconButton(
          onPressed: canGoPrev ? onPrev : null,
          icon: Icon(
            Icons.chevron_left,
            color: canGoPrev ? AppColors.violetaClaro : AppColors.hintText,
          ),
        ),
        Expanded(
          child: Center(
            child: Text(
              formatMonthYear(month),
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AppColors.violetaClaro,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(
            Icons.chevron_right,
            color: AppColors.violetaClaro,
          ),
        ),
      ],
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.focusedMonth,
    required this.selected,
    required this.minimum,
    required this.onSelect,
  });

  final DateTime focusedMonth;
  final DateTime selected;
  final DateTime minimum;
  final ValueChanged<DateTime> onSelect;

  // H08: Monday-first initials in the active language.
  static List<String> get _weekdayLabels => currentLanguageCode() == 'es'
      ? const ['L', 'M', 'X', 'J', 'V', 'S', 'D']
      : const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);
    // Convert to Mon=0..Sun=6 (Dart weekday is Mon=1..Sun=7).
    final leadingBlanks = firstOfMonth.weekday - 1;
    final daysInMonth =
        DateTime(focusedMonth.year, focusedMonth.month + 1, 0).day;
    final cells = leadingBlanks + daysInMonth;
    final rows = (cells / 7).ceil();
    final today = DateTime.now();

    return Column(
      children: [
        Row(
          children: _weekdayLabels
              .map(
                (label) => Expanded(
                  child: SizedBox(
                    height: 24,
                    child: Center(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          letterSpacing: 0.4,
                          color: Color(0xFF8B82B5),
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 4),
        ...List.generate(rows, (rowIdx) {
          return Row(
            children: List.generate(7, (col) {
              final cellIdx = rowIdx * 7 + col;
              final dayNum = cellIdx - leadingBlanks + 1;
              if (dayNum < 1 || dayNum > daysInMonth) {
                return const Expanded(child: SizedBox(height: 36));
              }
              final date =
                  DateTime(focusedMonth.year, focusedMonth.month, dayNum);
              final isPast = date.isBefore(
                DateTime(minimum.year, minimum.month, minimum.day),
              );
              final isSelected = date == DateTime(
                selected.year,
                selected.month,
                selected.day,
              );
              final isToday = date == DateTime(
                today.year,
                today.month,
                today.day,
              );
              return Expanded(
                child: GestureDetector(
                  onTap: isPast ? null : () => onSelect(date),
                  child: Container(
                    height: 36,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.violeta
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: !isSelected && isToday
                          ? Border.all(
                              color: AppColors.violeta.withValues(alpha: 0.4),
                            )
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$dayNum',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13,
                        color: isPast
                            ? AppColors.hintText.withValues(alpha: 0.4)
                            : isSelected
                                ? Colors.white
                                : AppColors.violetaClaro,
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        }),
      ],
    );
  }
}

class _TimeWheels extends StatelessWidget {
  const _TimeWheels({
    required this.hour,
    required this.minute,
    required this.onHourChanged,
    required this.onMinuteChanged,
  });

  final int hour;
  final int minute;
  final ValueChanged<int> onHourChanged;
  final ValueChanged<int> onMinuteChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1444),
        border: Border.all(color: const Color(0xFF2F1B66)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Spinner(
            value: hour,
            range: 24,
            label: 'HH',
            formatter: (v) => v.toString().padLeft(2, '0'),
            onChanged: onHourChanged,
          ),
          const SizedBox(width: 6),
          const Text(
            ':',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 22,
              color: AppColors.violetaClaro,
            ),
          ),
          const SizedBox(width: 6),
          _Spinner(
            value: minute,
            range: 60,
            label: 'MM',
            formatter: (v) => v.toString().padLeft(2, '0'),
            onChanged: onMinuteChanged,
          ),
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({
    required this.value,
    required this.range,
    required this.label,
    required this.formatter,
    required this.onChanged,
  });

  final int value;
  final int range;
  final String label;
  final String Function(int) formatter;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: 9,
            letterSpacing: 1,
            color: Color(0xFF8B82B5),
          ),
        ),
        Row(
          children: [
            _Stepper(
              icon: Icons.keyboard_arrow_up,
              onTap: () => onChanged((value + 1) % range),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 50,
              child: Center(
                child: Text(
                  formatter(value),
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                    color: AppColors.violetaClaro,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _Stepper(
              icon: Icons.keyboard_arrow_down,
              onTap: () => onChanged((value - 1 + range) % range),
            ),
          ],
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.violeta.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppColors.violetaClaro, size: 18),
      ),
    );
  }
}
