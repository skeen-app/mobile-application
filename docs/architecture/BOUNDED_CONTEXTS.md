# skeen - Bounded Contexts Definition

## 1. Identity Validation (Auth)
- Purpose: Ensure only authorized personnel access patient data.
- Key Services: AuthService, SessionValidator.

## 2. Patient Data Management (Patient)
- Purpose: Manage patient profiles and link them to lesion analysis.
- Entities: Patient, LesionHistory.

## 3. Image Analysis Coordination (Detection)
- Purpose: The core AI engine. Orchestrates Camera -> AR Guide -> TFLite -> Results.
- Key Services: InferenceService, CameraManager.

## 4. OTA Update Orchestration (System)
- Purpose: Ensure the `.tflite` model and AR assets are up to date without a full app store update.
- Logic: Check version, download assets, hot-swap model.