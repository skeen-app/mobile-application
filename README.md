# skeen: AI-Powered Dermatological Triage

skeen is a professional-grade mobile application designed for the early detection and triage of skin lesions in Peru. Developed to address high UV radiation risks and limited specialist access, skeen leverages On-Device Artificial Intelligence and Augmented Reality to provide a fast, offline, and secure screening tool for primary care physicians and users.

## Core Mission
To bridge the gap in dermatological healthcare by providing an accurate, offline-first triage tool for critical skin conditions (AK, BCC, Melanoma, Nevus, SCC) using state-of-the-art computer vision tailored for the Peruvian context.

---

## Key Features

- **Offline-First AI Inference:** Powered by a fine-tuned EfficientNetB0 model running locally via TFLite for 100% privacy and zero-latency analysis.
- **AR-Guided Capture:** Integrated ARCore/ARKit overlays to guide users toward the optimal focal distance and lighting for high-quality image analysis.
- **Privacy-Centric Design:** All medical data and images are processed on-device. No patient imagery is saved to public galleries or transmitted without explicit consent.
- **DDD Architecture:** Robust implementation of Domain-Driven Design (DDD) and Clean Architecture for enterprise-grade scalability and maintainability.

---

## Tech Stack

- **Framework:** Flutter (Stable)
- **State Management:** Flutter Riverpod
- **Architecture:** Clean Architecture + Domain-Driven Design (DDD)
- **Navigation:** GoRouter
- **AI/ML:** TensorFlow Lite (TFLite)
- **AR:** ARCore / ARKit
- **Design System:** Figma-synchronized via Atomic Design principles

---

## Project Structure (Bounded Contexts)

The project is organized into four main Bounded Contexts to isolate complexity and ensure high cohesion:

- **Identity Validation (auth):** Secure professional access and session management.
- **Patient Data Management (patient):** Handling of patient metadata and clinical history.
- **Image Analysis Coordination (detection):** The core engine orchestrating Camera, AR Guides, and TFLite Inference.
- **OTA Update Orchestration (system):** Independent delivery of AI model weights and AR asset updates.

```text
lib/
├── core/                 # Shared infrastructure (Theme, Router, Utils)
└── features/             # Bounded Contexts
    ├── auth/             # Identity & Security
    ├── patient/          # Clinical Metadata
    ├── detection/        # AI & AR Core Logic
    └── system/           # OTA & Global State
```

## Getting Started
### Prerequisites
- Flutter SDK (Latest Stable)
- Android Studio / Xcode
- TFLite Model Weights (assets/models/skeen_v2_finetuned.tflite)

## Installation & Setup
1. Clone the repository.
2. Initialize the project using the Claude Code skill:

```bash
claude skeen-init
```
Or manually:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

## AI Specifications
- Model Architecture: EfficientNetB0 (Fine-tuned)
- Input Shape: 224x224 RGB

Classification Labels:

- actinic_keratosis (AK)
- bcc (Basal Cell Carcinoma)
- melanoma
- nevus (Benign)
- scc (Squamous Cell Carcinoma)

- Performance Strategy: Prioritizing Recall (Sensitivity) for malignant classes to minimize false negatives in a medical context.

## Development Workflow
This project is optimized for a hybrid AI-Collaborative workflow:
Claude Code: Used for architectural scaffolding, dependency orchestration, and terminal-based automation via custom Skills.
Cursor: Used for rapid UI development (Atomic Widgets) and business logic refinement using the docs/design/SDD_FRONTEND.md as the primary blueprint.

## Study protocol & device eligibility

The capture module doubles as the intervention arm of a paired study. The
printed reference card, its placement instruction (identical in both arms)
and the telemetry schema are documented in `docs/protocol/PROTOCOLO_MARCADOR.md`;
the card itself is generated from code with
`flutter test tool/generate_marker_card.dart`.

**Emulators and simulators are reported as NOT ELIGIBLE** on the scan
screen: they have no gyroscope and generally do not report the camera's
focal length, both of which the guided arm measures. This is fail-closed
behaviour, not a bug — test the guided arm on a physical device. The
exclusion (and every eligible session) is written to the telemetry sidecar.

## Medical Disclaimer
skeen is a triage support tool and NOT a diagnostic system. It does not replace professional medical advice, diagnosis, or treatment. Always seek the advice of a dermatologist or other qualified health provider with any questions regarding a medical condition.