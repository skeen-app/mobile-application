import 'package:skeen/core/localization/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/skeen_bottom_nav.dart';
import '../../core/widgets/skeen_top_app_bar.dart';
import 'notification_entity.dart';
import 'notifications_controller.dart';

/// Activity log screen — shows the latest 20 events recorded by the
/// notifications controller. Mounts behind the bell icon (home) and the
/// "Notifications" row (profile).
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Mark every visible row as read once the screen settles. Doing this
    // in `addPostFrameCallback` avoids modifying provider state during
    // the build that mounts us.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Tell the banner host we're on this route so it suppresses
      // duplicate banners while we're visible.
      InAppBannerSuppressor.instance.setSuppressed(true);
      ref.read(notificationsControllerProvider.notifier).markAllRead();
    });
  }

  @override
  void dispose() {
    InAppBannerSuppressor.instance.setSuppressed(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsControllerProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              hasItems: state.items.isNotEmpty,
              onClearAll: () => _confirmClearAll(context),
            ),
            Expanded(
              child: state.items.isEmpty
                  ? const _EmptyState()
                  : _NotificationsList(items: state.items),
            ),
            SkeenBottomNav(
              activeTab: SkeenNavTab.profile,
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

  Future<void> _confirmClearAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.violetaOscuro),
        ),
        title: Text(
          'Clear all notifications?'.tr,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            color: AppColors.violetaClaro,
          ),
        ),
        content: Text(
          'This will permanently remove every notification on this device.'.tr,
          style: TextStyle(
            fontFamily: 'Poppins',
            color: AppColors.hintText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.fucsia,
            ),
            child: Text('Clear all'.tr),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(notificationsControllerProvider.notifier).clearAll();
    }
  }
}

/// Mounted by the notifications screen so the in-app banner host can
/// suppress duplicate banners while the user is already on the list.
/// Singleton + ChangeNotifier pattern — keeps the banner host decoupled
/// from go_router's location stream.
class InAppBannerSuppressor extends ChangeNotifier {
  InAppBannerSuppressor._();
  static final InAppBannerSuppressor instance = InAppBannerSuppressor._();
  bool _suppressed = false;
  bool get isSuppressed => _suppressed;
  void setSuppressed(bool value) {
    if (_suppressed == value) return;
    _suppressed = value;
    notifyListeners();
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.hasItems,
    required this.onClearAll,
  });

  final bool hasItems;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SkeenTopAppBar(
          title: 'Notifications'.tr,
          subtitle: 'your activity'.tr,
          showBack: true,
        ),
        if (hasItems)
          Positioned(
            right: 12,
            top: 18,
            child: IconButton(
              tooltip: 'Clear all',
              icon: const Icon(
                Icons.delete_sweep_outlined,
                size: 20,
                color: AppColors.violetaClaro,
              ),
              onPressed: onClearAll,
            ),
          ),
      ],
    );
  }
}

class _NotificationsList extends ConsumerWidget {
  const _NotificationsList({required this.items});
  final List<NotificationEntity> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final entity = items[i];
        return Dismissible(
          key: ValueKey(entity.id),
          direction: DismissDirection.endToStart,
          background: Container(
            decoration: BoxDecoration(
              color: AppColors.fucsia.withValues(alpha: 0.18),
              border: Border.all(
                color: AppColors.fucsia.withValues(alpha: 0.45),
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 22),
            child: const Icon(
              Icons.delete_outline,
              color: AppColors.fucsia,
              size: 22,
            ),
          ),
          onDismissed: (_) => ref
              .read(notificationsControllerProvider.notifier)
              .remove(entity.id),
          child: NotificationRow(
            entity: entity,
            onTap: () => _navigateForType(context, entity),
          ),
        );
      },
    );
  }
}

void _navigateForType(BuildContext context, NotificationEntity entity) {
  switch (entity.type) {
    case NotificationType.scanCompleted:
    case NotificationType.predictionReady:
    case NotificationType.highRiskDetected:
    case NotificationType.scanSyncedToCloud:
      final scanId = entity.payload['scanId'] as String?;
      if (scanId == null || scanId.isEmpty) return;
      context.pushNamed(
        'scan-detail',
        pathParameters: {'scanId': scanId},
      );
    case NotificationType.passwordChanged:
    case NotificationType.profileEdited:
    case NotificationType.avatarUpdated:
      context.pushNamed('profile');
    case NotificationType.modelUpdateInstalled:
      // No detail surface yet.
      break;
    case NotificationType.reminderCheckup:
      context.pushNamed('reminder');
  }
}

class NotificationRow extends StatelessWidget {
  const NotificationRow({
    super.key,
    required this.entity,
    required this.onTap,
  });

  final NotificationEntity entity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = entity.category.accent;
    final unread = !entity.isRead;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1A44),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: unread
                  ? accent.withValues(alpha: 0.45)
                  : const Color(0x1A4A4455),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(entity.category.icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entity.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              height: 1.3,
                              color: Color(0xFFE2DFFF),
                            ),
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (entity.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        entity.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w400,
                          fontSize: 12,
                          height: 1.4,
                          color: Color(0xFFCCC3D8),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _CategoryPill(category: entity.category),
                        const SizedBox(width: 8),
                        Text(
                          formatRelativeTime(entity.createdAt),
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                            color: Color(0xFF8B82B5),
                          ),
                        ),
                      ],
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

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.category});
  final NotificationCategory category;

  @override
  Widget build(BuildContext context) {
    final accent = category.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        category.label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 9,
          letterSpacing: 0.4,
          color: accent,
        ),
      ),
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
                Icons.notifications_none_rounded,
                size: 28,
                color: AppColors.violeta,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No notifications yet'.tr,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: AppColors.violetaClaro,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              ('Activity from your scans, account changes and OTA updates '
              'will appear here.').tr,
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

/// Compact relative time formatter — shared between the list and the
/// banner. Falls back to an absolute month-day label for anything older
/// than a week so the bottom of the list doesn't collapse to "30d ago".
String formatRelativeTime(DateTime at) {
  final now = DateTime.now();
  final diff = now.difference(at);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  const months = [
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
  return '${months[at.month - 1]} ${at.day}';
}
