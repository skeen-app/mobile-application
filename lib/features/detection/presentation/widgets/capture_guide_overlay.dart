import 'package:skeen/core/localization/locale_controller.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../../../core/theme/app_colors.dart';
import '../../application/hint_arbiter.dart';
import '../../domain/capture_quality.dart';
import '../../domain/capture_scale.dart';
import '../../domain/capture_standard.dart';
import '../../domain/display_mapping.dart';
import '../../domain/lesion_anchor.dart';
import '../../domain/roi_frame_metrics.dart';
import '../../domain/skin_plane_pose.dart';

/// Capture-time overlay. A blocking gate, and — from WP-2 — spatial rather
/// than textual wherever a signal has a place on screen.
///
/// Layout:
///   • Guide box: faint corner brackets marking the analysed region.
///   • **Lesion reticle** (WP-2d): a ring sitting on the segmented lesion,
///     sized to it, smoothed and carried by the gyroscope between
///     measurements. Colour says framing: green when the lesion fills the
///     box well, orange when the user should move closer or back. Replaces
///     the "move closer / move back" text.
///   • **Glare shading** (WP-2c): the clipped cells painted where the
///     reflection actually is, with an arrow from the highlight away from
///     the lesion — the direction to tilt. Replaces "adjust lighting".
///   • One coaching line for what has no spatial form (light, shake,
///     focus, colour), arbitrated by [HintArbiter] so it does not strobe.
///   • A compact status row: passing signals collapse to a bare icon, the
///     failing one keeps its label.
///   • Auto-capture progress ring, so the shutter never fires unannounced.
///
/// Every spatial element goes through [roiToDisplay], so the sensor→screen
/// rotation is decided in exactly one place.
class CaptureGuideOverlay extends StatefulWidget {
  const CaptureGuideOverlay({
    super.key,
    required this.readiness,
    required this.boxSide,
    this.autoCaptureProgress = 0,
    this.sensorOrientationDegrees = 90,
    this.streamFrameSize,
  });

  final CaptureReadiness readiness;

  /// Camera sensor mounting, for mapping stream coordinates to the screen.
  final int sensorOrientationDegrees;

