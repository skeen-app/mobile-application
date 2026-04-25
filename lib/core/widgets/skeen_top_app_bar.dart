import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

/// Reusable top app bar matching Figma `Header - TopAppBar` (155:1060).
///
/// Layout (left → right):
///   • 40 × 40 rounded-square button (#9057F0, radius 9) with white back arrow
///   • Column: [title] Poppins SemiBold 16 px · #F5F5F5
///             [subtitle] Poppins Medium 11 px · rgba(237,233,254,0.53)
///   • Animated constellation decoration floating on the right
///
/// Background is transparent so the screen-level `SkeenStarField` shows
/// through.
///
/// The widget implements [PreferredSizeWidget] so it can drop into a
/// `Scaffold(appBar:)`, but it is also fine to embed directly in a column
/// when a custom layout is needed.
class SkeenTopAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SkeenTopAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
    this.showBack = true,
  });

  final String title;

  /// Optional subtitle rendered below the title.
  /// When `null`, only the title row is shown.
  final String? subtitle;

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
      child: Stack(
        children: [
          // ── Foreground row ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Back button
                if (showBack)
                  _BackButton(onPressed: () => _handleBack(context))
                else
                  const SizedBox(width: 40),

                const SizedBox(width: 12),

                // Title + subtitle column
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          height: 1.5,
                          letterSpacing: -0.16,
                          color: Color(0xFFF5F5F5),
                        ),
                      ),
                      if (subtitle != null) ...[
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                            height: 1.5,
                            letterSpacing: -0.11,
                            color: Color(0x87EDE9FE), // rgba(237,233,254,0.53)
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Trailing actions
                if (actions.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: actions),
              ],
            ),
          ),
        ],
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
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onPressed,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF9057F0),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Center(
            child: SvgPicture.asset(
              'assets/images/profile/back_arrow.svg',
              width: 16,
              height: 16,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
