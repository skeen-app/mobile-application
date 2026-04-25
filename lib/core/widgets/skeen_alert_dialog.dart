import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'skeen_button.dart';

enum SkeenAlertVariant { error, success, info }

/// Modern animated alert dialog used across the app for both error feedback
/// (e.g. failed register/login requests) and confirmations.
///
/// Visuals:
///  - Backdrop blur scrim over the existing screen
///  - Card scales+fades in (180ms ease-out), out (140ms ease-in)
///  - Halo icon at the top whose color follows the chosen variant
class SkeenAlertDialog {
  const SkeenAlertDialog._();

  static Future<void> showError(
    BuildContext context, {
    required String title,
    required String message,
    String dismissLabel = 'Got it',
  }) {
    return _show(
      context,
      title: title,
      message: message,
      dismissLabel: dismissLabel,
      variant: SkeenAlertVariant.error,
    );
  }

  static Future<void> showSuccess(
    BuildContext context, {
    required String title,
    required String message,
    String dismissLabel = 'Continue',
  }) {
    return _show(
      context,
      title: title,
      message: message,
      dismissLabel: dismissLabel,
      variant: SkeenAlertVariant.success,
    );
  }

  static Future<void> showInfo(
    BuildContext context, {
    required String title,
    required String message,
    String dismissLabel = 'Got it',
  }) {
    return _show(
      context,
      title: title,
      message: message,
      dismissLabel: dismissLabel,
      variant: SkeenAlertVariant.info,
    );
  }

  static Future<void> _show(
    BuildContext context, {
    required String title,
    required String message,
    required String dismissLabel,
    required SkeenAlertVariant variant,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss alert',
      barrierColor: const Color(0x99070626),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, _) {
        return _SkeenAlertContent(
          title: title,
          message: message,
          dismissLabel: dismissLabel,
          variant: variant,
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 8 * curved.value,
              sigmaY: 8 * curved.value,
            ),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.85, end: 1.0).animate(curved),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _SkeenAlertContent extends StatelessWidget {
  const _SkeenAlertContent({
    required this.title,
    required this.message,
    required this.dismissLabel,
    required this.variant,
  });

  final String title;
  final String message;
  final String dismissLabel;
  final SkeenAlertVariant variant;

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor(variant);
    final icon = _icon(variant);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              decoration: BoxDecoration(
                color: const Color(0xFF1B1654),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.indigoClaro, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.20),
                    blurRadius: 32,
                    spreadRadius: 2,
                  ),
                  const BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 40,
                    offset: Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Halo(color: accent, icon: icon),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: AppColors.violetaClaro,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      height: 1.5,
                      letterSpacing: -0.14,
                      color: AppColors.hintText,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SkeenButton.primary(
                    label: dismissLabel,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _accentColor(SkeenAlertVariant v) {
    switch (v) {
      case SkeenAlertVariant.error:
        return AppColors.fucsia;
      case SkeenAlertVariant.success:
        return AppColors.turquesa;
      case SkeenAlertVariant.info:
        return AppColors.violetaLink;
    }
  }

  IconData _icon(SkeenAlertVariant v) {
    switch (v) {
      case SkeenAlertVariant.error:
        return Icons.error_outline;
      case SkeenAlertVariant.success:
        return Icons.check_circle_outline;
      case SkeenAlertVariant.info:
        return Icons.info_outline;
    }
  }
}

class _Halo extends StatefulWidget {
  const _Halo({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  State<_Halo> createState() => _HaloState();
}

class _HaloState extends State<_Halo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final pulse = 0.6 + 0.4 * t;
        return SizedBox(
          width: 76,
          height: 76,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 60 + 12 * pulse,
                height: 60 + 12 * pulse,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.10 + 0.10 * (1 - t)),
                ),
              ),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.18),
                  border: Border.all(
                    color: widget.color.withValues(alpha: 0.55),
                    width: 1.4,
                  ),
                ),
                child: Icon(widget.icon, color: widget.color, size: 28),
              ),
            ],
          ),
        );
      },
    );
  }
}
