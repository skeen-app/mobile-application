import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import 'notification_entity.dart';
import 'notifications_controller.dart';
import 'notifications_screen.dart';

/// Listens to the controller's banner stream and slides a card down from
/// the top of the screen for ~4 s when a new notification is recorded.
///
/// Mounted once via `MaterialApp.builder`, so every route inherits it.
/// Suppressed when the user is already on the notifications list (the
/// list highlights the new row instead).
class InAppNotificationBannerHost extends ConsumerStatefulWidget {
  const InAppNotificationBannerHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<InAppNotificationBannerHost> createState() =>
      _InAppNotificationBannerHostState();
}

class _InAppNotificationBannerHostState
    extends ConsumerState<InAppNotificationBannerHost> {
  StreamSubscription<NotificationEntity>? _sub;
  OverlayEntry? _entry;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    final controller = ref.read(notificationsControllerProvider.notifier);
    _sub = controller.bannerStream.listen(_onNotification);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _autoDismissTimer?.cancel();
    _removeBanner();
    super.dispose();
  }

  void _onNotification(NotificationEntity entity) {
    if (InAppBannerSuppressor.instance.isSuppressed) return;
    _showBanner(entity);
  }

  void _showBanner(NotificationEntity entity) {
    _removeBanner();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (ctx) => _BannerCard(
        entity: entity,
        onTap: () {
          _removeBanner();
          // Push the notifications screen on top of whatever route the
          // user is on. We don't `goNamed` so the back button returns
          // them to where they were.
          GoRouter.of(context).pushNamed('notifications');
        },
        onDismiss: _removeBanner,
      ),
    );

    overlay.insert(entry);
    _entry = entry;
    _autoDismissTimer = Timer(const Duration(seconds: 4), _removeBanner);
  }

  void _removeBanner() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _BannerCard extends StatefulWidget {
  const _BannerCard({
    required this.entity,
    required this.onTap,
    required this.onDismiss,
  });

  final NotificationEntity entity;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  State<_BannerCard> createState() => _BannerCardState();
}

class _BannerCardState extends State<_BannerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final entity = widget.entity;
    final accent = entity.category.accent;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Align(
          alignment: Alignment.topCenter,
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _fade,
              child: Material(
                color: Colors.transparent,
                child: Dismissible(
                  key: ValueKey('banner-${entity.id}'),
                  direction: DismissDirection.up,
                  onDismissed: (_) => widget.onDismiss(),
                  child: GestureDetector(
                    onTap: () async {
                      await _ctrl.reverse();
                      widget.onTap();
                    },
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1A44),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.45),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                          BoxShadow(
                            color: accent.withValues(alpha: 0.18),
                            blurRadius: 22,
                            spreadRadius: -2,
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(
                              entity.category.icon,
                              color: accent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entity.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: AppColors.violetaClaro,
                                  ),
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
                                      fontSize: 11.5,
                                      height: 1.4,
                                      color: Color(0xFFCCC3D8),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Color(0xFF8B82B5),
                            ),
                            onPressed: _dismiss,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
