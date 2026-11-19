import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../../core/localization/locale_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_top_app_bar.dart';
import '../../../detection/domain/class_label.dart';
import '../../../detection/domain/lesion_analysis.dart';
import '../../../detection/application/providers.dart';
import '../../../reminders/application/reminders_controller.dart';
import '../../../reminders/domain/reminder.dart';
import '../../../reminders/presentation/widgets/skeen_date_time_picker.dart';
import '../../../auth/application/auth_controller.dart';

/// Scheduler for skin-check alarms. Lists upcoming reminders, surfaces a
/// risk-aware "recommended next check" card, and lets the user pick a
/// type, recurrence and exact instant via a brand-themed picker.
class ReminderScreen extends ConsumerStatefulWidget {
  const ReminderScreen({super.key});

  @override
  ConsumerState<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends ConsumerState<ReminderScreen> {
  Future<List<LesionAnalysis>>? _scansFuture;

  @override
  void initState() {
    super.initState();
    _scansFuture = _loadRecentScans();
  }

  Future<List<LesionAnalysis>> _loadRecentScans() async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return const [];
    final repo = ref.read(lesionRepositoryProvider);
    await repo.initialize();
    return repo.findByPatient(user.id);
  }

  @override
  Widget build(BuildContext context) {
    final reminders = ref.watch(remindersControllerProvider);
    final now = DateTime.now();
    final upcoming = reminders
        .where((r) => r.scheduledAt.isAfter(now))
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            SkeenTopAppBar(
              title: 'Reminders'.tr,
              subtitle: 'your skin routine'.tr,
              showBack: true,
            ),
            Expanded(
              child: FutureBuilder<List<LesionAnalysis>>(
                future: _scansFuture,
                builder: (context, snap) {
                  final scans = snap.data ?? const <LesionAnalysis>[];
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [
                      _SmartSuggestionCard(
                        scans: scans,
                        onSchedule: (preset) => _openCreateSheet(
                          context,
                          recentScans: scans,
                          presetSuggestion: preset,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _SectionLabel(label: 'NEW REMINDER'.tr),
                      const SizedBox(height: 8),
                      _CreateTile(
                        icon: Icons.alarm_add_outlined,
                        title: 'Schedule a reminder'.tr,
                        subtitle:
                            'Pick a type, repetition and exact time.'.tr,
                        onTap: () => _openCreateSheet(
                          context,
                          recentScans: scans,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _SectionLabel(label: 'UPCOMING'.tr),
                      const SizedBox(height: 8),
                      if (upcoming.isEmpty)
                        const _EmptyUpcoming()
                      else
                        ...upcoming.map(
                          (r) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Dismissible(
                              key: ValueKey(r.id),
                              direction: DismissDirection.endToStart,
                              background: _swipeBackground(),
                              onDismissed: (_) async {
                                await ref
                                    .read(remindersControllerProvider.notifier)
                                    .remove(r.id);
                              },
                              child: _ReminderCard(
                                reminder: r,
                                onTap: () => _openCreateSheet(
                                  context,
                                  recentScans: scans,
                                  editing: r,
                                ),
                              ),
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
              onTabSelected: (tab) {
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
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _swipeBackground() => Container(
        decoration: BoxDecoration(
          color: AppColors.fucsia.withValues(alpha: 0.18),
          border:
              Border.all(color: AppColors.fucsia.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        child:
            const Icon(Icons.delete_outline, color: AppColors.fucsia, size: 22),
      );

  Future<void> _openCreateSheet(
    BuildContext context, {
    required List<LesionAnalysis> recentScans,
    Reminder? editing,
    _SuggestedPreset? presetSuggestion,
  }) async {
    // Permission gating — the alarm is useless if the OS won't let us
    // fire a notification. We ask once here and bail with a snackbar if
    // the user rejected it permanently.
    final scheduler = ref.read(localNotificationServiceProvider);
    final granted = await scheduler.isPermissionGranted();
    if (!granted) {
      final result = await scheduler.requestPermissions();
      if (!result) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Notification permission is required for reminders.'.tr,
            ),
          ),
        );
        return;
      }
    }
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ReminderSheet(
        recentScans: recentScans,
        editing: editing,
        presetSuggestion: presetSuggestion,
        onSubmit: (input) async {
          final controller = ref.read(remindersControllerProvider.notifier);
          if (editing != null) {
            await controller.update(
              editing.copyWith(
                type: input.type,
                scanId: input.scanId,
                scheduledAt: input.scheduledAt,
                repeat: input.repeat,
                title: input.title,
                note: input.note,
              ),
            );
          } else {
            await controller.create(
              type: input.type,
              scheduledAt: input.scheduledAt,
              repeat: input.repeat,
              scanId: input.scanId,
              title: input.title,
              note: input.note,
            );
          }
        },
      ),
    );
    if (mounted) setState(() => _scansFuture = _loadRecentScans());
  }
}

// ── Smart suggestion card ─────────────────────────────────────────────

class _SmartSuggestionCard extends StatelessWidget {
  const _SmartSuggestionCard({
    required this.scans,
    required this.onSchedule,
  });

  final List<LesionAnalysis> scans;
  final ValueChanged<_SuggestedPreset> onSchedule;

  @override
  Widget build(BuildContext context) {
    final preset = _computePreset(scans);
    if (preset == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            preset.accent.withValues(alpha: 0.22),
            const Color(0xFF1E1444),
          ],
        ),
        border: Border.all(color: preset.accent.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: preset.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.bolt, color: preset.accent, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                'RECOMMENDED'.tr,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: preset.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            preset.title.tr,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: AppColors.violetaClaro,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            preset.subtitle,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w400,
              fontSize: 12.5,
              height: 1.5,
              color: Color(0xFFCCC3D8),
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => onSchedule(preset),
              icon: const Icon(Icons.alarm_add_outlined, size: 16),
              label: Text('Schedule this'.tr),
              style: FilledButton.styleFrom(
                backgroundColor: preset.accent,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Derives a single recommended preset from the user's recent scans.
  /// Priority order: high-risk → 30-day rescan, medium-risk → 60-day,
  /// any low-risk → 6-month routine, no scans → "first scan" nudge.
  _SuggestedPreset? _computePreset(List<LesionAnalysis> scans) {
    if (scans.isEmpty) {
      return _SuggestedPreset(
        title: 'Run your first scan',
        subtitle:
            'Capture a lunar today and we will schedule your follow-ups for you.'.tr,
        accent: AppColors.turquesa,
        type: ReminderType.newScan,
        repeat: ReminderRepeat.none,
        scanId: null,
        scheduledAt: _atNineAm(DateTime.now().add(const Duration(days: 1))),
      );
    }

    // Most concerning recent scan wins.
    LesionAnalysis? alert;
    LesionAnalysis? caution;
    for (final s in scans.take(15)) {
      switch (s.result.warningLevel) {
        case WarningLevel.alert:
          alert ??= s;
        case WarningLevel.caution:
          caution ??= s;
        case WarningLevel.reassuring:
          break;
      }
    }

    if (alert != null) {
      return _SuggestedPreset(
        title: 'Recheck a high-risk lesion in 30 days',
        subtitle:
            '${'A scan flagged as high-risk benefits from a tight follow-up loop. We suggest re-scanning'.tr} '
            '${alert.bodyRegion?.tr ?? 'the same lunar'.tr}.',
        accent: AppColors.fucsia,
        type: ReminderType.rescan,
        repeat: ReminderRepeat.monthly,
        scanId: alert.id,
        scheduledAt: _atNineAm(DateTime.now().add(const Duration(days: 30))),
      );
    }
    if (caution != null) {
      return _SuggestedPreset(
        title: 'Recheck this lesion in 60 days',
        subtitle:
            '${'Atypical patterns deserve a periodic look. Re-scan'.tr} '
            '${caution.bodyRegion?.tr ?? 'the same lunar'.tr} '
            '${'to compare changes.'.tr}',
        accent: AppColors.naranja,
        type: ReminderType.rescan,
        repeat: ReminderRepeat.quarterly,
        scanId: caution.id,
        scheduledAt: _atNineAm(DateTime.now().add(const Duration(days: 60))),
      );
    }
    return _SuggestedPreset(
      title: 'Routine self-exam in 6 months',
      subtitle:
          'No concerning patterns lately — keep the habit with a gentle half-yearly self-examination.'.tr,
      accent: AppColors.turquesa,
      type: ReminderType.selfExamination,
      repeat: ReminderRepeat.quarterly,
      scanId: null,
      scheduledAt: _atNineAm(DateTime.now().add(const Duration(days: 180))),
    );
  }

  static DateTime _atNineAm(DateTime d) =>
      DateTime(d.year, d.month, d.day, 9);
}

class _SuggestedPreset {
  const _SuggestedPreset({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.type,
    required this.repeat,
    required this.scheduledAt,
    this.scanId,
  });
  final String title;
  final String subtitle;
  final Color accent;
  final ReminderType type;
  final ReminderRepeat repeat;
  final String? scanId;
  final DateTime scheduledAt;
}

// ── Misc widgets ─────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: 1.0,
          color: Color(0xFF7B6BB6),
        ),
      ),
    );
  }
}

class _CreateTile extends StatelessWidget {
  const _CreateTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1444),
            border: Border.all(color: const Color(0xFF2F1B66)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.violeta.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: AppColors.violeta, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: AppColors.violetaClaro,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontSize: 12,
                        color: Color(0xFFCCC3D8),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 20, color: Color(0xFF958DA1)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.reminder, required this.onTap});
  final Reminder reminder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateLabel = _formatReminderDate(reminder.scheduledAt);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1A44),
            border: Border.all(color: const Color(0xFF2A1F66)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.violeta.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(reminder.type.icon,
                    color: AppColors.violeta, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminderDisplayTitle(reminder.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFFE2DFFF),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: Color(0xFFCCC3D8),
                      ),
                    ),
                    if (reminder.repeat != ReminderRepeat.none) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.turquesa.withValues(alpha: 0.12),
                          border: Border.all(
                            color:
                                AppColors.turquesa.withValues(alpha: 0.32),
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          reminder.repeat.displayLabel,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 9,
                            letterSpacing: 0.4,
                            color: AppColors.turquesa,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 20, color: Color(0xFF958DA1)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyUpcoming extends StatelessWidget {
  const _EmptyUpcoming();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A123E),
        border: Border.all(color: const Color(0xFF2A1F5C)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.alarm_off_outlined,
              color: AppColors.hintText, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No reminders scheduled yet. Use the recommended card or the "Schedule a reminder" tile above.'.tr,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                height: 1.5,
                color: AppColors.hintText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Create / edit sheet ───────────────────────────────────────────────

class _ReminderSheetInput {
  const _ReminderSheetInput({
    required this.type,
    required this.scheduledAt,
    required this.repeat,
    required this.title,
    this.scanId,
    this.note,
  });
  final ReminderType type;
  final DateTime scheduledAt;
  final ReminderRepeat repeat;
  final String title;
  final String? scanId;
  final String? note;
}

class _ReminderSheet extends StatefulWidget {
  const _ReminderSheet({
    required this.recentScans,
    required this.onSubmit,
    this.editing,
    this.presetSuggestion,
  });

  final List<LesionAnalysis> recentScans;
  final Reminder? editing;
  final _SuggestedPreset? presetSuggestion;
  final Future<void> Function(_ReminderSheetInput) onSubmit;

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  late ReminderType _type;
  late ReminderRepeat _repeat;
  late DateTime _scheduledAt;
  String? _scanId;
  String? _note;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final preset = widget.presetSuggestion;
    final editing = widget.editing;
    if (editing != null) {
      _type = editing.type;
      _repeat = editing.repeat;
      _scheduledAt = editing.scheduledAt;
      _scanId = editing.scanId;
      _note = editing.note;
    } else if (preset != null) {
      _type = preset.type;
      _repeat = preset.repeat;
      _scheduledAt = preset.scheduledAt;
      _scanId = preset.scanId;
    } else {
      _type = ReminderType.newScan;
      _repeat = ReminderRepeat.none;
      _scheduledAt = _defaultPreset(7);
      _scanId = null;
    }
  }

  static DateTime _defaultPreset(int daysFromNow) {
    final d = DateTime.now().add(Duration(days: daysFromNow));
    return DateTime(d.year, d.month, d.day, 9);
  }

  String get _composedTitle {
    if (_type == ReminderType.rescan && _scanId != null) {
      final match = widget.recentScans.firstWhere(
        (s) => s.id == _scanId,
        orElse: () => widget.recentScans.first,
      );
      // Stored in English so the list can re-translate it on a language
      // switch (see [reminderDisplayTitle]).
      return 'Re-scan ${match.bodyRegion ?? 'your lunar'}';
    }
    return _type.displayLabel;
  }

  Future<void> _pickDate() async {
    final picked = await showSkeenDateTimePicker(
      context: context,
      initial: _scheduledAt,
    );
    if (picked != null) setState(() => _scheduledAt = picked);
  }

  bool get _isValid {
    if (_scheduledAt.isBefore(DateTime.now())) return false;
    if (_type == ReminderType.rescan && _scanId == null) return false;
    return true;
  }

  Future<void> _submit() async {
    if (!_isValid || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSubmit(
        _ReminderSheetInput(
          type: _type,
          scheduledAt: _scheduledAt,
          repeat: _repeat,
          title: _composedTitle,
          scanId: _scanId,
          note: _note,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollCtrl) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: AppColors.violetaOscuro),
          borderRadius: BorderRadius.circular(24),
        ),
        child: ListView(
          controller: scrollCtrl,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hintText.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.editing != null ? 'Edit reminder'.tr : 'New reminder'.tr,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 18,
                color: AppColors.violetaClaro,
              ),
            ),
            const SizedBox(height: 16),
            _SubLabel(label: 'Type'.tr),
            const SizedBox(height: 6),
            _TypeSelector(
              value: _type,
              hasScans: widget.recentScans.isNotEmpty,
              onChanged: (v) => setState(() {
                _type = v;
                if (v != ReminderType.rescan) _scanId = null;
              }),
            ),
            if (_type == ReminderType.rescan) ...[
              const SizedBox(height: 14),
              _SubLabel(label: 'Which mole?'.tr),
              const SizedBox(height: 6),
              _ScanPicker(
                scans: widget.recentScans,
                selected: _scanId,
                onChanged: (id) => setState(() => _scanId = id),
              ),
            ],
            const SizedBox(height: 14),
            _SubLabel(label: 'When'.tr),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _PresetChip(
                    label: '1 week'.tr,
                    selected: _isPresetMatch(7),
                    onTap: () =>
                        setState(() => _scheduledAt = _defaultPreset(7)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _PresetChip(
                    label: '1 month'.tr,
                    selected: _isPresetMatch(30),
                    onTap: () =>
                        setState(() => _scheduledAt = _defaultPreset(30)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _PresetChip(
                    label: '3 months'.tr,
                    selected: _isPresetMatch(90),
                    onTap: () =>
                        setState(() => _scheduledAt = _defaultPreset(90)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _DateButton(
              dateTime: _scheduledAt,
              onTap: _pickDate,
            ),
            const SizedBox(height: 14),
            _SubLabel(label: 'Repeat'.tr),
            const SizedBox(height: 6),
            _RepeatSelector(
              value: _repeat,
              onChanged: (v) => setState(() => _repeat = v),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _isValid && !_saving ? _submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.violeta,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(widget.editing != null
                      ? 'Save changes'.tr
                      : 'Schedule reminder'.tr),
            ),
          ],
        ),
      ),
    );
  }

  bool _isPresetMatch(int days) {
    final preset = _defaultPreset(days);
    return _scheduledAt.year == preset.year &&
        _scheduledAt.month == preset.month &&
        _scheduledAt.day == preset.day &&
        _scheduledAt.hour == preset.hour &&
        _scheduledAt.minute == preset.minute;
  }
}

class _SubLabel extends StatelessWidget {
  const _SubLabel({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontFamily: 'Poppins',
        fontWeight: FontWeight.w600,
        fontSize: 12,
        letterSpacing: 0.6,
        color: Color(0xFF8B82B5),
      ),
    );
  }
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({
    required this.value,
    required this.hasScans,
    required this.onChanged,
  });
  final ReminderType value;
  final bool hasScans;
  final ValueChanged<ReminderType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: ReminderType.values
          .map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TypeRow(
                type: t,
                selected: value == t,
                disabled: t == ReminderType.rescan && !hasScans,
                onTap: () => onChanged(t),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.type,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });
  final ReminderType type;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: disabled ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:
                selected ? AppColors.violeta.withValues(alpha: 0.18) : const Color(0xFF1E1444),
            border: Border.all(
              color: selected ? AppColors.violeta : const Color(0xFF2F1B66),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                type.icon,
                color: disabled
                    ? AppColors.hintText
                    : selected
                        ? Colors.white
                        : AppColors.violetaClaro,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.displayLabel,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 13,
                        color: disabled
                            ? AppColors.hintText
                            : AppColors.violetaClaro,
                      ),
                    ),
                    Text(
                      disabled
                          ? 'Available once you have at least one scan'.tr
                          : type.description,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: Color(0xFFB5A9E9),
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

class _ScanPicker extends StatelessWidget {
  const _ScanPicker({
    required this.scans,
    required this.selected,
    required this.onChanged,
  });
  final List<LesionAnalysis> scans;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: scans.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = scans[i];
          final isSelected = s.id == selected;
          return GestureDetector(
            onTap: () => onChanged(s.id),
            child: Container(
              width: 150,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.violeta.withValues(alpha: 0.18)
                    : const Color(0xFF1E1444),
                border: Border.all(
                  color: isSelected
                      ? AppColors.violeta
                      : const Color(0xFF2F1B66),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    s.bodyRegion?.tr ?? 'Lunar'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.violetaClaro,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.result.topLabel.display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                      color: Color(0xFFCCC3D8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat.MMMd(currentLanguageCode()).format(s.capturedAt),
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      color: Color(0xFF8B82B5),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.violeta.withValues(alpha: 0.18)
                : const Color(0xFF1E1444),
            border: Border.all(
              color: selected ? AppColors.violeta : const Color(0xFF2F1B66),
            ),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: AppColors.violetaClaro,
            ),
          ),
        ),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({required this.dateTime, required this.onTap});
  final DateTime dateTime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label =
        '${DateFormat.yMMMEd(currentLanguageCode()).format(dateTime)} · '
        '${DateFormat.jm(currentLanguageCode()).format(dateTime)}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1444),
            border: Border.all(color: const Color(0xFF2F1B66)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.event_outlined,
                  color: AppColors.violeta, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.violetaClaro,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: Color(0xFF958DA1), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepeatSelector extends StatelessWidget {
  const _RepeatSelector({required this.value, required this.onChanged});
  final ReminderRepeat value;
  final ValueChanged<ReminderRepeat> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: ReminderRepeat.values
          .map(
            (r) => Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _PresetChip(
                  label: r.displayLabel,
                  selected: value == r,
                  onTap: () => onChanged(r),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}


/// H08: reminder titles are stored as English keys ("Scan a new mole",
/// "Re-scan Left Arm"), so the list re-translates them on every build and
/// a language switch also applies to reminders created earlier.
String reminderDisplayTitle(String stored) {
  const rescan = 'Re-scan ';
  if (stored.startsWith(rescan)) {
    final target = stored.substring(rescan.length);
    return '${'Re-scan'.tr} ${target.tr}';
  }
  return stored.tr;
}

String _formatReminderDate(DateTime at) {
  final lang = currentLanguageCode();
  return '${DateFormat.MMMEd(lang).format(at)} · ${DateFormat.jm(lang).format(at)}';
}
