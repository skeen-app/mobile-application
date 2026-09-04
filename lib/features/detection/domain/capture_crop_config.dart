/// ── Guide-box geometry ──────────────────────────────────────────────────
///
/// The classifier was trained on dermatoscopic frames (lesion centred and
/// dominant). A phone frame carries far more surrounding skin, so the capture
/// is cropped to the region the user framed inside the on-screen guide box
/// before the cascade runs.
///
/// **One source of truth.** These constants define the guide box *on screen*
/// only. Everything downstream — the region readiness metrics are measured
/// over, and the region cropped out of the capture for the models — is
/// derived from that box through `resolveGuideBoxSide` and
/// `CaptureRoi.fromPreviewGeometry`, using the real preview↔frame mapping.
///
/// This used to be three independent derivations: the overlay drew a box, the
/// metrics sampled a separately-derived region, and the cropper cut a blind
/// `0.55` of the captured image's shorter side. They agreed only at the
/// aspect ratio the constant happened to be tuned for and drifted apart at
/// every other one, so "what you frame" was not "what gets analysed". The
/// `CropStrategy` enum that used to live here existed to approximate the
/// mapping that is now computed properly, and is gone with it.
library;

/// Master switch. When `false`, the full standardized capture reaches the
/// models untouched and the guide box falls back to its fixed logical size.
const bool kGuideCropEnabled = true;

/// Side of the on-screen guide box as a fraction of the preview's **shorter
/// side**. This is a UI dimension: how much of the viewfinder the box covers.
/// The fraction of the *captured frame* that ends up analysed is derived from
/// it, not equal to it.
const double kGuideCropRatio = 0.55;

/// Fallback logical-pixel side for the guide box, used when the preview has
/// not been laid out yet or cropping is disabled.
const double kGuideBoxLogicalPx = 220.0;
