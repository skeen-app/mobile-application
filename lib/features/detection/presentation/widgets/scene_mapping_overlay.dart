import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../application/hint_arbiter.dart';
import '../../domain/capture_quality.dart';

/// Pre-diagnosis "scene mapping" overlay shown above the AR view.
///
/// Visually minimal: ONE subtle pulsing ring at the center, ONE coaching
/// label that swaps with priority-based hysteresis (1.5 s settle time, or
/// instant when a higher-priority issue surfaces). Mirrors Pokémon-GO's
/// calm capture intro.
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
      AnimationController(vsync: this, duration: const Duration(seconds: 3))
        ..repeat();

  /// Priority + hysteresis now lives in [HintArbiter], shared with
  /// [CaptureGuideOverlay]. The behaviour is unchanged; it moved out so the
  /// capture-time gate could reuse it instead of growing a second copy.
  late final HintArbiter _arbiter = HintArbiter(
    priority: const ['lighting', 'focus', 'ready'],
    resolvedKey: 'ready',
    initial: _failingHint(widget.readiness) ?? 'ready',
  );

  int _lastElapsed = 0;

  @override
  void initState() {
    super.initState();
    _lastElapsed = widget.elapsedMs;
  }

  @override
  void didUpdateWidget(covariant SceneMappingOverlay old) {
    super.didUpdateWidget(old);
    final dt = widget.elapsedMs - _lastElapsed;
    _lastElapsed = widget.elapsedMs;
    _arbiter.update(failing: _failingHint(widget.readiness), dtMs: dt);
  }

  /// The AR surface measures only lighting and tracking — it has no image
  /// stream to derive glare, colour cast, shake or lesion scale from, so it
  /// coaches on what it actually knows. The old "distance" hint is gone: it
  /// was driven by ARCore Depth, which does not resolve at macro range.
  String? _failingHint(CaptureReadiness r) {
    if (!r.lighting.canCapture) return 'lighting';
    if (!r.focus) return 'focus';
    return null;
  }

  _Hint _hintFor(String key, CaptureReadiness r) {
    switch (key) {
      case 'lighting':
        return _Hint(
          icon: Icons.wb_sunny_outlined,
          message: r.lighting.brightness < 55
              ? 'Find more light'
              : r.lighting.brightness > 225
                  ? 'Reduce direct light'
                  : 'Adjust lighting',
          accent: const Color(0xFFFFC857),
        );
      case 'focus':
        return const _Hint(
          icon: Icons.filter_center_focus_outlined,
          message: 'Hold steady — mapping the surface',
          accent: AppColors.violetaClaro,
        );
      case 'ready':
      default:
        return const _Hint(
          icon: Icons.adjust,
          message: 'Center the mole in the ring',
          accent: Color(0xFF7BE38C),
        );
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hint = _hintFor(_arbiter.active, widget.readiness);
    return IgnorePointer(
      child: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.35),
                ],
              ),
            ),
            child: const SizedBox.expand(),
          ),
          Center(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, _) => _SinglePulseRing(
                t: _pulse.value,
                color: hint.accent,
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.55),
            child: _CoachLabel(hint: hint),
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

/// One subtle ring that breathes once per pulse cycle. No nested rings.
class _SinglePulseRing extends StatelessWidget {
  const _SinglePulseRing({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // 0 → 1 over 3s. Use a smooth ease for a calmer feel.
    final eased = Curves.easeInOut.transform(t);
    final size = 170 + 14 * eased;
    final alpha = (0.35 + 0.25 * (1 - (eased - 0.5).abs() * 2)).clamp(0.15, 0.6);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: alpha),
          width: 1.6,
        ),
      ),
    );
  }
}

class _CoachLabel extends StatelessWidget {
  const _CoachLabel({required this.hint});
  final _Hint hint;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey(hint.message),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          border: Border.all(color: hint.accent.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(14),
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
