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
- **Filename:** `skeen_model_v2.tflite`
- **Path:** `assets/models/skeen_model_v2.tflite`
- **Core architecture:** EfficientNet-B1 (fine-tuned)
- **Format:** TensorFlow Lite (fully uint8-quantized, input AND output)
- **Size:** ~7.8 MB

### I/O (verified from the tensor signature)
- **Input shape:** `[1, 240, 240, 3]`
- **Input dtype:** `uint8`, quant `scale=1.0 / zeroPoint=0` — feed raw
  pixel integers in `[0, 255]`. EfficientNet's internal normalization is
  baked into the graph; do NOT divide by 255 or pre-normalize.
- **Output shape:** `[1, 5]` — softmax probabilities over the 5 classes.
- **Output dtype:** `uint8`, quant `scale=0.00390625 (1/256) / zeroPoint=0`.
  Dequantize each score with `real = (raw_uint8 - zeroPoint) * scale` to
  recover probabilities in `[0, 1]`.
- **Runtime note:** run on a **synchronous** `Interpreter` (not
  `IsolateInterpreter`) — the package's isolate path deadlocks on uint8
  tensors.

### Classes
Order is strictly alphabetical and MUST NOT be altered.
| Index | Slug                 | Display name              | Malignant |
|-------|----------------------|---------------------------|-----------|
| 0     | `actinic_keratosis`  | Actinic Keratosis         | yes       |
| 1     | `bcc`                | Basal Cell Carcinoma      | yes       |
| 2     | `melanoma`           | Melanoma                  | yes       |
| 3     | `nevus`              | Nevus (benign)            | no        |
| 4     | `scc`                | Squamous Cell Carcinoma   | yes       |

### Pre-processing
- **Resizing:** Bilinear interpolation to 240×240
- **Normalization:** Handled inside the model — feed raw uint8 `[0, 255]`.

### Decision logic — conservative three tiers
Implemented in `TriageDecisionPolicy` → `DiagnosisResult`. Derived from the
scores; does NOT alter the persisted `InferenceResult` / `WarningLevel`.
- `malignant_sum` = Σ probabilities of the 4 malignant classes.
- `nevus_p` = probability of nevus (the only benign class).
- `top_mal` / `top_mal_p` = strongest malignant class and its probability.

Thresholds: `TH_BENIGN = 0.70`, `TH_MALIGNANT_SUM = 0.55`, `TH_SPECIFIC = 0.55`.

Rules in order:
1. `nevus_p >= 0.70` → **benign**.
2. `malignant_sum >= 0.55` AND `top_mal_p >= 0.55` → **malignant, specific**
   (`lesionType = top_mal`).
3. `malignant_sum >= 0.55` (no class reached 0.55) → **malignant, unspecified**.
4. otherwise → **inconclusive**.

### Inference goal
- Prioritize **recall** for SCC (current: 0.77) and Melanoma.
