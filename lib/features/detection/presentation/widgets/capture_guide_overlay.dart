import 'package:skeen/core/localization/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../../../core/theme/app_colors.dart';
import '../../application/hint_arbiter.dart';
import '../../domain/capture_quality.dart';
import '../../domain/capture_scale.dart';

/// Capture-time overlay. Now a blocking gate rather than a readout.
///
/// Layout:
///   • Centre frame: corner brackets around the guide box. Switches to
///     brand-violet with a glow the moment every check passes — the single
///     "you may shoot" signal.
///   • One coaching line, arbitrated by [HintArbiter] so that with six live
///     signals the message does not strobe. Reused from the scene-mapping
///     overlay, which already had this right.
///   • A compact status row: passing signals collapse to a bare icon,
///     the failing one keeps its label. Keeps six signals legible on a
///     narrow screen without hiding any of them.
///   • Auto-capture progress ring, so the shutter never fires unannounced.
class CaptureGuideOverlay extends StatefulWidget {
  const CaptureGuideOverlay({
    super.key,
    required this.readiness,
    required this.boxSide,
    this.autoCaptureProgress = 0,
  });

  final CaptureReadiness readiness;

  /// Side of the guide square, resolved by the screen so that the box drawn
  /// here and the ROI the metrics are measured over cannot diverge.
  final double boxSide;

  /// 0–1 progress of the auto-capture dwell. 0 when not counting down.
  final double autoCaptureProgress;

  @override
  State<CaptureGuideOverlay> createState() => _CaptureGuideOverlayState();
}

class _CaptureGuideOverlayState extends State<CaptureGuideOverlay> {
  /// Coaching order. It is a sequence the user can actually follow: get light
  /// on the lesion, kill the reflection, frame it, hold still, let it focus,
  /// then worry about colour. Anything earlier in this list pre-empts
  /// immediately; anything later has to wait out the settle window.
  static const List<String> _priority = [
    'lighting',
    'glare',
    'scale',
    'stability',
    'focus',
    'color',
    'ready',
  ];

  late final HintArbiter _arbiter = HintArbiter(
    priority: _priority,
    resolvedKey: 'ready',
    initial: 'lighting',
  );

  bool? _previousReady;
  DateTime _lastUpdate = DateTime.now();

  @override
  void didUpdateWidget(covariant CaptureGuideOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    final now = DateTime.now();
    _arbiter.update(
      failing: _failingKey(widget.readiness),
      dtMs: now.difference(_lastUpdate).inMilliseconds,
    );
    _lastUpdate = now;

    final wasReady = _previousReady;
    final isReady = widget.readiness.isReady;
    if (wasReady == false && isReady) {
      // Soft haptic on the false → true edge so the user feels the green
      // light without looking away from the lesion.
      HapticFeedback.lightImpact();
    }
    _previousReady = isReady;
  }

  /// Highest-priority failing signal, or null when everything passes.
  ///
  /// Surfaces that do not measure the full vector (`gatingSignals == false`,
  /// i.e. the AR screen) only ever coach on what they actually measure.
  static String? _failingKey(CaptureReadiness r) {
    if (!r.lighting.canCapture) return 'lighting';
    if (r.gatingSignals) {
      if (!r.glareOk) return 'glare';
      if (!r.scale.isAcceptable) return 'scale';
      if (!r.stability.isSteady) return 'stability';
    }
    if (!r.focus) return 'focus';
    if (r.gatingSignals && !r.colorNeutral) return 'color';
    return null;
  }

