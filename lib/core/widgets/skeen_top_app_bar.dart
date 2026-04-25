import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';

/// Reusable frosted-glass top app bar.
///
/// Matches Figma `Header - TopAppBar` (154:1026): translucent indigo with a
/// 6 px blur, leading back button, centered title. Used on every screen that
/// is reachable via push/pop (Profile, Body Map, Reminder, sub-settings, …).
///
/// The widget implements [PreferredSizeWidget] so it can drop into a
/// `Scaffold(appBar:)`, but it is also fine to embed directly in a column
/// when a custom layout is needed.
class SkeenTopAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SkeenTopAppBar({
    super.key,
    required this.title,
    this.onBack,
    this.actions = const [],
    this.showBack = true,
  });

  final String title;

  /// Override for the back action. When `null`, falls back to `context.pop()`
  /// or `context.goNamed('home')` if the navigator stack cannot pop.
  final VoidCallback? onBack;

  /// Trailing widgets (e.g. an "edit" icon). Rendered in the order given.
  final List<Widget> actions;

  final bool showBack;

  static const double _height = 64;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            color: const Color(0x9936345F),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (showBack)
                  _BackButton(onPressed: () => _handleBack(context))
                else
                  const SizedBox(width: 40),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 20,
                      height: 1.4,
                      letterSpacing: -0.5,
                      color: Color(0xFF8B76E1),
                    ),
                  ),
                ),
                if (actions.isEmpty)
                  const SizedBox(width: 40)
                else
                  Row(mainAxisSize: MainAxisSize.min, children: actions),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleBack(BuildContext context) {
    if (onBack != null) {
      onBack!();
      return;
    }
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.goNamed('home');
    }
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: SvgPicture.asset(
              'assets/images/profile/back_arrow.svg',
              width: 16,
              height: 16,
              colorFilter: const ColorFilter.mode(
                AppColors.violetaClaro,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