  /// Size of the camera stream in sensor orientation. Needed to place the
  /// plane-registered elements (WP-2a/2b), which live in full-frame pixels.
  final Size? streamFrameSize;

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
  late final HintArbiter _arbiter = HintArbiter(
    priority: CaptureReadiness.coachingPriority,
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
      failing: widget.readiness.failingKey,
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
      case 'marker':
        return _Hint(
          icon: Icons.qr_code_2_outlined,
          message: 'Show the marker card next to the mole'.tr,
          accent: AppColors.violetaClaro,
        );
      case 'glare':
        return _Hint(
          icon: Icons.flare_outlined,
          message: 'Glare on the skin — tilt away or turn the flash off'.tr,
          accent: const Color(0xFFFFC857),
        );
      case 'tilt':
        return _Hint(
          icon: Icons.screen_rotation_alt_outlined,
          message: 'Level the phone until the ring closes'.tr,
          accent: AppColors.violetaClaro,
        );
      case 'centre':
        return _Hint(
          icon: Icons.center_focus_strong_outlined,
          message: 'Centre the mole in the disc'.tr,
          accent: AppColors.violetaClaro,
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

  /// Signals that are drawn where they are rather than described: the
  /// glare shading, the disc's size and colour, the nadir cue, the reticle.
  static const Set<String> _spatialKeys = {'glare', 'scale', 'tilt', 'centre'};

  @override
  Widget build(BuildContext context) {
    final r = widget.readiness;
    final ready = r.isReady;
    final active = _arbiter.active;
    final hint = _hintFor(active, r);
    final orientation = widget.sensorOrientationDegrees;

    final pose = r.pose;
    final stream = widget.streamFrameSize;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Plane-registered elements (WP-2a/2b) ────────────────────
          // Drawn over the whole preview: the disc is where the skin is,
          // not where the guide box is. It appears only with a live pose.
          if (r.gatingSignals && pose != null && stream != null)
            CustomPaint(
              painter: _PlanePainter(
                pose: pose,
                streamSize: stream,
                orientation: orientation,
                boxSide: widget.boxSide,
              ),
            ),

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
                  // ── Glare, where it is (WP-2c) ─────────────────────
                  if (r.gatingSignals)
                    CustomPaint(
                      painter: _GlarePainter(
                        metrics: r.metrics,
                        lesionCentre: r.anchor?.centre,
                        orientation: orientation,
                        emphasise: active == 'glare',
                      ),
                    ),
                  // ── Lesion reticle (WP-2d) ─────────────────────────
                  if (r.gatingSignals && r.anchor != null)
                    CustomPaint(
                      painter: _ReticlePainter(
                        anchor: r.anchor!,
                        // With a pose the ring reports centring on the disc;
                        // without one, the fill-based advice.
                        advice: r.poseReadiness.hasPose
                            ? (r.poseReadiness.centredOk
                                ? ScaleAdvice.ok
                                : ScaleAdvice.unknown)
                            : r.scale.advice,
                        orientation: orientation,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Coaching line — only for what has no place on screen ────
          if (!_spatialKeys.contains(active))
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

/// The target disc on the skin plane and the nadir cue above it.
///
/// This is the element that makes the guidance AR in the strict sense: it is
/// a fixed spot on the skin, projected through the measured pose. It
/// stretches into an ellipse as the phone tilts, grows as the phone comes
/// closer, and stays put on the skin as the phone moves. One object answers
/// framing, scale and angle at once:
///
///   • **Scale** — the disc is [kRoiSideMm] across on the skin. At the target
///     px/mm its projection is exactly the guide box's size, so "make the
///     disc fill the box" *is* the scale gate; the colour says whether it is
///     within ±[kScaleTolerance].
///   • **Angle** — a point [TargetDisc.nadirHeightMm] above the disc centre
///     projects onto the centre exactly when the disc is viewed along its
///     normal (local tilt zero) and drifts off it otherwise. The ring at
///     that point closes onto the centre dot when the disc is head-on;
///     colour by [kMaxTiltDeg] on the local tilt.
///   • **Framing** — the lesion goes inside the disc (the protocol places
///     the card so that it does).
class _PlanePainter extends CustomPainter {
  _PlanePainter({
    required this.pose,
    required this.streamSize,
    required this.orientation,
    required this.boxSide,
  });

  final SkinPlanePose pose;
  final Size streamSize;
  final int orientation;
  final double boxSide;

  static const Color _good = Color(0xFF7BE38C);

  Offset? _toWidget(Offset? streamPx, Size widget) => streamPx == null
      ? null
      : streamToWidget(streamPx, streamSize, orientation, widget);

  @override
  void paint(Canvas canvas, Size size) {
    final c = TargetDisc.centreMm();
    final radius = TargetDisc.diameterMm / 2;

    // ── Disc: sampled circle in plane mm, projected point by point ────
    const segments = 48;
    final ring = <Offset>[];
    for (var i = 0; i < segments; i++) {
      final a = 2 * math.pi * i / segments;
      final p = _toWidget(
        pose.project(c.dx + radius * math.cos(a), c.dy + radius * math.sin(a)),
        size,
      );
      if (p == null) return; // behind the camera: nothing sensible to draw
      ring.add(p);
    }
    final centre = _toWidget(pose.project(c.dx, c.dy), size);
    if (centre == null) return;

    // Projected extent along the plane's X axis vs. the guide box: this is
    // measured px/mm over target px/mm, the scale gate's own ratio.
    final left = _toWidget(pose.project(c.dx - radius, c.dy), size);
    final right = _toWidget(pose.project(c.dx + radius, c.dy), size);
    final projectedDiameter =
        (left != null && right != null) ? (right - left).distance : 0.0;
    final scaleRatio = boxSide > 0 ? projectedDiameter / boxSide : 0.0;
    final scaleOk = (scaleRatio - 1).abs() <= kScaleTolerance;
    // Local tilt at the disc: what actually foreshortens the lesion, and
    // what the nadir cue below visualises.
    final tiltOk = pose.localTiltDeg(c.dx, c.dy) <= kMaxTiltDeg;
    final predicted = pose.source == PoseSource.predicted;

    final discColor = scaleOk ? _good : AppColors.naranja;
    final path = Path()..moveTo(ring.first.dx, ring.first.dy);
    for (final p in ring.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = discColor.withValues(alpha: 0.10),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = discColor.withValues(alpha: predicted ? 0.65 : 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // ── Nadir cue: a point above the plane, projected ────────────────
    final top = _toWidget(
      pose.project3(c.dx, c.dy, -TargetDisc.nadirHeightMm),
      size,
    );
    if (top == null) return;
    final tiltColor = tiltOk ? _good : AppColors.naranja;
    final offset = (top - centre).distance;

    // Stalk from the disc centre up to the floating point.
    canvas.drawLine(
      centre,
      top,
      Paint()
        ..color = tiltColor.withValues(alpha: 0.8)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    // Centre dot.
    canvas.drawCircle(centre, 4, Paint()..color = tiltColor);
    // Floating ring; when it sits on the dot the phone is level.
    final closed = offset < 4;
    canvas.drawCircle(
      top,
      10,
      Paint()
        ..color = tiltColor
        ..style = closed ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _PlanePainter old) =>
      !identical(old.pose, pose) ||
      old.streamSize != streamSize ||
      old.orientation != orientation ||
      old.boxSide != boxSide;
}

/// Ring on the segmented lesion, sized to it.
///
/// The colour is the framing verdict: it replaces the "move closer / move
/// back" text. A ring that is visibly small inside the box, or spilling out
/// of it, needs no caption. A predicted (gyroscope-carried) position is
/// drawn slightly fainter than a measured one.
class _ReticlePainter extends CustomPainter {
  _ReticlePainter({
    required this.anchor,
    required this.advice,
    required this.orientation,
  });

  final LesionAnchor anchor;
  final ScaleAdvice advice;
  final int orientation;

  /// The ring is never drawn smaller than this, so a distant speck still
  /// gets a visible target rather than a dot.
  static const double minDiameterPx = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final d = roiToDisplay(anchor.centre, orientation);
    final centre = Offset(d.dx * size.width, d.dy * size.height);
    final diameter = (anchor.diameterFraction.clamp(0.0, 1.5) * size.width)
        .clamp(minDiameterPx, size.width * 1.5);

    final color = switch (advice) {
      ScaleAdvice.ok => const Color(0xFF7BE38C),
      ScaleAdvice.unknown => Colors.white,
      _ => AppColors.naranja,
    };
    final alpha = anchor.predicted ? 0.7 : 0.95;

    canvas.drawCircle(
      centre,
      diameter / 2,
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    // Soft fill so the ring reads as "on" the lesion, not around empty skin.
    canvas.drawCircle(
      centre,
      diameter / 2,
      Paint()..color = color.withValues(alpha: 0.10),
    );
    // Direction ticks when the user should change distance: outward when
    // too small (come closer), inward when overflowing (move back).
    if (advice == ScaleAdvice.moveCloser || advice == ScaleAdvice.moveAway) {
      final outward = advice == ScaleAdvice.moveCloser;
      final r0 = diameter / 2;
      final tick = Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 4; i++) {
        final a = i * math.pi / 2 + math.pi / 4;
        final dir = Offset(math.cos(a), math.sin(a));
        final from = centre + dir * (outward ? r0 + 4 : r0 + 16);
        final to = centre + dir * (outward ? r0 + 16 : r0 + 4);
        canvas.drawLine(from, to, tick);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ReticlePainter old) =>
      old.anchor != anchor ||
      old.advice != advice ||
      old.orientation != orientation;
}

/// Shades the clipped cells of the ROI where they are and draws an arrow
/// from the highlight away from the lesion: the direction to tilt so the
/// reflection leaves the lesion. Replaces "adjust lighting".
class _GlarePainter extends CustomPainter {
  _GlarePainter({
    required this.metrics,
    required this.lesionCentre,
    required this.orientation,
    required this.emphasise,
  });

  final RoiFrameMetrics metrics;
  final Offset? lesionCentre;
  final int orientation;

  /// True while glare is the arbiter's active problem: the arrow is drawn.
  /// The shading is always drawn so the user sees a highlight forming
  /// before it grows large enough to close the gate.
  final bool emphasise;

  static const Color _warm = Color(0xFFFFC857);

  @override
  void paint(Canvas canvas, Size size) {
    const n = RoiFrameMetrics.glareGridSize;
    final cells = metrics.glareCells;
    if (cells.length != n * n) return;

    final cellW = size.width / n;
    final cellH = size.height / n;
    final fill = Paint();
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        final f = cells[row * n + col];
        if (f < RoiFrameMetrics.glareCellVisible) continue;
        // Cell centre in stream-ROI space → display space.
        final d = roiToDisplay(
          Offset((col + 0.5) / n, (row + 0.5) / n),
          orientation,
        );
        final rect = Rect.fromCenter(
          center: Offset(d.dx * size.width, d.dy * size.height),
          width: cellW,
          height: cellH,
        );
        fill.color = _warm.withValues(alpha: (0.25 + 0.5 * f).clamp(0.0, 0.75));
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.deflate(0.5), const Radius.circular(3)),
          fill,
        );
      }
    }

    final g = metrics.glareCentroid;
    if (!emphasise || g == null) return;

    // Arrow: from the highlight, away from the lesion (or away from the box
    // centre when no lesion is segmented). Tilting the phone this way moves
    // the reflection off the lesion.
    final from = roiToDisplay(g, orientation);
    final awayFrom = roiToDisplay(lesionCentre ?? const Offset(0.5, 0.5), orientation);
    var dir = from - awayFrom;
    if (dir.distance < 1e-3) dir = const Offset(0, -1);
    dir = dir / dir.distance;

    final start = Offset(from.dx * size.width, from.dy * size.height);
    final len = size.width * 0.22;
    final end = start + dir * len;
    final stroke = Paint()
      ..color = _warm
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(start, end, stroke);
    final perp = Offset(-dir.dy, dir.dx);
    final head = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(end.dx - dir.dx * 10 + perp.dx * 6, end.dy - dir.dy * 10 + perp.dy * 6)
      ..lineTo(end.dx - dir.dx * 10 - perp.dx * 6, end.dy - dir.dy * 10 - perp.dy * 6)
      ..close();
    canvas.drawPath(head, Paint()..color = _warm);
  }

  @override
  bool shouldRepaint(covariant _GlarePainter old) =>
      !identical(old.metrics, metrics) ||
      old.lesionCentre != lesionCentre ||
      old.orientation != orientation ||
      old.emphasise != emphasise;
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
