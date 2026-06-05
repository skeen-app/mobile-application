/// ── Guide-box crop experiment (FASE 2) ──────────────────────────────────
///
/// The classifier was trained on dermatoscopic frames (lesion centered and
/// dominant). The phone camera produces wide frames with lots of background
/// and surrounding skin, so the lesion the user frames in the on-screen guide
/// box only fills a fraction of what reaches the model. This config gates an
/// experiment that crops the captured JPEG to that centered guide region
/// before the cascade runs, narrowing the domain gap.
///
/// All knobs live here so A/B testing is a one-line change + hot restart —
/// no logic path changes. The flag is read in exactly two places:
///   • [DetectionController.captureAndClassify] — applies the crop once to
///     the buffer that feeds BOTH models (skin gate + classifier).
///   • [CaptureGuideOverlay] — sizes the visual box to match the cropped
///     region so "what you frame" stays "what gets analyzed".
library;

/// Master A/B switch. When `false`, the cascade behaves EXACTLY as before the
/// experiment (full standardized capture → models, no extra crop, 220 px
/// visual box). When `true`, only the centered guide region feeds the models.
const bool kGuideCropEnabled = true;

/// Side of the square crop as a fraction of the incoming capture's shorter
/// side, used by [CropStrategy.centeredFraction]. `0.55` ≈ the historical
/// 220 px on-screen guide box. Lower = tighter / more dermatoscopic; higher =
/// safer against clipping an off-center or large lesion. Calibrate empirically.
const double kGuideCropRatio = 0.55;

/// Logical-pixel side of the visual guide box. Shared between the overlay and
/// the [CropStrategy.coverGeometry] mapping so the box the user sees and the
/// region actually analyzed stay coupled. Historical value was 220.
const double kGuideBoxLogicalPx = 220.0;

/// Crop mapping strategy.
///  • [centeredFraction] — surface-agnostic. Crops the central
///    [kGuideCropRatio] square. Works for BOTH the AR-native capture and the
///    plain-camera capture. **Default.**
///  • [coverGeometry] — higher-fidelity variant intended for the plain-camera
///    `BoxFit.cover` preview only: derives the crop size from the real
///    on-screen box-to-preview proportion ([kGuideBoxLogicalPx] vs the
///    preview's shorter side) instead of a blind constant. Still emits a
///    centered square, so it stays robust on the AR path too.
enum CropStrategy { centeredFraction, coverGeometry }

const CropStrategy kGuideCropStrategy = CropStrategy.centeredFraction;
