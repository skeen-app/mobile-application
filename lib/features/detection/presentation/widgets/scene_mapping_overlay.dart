import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/capture_quality.dart';

/// Pre-diagnosis "scene mapping" overlay shown above the AR view.
///
/// Mirrors the Pokémon-GO capture intro: the user is asked to slowly move
/// the phone over the area while ARCore / ARKit detects planes and the
/// readiness gate (lighting + focus + distance) stabilizes. While that
/// happens, contextual popups float in to coach the user.
///
/// The overlay disappears once the parent screen calls
/// `DetectionController.completeMapping()` — typically when tracking is OK
/// AND the readiness gate has passed for ~1 s.
class SceneMappingOverlay extends StatefulWidget {
  const SceneMappingOverlay({
    super.key,
    required this.readiness,
    required this.elapsedMs,
  });

  final CaptureReadiness readiness;
  final int elapsedMs;

  @override
  State<SceneMappingOverlay> createState() => _SceneMappingOverlayState();
}

class _SceneMappingOverlayState extends State<SceneMappingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// Selects the highest-priority hint to surface.
  _Hint _selectHint() {
    final r = widget.readiness;
    if (!r.lighting.canCapture) {
      return const _Hint(
        icon: Icons.wb_sunny_outlined,
        message: 'Find better light',
        accent: Color(0xFFFFC857),
      );
    }
    if (!r.distance) {
      return const _Hint(
        icon: Icons.center_focus_strong_outlined,
        message: 'Bring camera closer · ~15 cm',
        accent: AppColors.violetaClaro,
      );
    }
    if (!r.focus) {
      return const _Hint(
        icon: Icons.filter_center_focus_outlined,
        message: 'Hold steady — focusing',
        accent: AppColors.violetaClaro,
      );
    }
    if (!r.isStable) {
      return const _Hint(
        icon: Icons.front_hand_outlined,
        message: 'Hold the phone steady',
        accent: AppColors.violetaClaro,
      );
    }
    return const _Hint(
      icon: Icons.adjust,
      message: 'Center the mole in the ring',
      accent: Color(0xFF7BE38C),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hint = _selectHint();
    return IgnorePointer(
      child: Stack(
        children: [
          // Subtle vignette
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.1,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.45),
                ],
              ),
            ),
            child: const SizedBox.expand(),
          ),
          // Top-center: mapping status
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(child: _MappingStatusChip(elapsed: widget.elapsedMs)),
          ),
          // Pulsing reticle ring (guidance to "look around")
          Center(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, _) {
                final t = _pulse.value;
                final size = 180 + 24 * math.sin(t * math.pi * 2);
                return Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: hint.accent.withValues(alpha: 0.55),
                      width: 2,
                    ),
                  ),
                );
              },
            ),
          ),
          // Floating hint card just above the reticle
          Align(
            alignment: const Alignment(0, -0.32),
            child: _FloatingHintCard(hint: hint),
          ),
          // Bottom: ARCore/ARKit attribution + nudge
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Slowly move the phone to map the skin surface',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  letterSpacing: -0.1,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint {
  const _Hint({
    required this.icon,
    required this.message,
    required this.accent,
  });
  final IconData icon;
  final String message;
  final Color accent;
}

class _FloatingHintCard extends StatelessWidget {
  const _FloatingHintCard({required this.hint});
  final _Hint hint;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: anim, child: child),
      ),
      child: Container(
        key: ValueKey(hint.message),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          border: Border.all(color: hint.accent.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: hint.accent.withValues(alpha: 0.25),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(hint.icon, color: hint.accent, size: 18),
            const SizedBox(width: 8),
            Text(
              hint.message,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                letterSpacing: -0.1,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MappingStatusChip extends StatelessWidget {
  const _MappingStatusChip({required this.elapsed});
  final int elapsed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.indigo.withValues(alpha: 0.85),
        border: Border.all(color: AppColors.violetaOscuro),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.violetaClaro),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Mapping skin · ${(elapsed / 1000).toStringAsFixed(1)}s',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 11,
              letterSpacing: 0.2,
              color: AppColors.violetaClaro,
            ),
          ),
        ],
      ),
    );
  }
}
