import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_colors.dart';

/// Top-of-home greeting strip: time-aware salutation + first name of the
/// signed-in user, alongside the notification bell.
///
/// Falls back to a name-less salutation when the auth state has no `user`
/// (e.g. fresh hydration before profile lookup completes).
class HomeGreeting extends StatelessWidget {
  const HomeGreeting({
    super.key,
    required this.firstName,
    required this.hasNotifications,
    required this.onNotificationsTap,
  });

  /// First name pulled from the session user. Pass `null` to render the
  /// salutation alone.
  final String? firstName;

  final bool hasNotifications;
  final VoidCallback onNotificationsTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_greeting()},',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  height: 1.0,
                  letterSpacing: -0.16,
                  color: Color(0xFF8B76E1),
                ),
              ),
              if (firstName != null && firstName!.trim().isNotEmpty)
                Text(
                  firstName!.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                    height: 1.5,
                    letterSpacing: -0.2,
                    color: AppColors.violetaClaro,
                  ),
                ),
            ],
          ),
        ),
        _NotificationBell(
          hasUnread: hasNotifications,
          onTap: onNotificationsTap,
        ),
      ],
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 19) return 'Good afternoon';
    return 'Good evening';
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.hasUnread, required this.onTap});

  final bool hasUnread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A113F),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          width: 41,
          height: 41,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFF3A1E74)),
          ),
          child: Stack(
            children: [
              Center(
                child: SvgPicture.asset(
                  'assets/images/notifications_icon.svg',
                  width: 20,
                  height: 20,
                  colorFilter: const ColorFilter.mode(
                    AppColors.violetaClaro,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              if (hasUnread)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.naranja,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
