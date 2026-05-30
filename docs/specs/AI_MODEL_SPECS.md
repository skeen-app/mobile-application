# AI Model Specifications - skeen

The Detection bounded context runs a **two-stage cascade** on every
capture (camera AR + gallery upload):

1. **Stage 1 — Skin Gate** decides whether the image shows skin. If not,
   the pipeline short-circuits and the user is shown an educational
   dialog asking them to refocus on a skin area with a visible lesion.
2. **Stage 2 — Cancer Classifier** (only runs when stage 1 approves)
   emits per-class probabilities over the 5 lesion classes.

This file documents both stages.

---

## Stage 1 — Skin Gate

### Model
- **Filename:** `skin_detector_v1.tflite`
- **Path:** `assets/models/skin_detector_v1.tflite`
- **Format:** TensorFlow Lite (uint8-quantized input)
- **Size:** ~1.3 MB
- **Architecture:** `MobileNetV3Small` (transfer learning, ImageNet
  weights, fine-tuned).
- **Purpose:** Lightweight binary classifier that filters out frames
  that do not depict skin (clothing, backgrounds, blurry crops, etc.)
  before the heavier cancer classifier runs.

### I/O
- **Input shape:** `[1, 224, 224, 3]`
- **Input dtype:** `uint8` — the model was exported with
  `inference_input_type = tf.uint8`. Feed raw pixel integers in
  `[0, 255]` directly; do **NOT** convert to Float32 and do **NOT**
  divide by 255. The Rescaling layer baked into the TFLite graph (from
  `MobileNetV3Small`'s `include_preprocessing=True`) handles the
  internal conversion.
- **Color space:** RGB.
- **Output shape:** `[1, 1]`
- **Output dtype:** `uint8` — the model is fully quantized. The raw
  uint8 value must be **dequantized** to recover the sigmoid score in
  `[0, 1]`:
  ```
  real_score = (raw_uint8 - zeroPoint) * scale
  ```
  `scale` and `zeroPoint` are read from the output tensor's
  `QuantizationParams` at load time and cached in
  `TfliteSkinGateService`.
- Class indexing in training: `0 = not_skin`, `1 = skin` (alphabetical
  default of `image_dataset_from_directory`). After dequantization,
  `1.0 ≈ "skin"`, `0.0 ≈ "not skin"`.

### Decision rule
- **Threshold:** `0.70` (centralized as `kSkinGateThreshold` in
  `lib/features/detection/domain/skin_gate_result.dart`).
- `isSkin == skinScore >= threshold`.

### Lifecycle
- Loaded **once** at first capture via
  `DetectionController.bootstrap()`, in parallel with the cancer model.
- Provider (`skinGateServiceProvider`) is a non-`autoDispose`
  singleton, so the interpreter stays warm for the lifetime of the
  Riverpod scope — subsequent captures skip the load cost.

### Pipeline placement
- Runs **after** the standardized 1:1 center-crop and **before** the
  cancer classifier, on the same JPEG buffer (both stages see identical
  input).
- Both models are loaded **in parallel** during
  `DetectionController.bootstrap()` so the first capture doesn't pay a
  serial load cost.
- A negative verdict short-circuits the pipeline: no classifier call,
  no DB row, no notifications, no cloud upload. The
  `DetectionPhase.notSkinRejected` state drives the UI dialog.

---

## Stage 2 — Cancer Classifier

### Model
- **Filename:** `skeen_v2_quantized.tflite`
- **Path:** `assets/models/skeen_v2_quantized.tflite`
- **Core architecture:** EfficientNetB0 (fine-tuned)
- **Format:** TensorFlow Lite (Float16 quantized)
- **Size:** ~7 MB

### I/O
- **Input shape:** `[1, 224, 224, 3]`
- **Color space:** RGB, values in `[0, 255]` (internal `Rescaling`
  layer — do NOT divide by 255)
- **Output shape:** `[1, 5]` — softmax probabilities over the 5
  classes below.

### Classes
| Index | Slug                 | Display name              |
|-------|----------------------|---------------------------|
| 0     | `actinic_keratosis`  | Actinic Keratosis         |
| 1     | `bcc`                | Basal Cell Carcinoma      |
| 2     | `melanoma`           | Melanoma                  |
| 3     | `nevus`              | Nevus (benign)            |
| 4     | `scc`                | Squamous Cell Carcinoma   |

### Pre-processing
- **Resizing:** Bilinear interpolation to 224×224
- **Normalization:** Handled inside the model (`Rescaling` layer)

### Inference goal
- Prioritize **recall** for SCC (current: 0.77) and Melanoma.