  _Hint _hintFor(String key, CaptureReadiness r) {
    switch (key) {
      case 'lighting':
        return _Hint(
          icon: Icons.wb_sunny_outlined,
          message: r.lighting.brightness < 55
              ? 'Find more light'.tr
              : r.lighting.brightness > 225
                  ? 'Reduce direct light'.tr
                  : 'Adjust lighting'.tr,
          accent: const Color(0xFFFFC857),
        );
      case 'glare':
        return _Hint(
          icon: Icons.flare_outlined,
          message: 'Glare on the skin — tilt away or turn the flash off'.tr,
          accent: const Color(0xFFFFC857),
        );
      case 'scale':
        return _Hint(
          icon: switch (r.scale.advice) {
            ScaleAdvice.moveAway => Icons.zoom_out_map,
            ScaleAdvice.tooCloseToFocus => Icons.zoom_out_map,
            _ => Icons.center_focus_strong_outlined,
          },
          // No centimetres anywhere: nothing on this path measures distance.
          // What the user is told is what is actually measured — how much of
          // the box the lesion fills.
          message: switch (r.scale.advice) {
            ScaleAdvice.moveCloser =>
              'Move closer until the mole fills the box'.tr,
            ScaleAdvice.moveAway =>
              'Move back — the mole overflows the box'.tr,
            ScaleAdvice.tooCloseToFocus =>
              'Too close to focus — move back a little'.tr,
            ScaleAdvice.unknown => 'Point the camera at the mole'.tr,
            ScaleAdvice.ok => 'Framing looks good'.tr,
          },
          accent: AppColors.violetaClaro,
        );
      case 'stability':
        return _Hint(
          icon: Icons.vibration,
          message: 'Hold the phone still'.tr,
          accent: AppColors.violetaClaro,
        );
      case 'focus':
        return _Hint(
          icon: Icons.filter_center_focus_outlined,
          message: 'Hold steady — focusing'.tr,
          accent: AppColors.violetaClaro,
        );
      case 'color':
        return _Hint(
          icon: Icons.color_lens_outlined,
          message: 'Move to more neutral light — daylight works best'.tr,
          accent: const Color(0xFFFFC857),
        );
      case 'ready':
      default:
        return _Hint(
          icon: Icons.check_circle_outline,
          message: 'Hold still — capturing'.tr,
          accent: const Color(0xFF7BE38C),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.readiness;
    final ready = r.isReady;
    final hint = _hintFor(_arbiter.active, r);

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Centre frame ────────────────────────────────────────────
          Center(
            child: SizedBox(
              width: widget.boxSide,
              height: widget.boxSide,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: ready
                          ? [
                              BoxShadow(
                                color:
                                    AppColors.violeta.withValues(alpha: 0.35),
                                blurRadius: 24,
                                spreadRadius: -2,
                              ),
                            ]
                          : const [],
                    ),
                    child: CustomPaint(
                      painter: _CornerBracketsPainter(
                        color: ready
                            ? AppColors.violeta
                            : Colors.white.withValues(alpha: 0.55),
                        stroke: ready ? 3.0 : 2.0,
                        bracketLength: 28,
                        radius: 28,
                      ),
                    ),
                  ),
                  if (widget.autoCaptureProgress > 0)
                    CustomPaint(
                      painter: _AutoCaptureRingPainter(
                        progress: widget.autoCaptureProgress,
                        color: const Color(0xFF7BE38C),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Coaching line ───────────────────────────────────────────
          Align(
            alignment: const Alignment(0, 0.62),
            child: _CoachLabel(hint: hint),
          ),

          // ── Status row ──────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Only measured signals get a chip. A surface that
                    // cannot measure glare must not show a green glare chip.
                    _SignalChip(
                      icon: Icons.wb_sunny_outlined,
                      label: 'Light'.tr,
                      ok: r.lighting.canCapture,
                    ),
                    if (r.gatingSignals) ...[
                      _SignalChip(
                        icon: Icons.flare_outlined,
                        label: 'Glare'.tr,
                        ok: r.glareOk,
                      ),
                      _SignalChip(
                        icon: Icons.center_focus_strong_outlined,
                        label: 'Framing'.tr,
                        ok: r.scale.isAcceptable,
                      ),
                      _SignalChip(
                        icon: Icons.vibration,
                        label: 'Steady'.tr,
                        ok: r.stability.isSteady,
                      ),
                    ],
                    _SignalChip(
                      icon: Icons.filter_center_focus_outlined,
                      label: 'Focus'.tr,
                      ok: r.focus,
                    ),
                    if (r.gatingSignals)
                      _SignalChip(
                        icon: Icons.color_lens_outlined,
                        label: 'Colour'.tr,
                        ok: r.colorNeutral,
                      ),
                  ],
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

/// Passing signals collapse to a bare icon; a failing one expands to show its
/// label. Six signals stay readable on a narrow screen, and the eye is drawn
/// to whichever one is actually blocking the shutter.
class _SignalChip extends StatelessWidget {
  const _SignalChip({
    required this.icon,
    required this.label,
    required this.ok,
  });

  final IconData icon;
  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final accent = ok ? AppColors.violeta : AppColors.naranja;
    final fg = ok ? Colors.white : AppColors.naranja;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: ok ? 7 : 10, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: ok ? 0.22 : 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: accent.withValues(alpha: ok ? 0.55 : 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            if (!ok) ...[
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: -0.1,
                  color: AppColors.naranja,
                ),
              ),
            ],
          ],
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
        margin: const EdgeInsets.symmetric(horizontal: 16),
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
            Flexible(
              child: Text(
                hint.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  letterSpacing: -0.1,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sweeps the guide box border while the auto-capture dwell counts down, so
/// the shutter never fires without warning.
class _AutoCaptureRingPainter extends CustomPainter {
  _AutoCaptureRingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(28),
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()..addRRect(rect);
    final metrics = path.computeMetrics().toList();
    for (final metric in metrics) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AutoCaptureRingPainter old) =>
      old.progress != progress || old.color != color;
}

/// Draws four L-shaped brackets in the corners of the available box,
/// rounded inward at [radius]. Explicitly NOT a full rectangle so the lesion
/// stays visible without a heavy outline over it.
class _CornerBracketsPainter extends CustomPainter {
  _CornerBracketsPainter({
    required this.color,
    required this.stroke,
    required this.bracketLength,
    required this.radius,
  });

  final Color color;
  final double stroke;
  final double bracketLength;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final r = radius;
    final b = bracketLength;

    // Top-left
    _drawCorner(canvas, paint, const Offset(0, 0), Offset(0, r), Offset(r, 0),
        b, true, true);
    // Top-right
    _drawCorner(canvas, paint, Offset(w, 0), Offset(w, r), Offset(w - r, 0), b,
        false, true);
    // Bottom-left
    _drawCorner(canvas, paint, Offset(0, h), Offset(0, h - r), Offset(r, h), b,
        true, false);
    // Bottom-right
    _drawCorner(canvas, paint, Offset(w, h), Offset(w, h - r),
        Offset(w - r, h), b, false, false);
  }

  void _drawCorner(
    Canvas canvas,
    Paint paint,
    Offset corner,
    Offset arcStart,
    Offset arcEnd,
    double bracketLen,
    bool isLeft,
    bool isTop,
  ) {
    final vEnd = Offset(
      arcStart.dx,
      arcStart.dy + (isTop ? bracketLen : -bracketLen),
    );
    final hEnd = Offset(
      arcEnd.dx + (isLeft ? bracketLen : -bracketLen),
      arcEnd.dy,
    );

    final rect = Rect.fromCircle(
      center: Offset(
        isLeft ? radius : (corner.dx - radius),
        isTop ? radius : (corner.dy - radius),
      ),
      radius: radius,
    );
    double startAngle;
    if (isLeft && isTop) {
      startAngle = 3.1416; // π
    } else if (!isLeft && isTop) {
      startAngle = -1.5708; // -π/2
    } else if (isLeft && !isTop) {
      startAngle = 1.5708; // π/2
    } else {
      startAngle = 0;
    }

    canvas.drawArc(rect, startAngle, 1.5708, false, paint);
    canvas.drawLine(arcStart, vEnd, paint);
    canvas.drawLine(arcEnd, hEnd, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketsPainter old) =>
      old.color != color ||
      old.stroke != stroke ||
      old.bracketLength != bracketLength ||
      old.radius != radius;
}
