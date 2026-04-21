# skeen - DDD Development Rules

## Tech Stack
- Frontend: Flutter (Clean Architecture + DDD)
- State Management: Riverpod (Application Layer)
- AI: TFLite (Infrastructure Layer)

## Bounded Contexts
1. **Auth (Identity Validation):** Security and user sessions.
2. **Patient (Patient Management):** Metadata and clinical history.
3. **Detection (Inference Coordination):** Camera, AR, and TFLite processing.
4. **System (OTA Orchestration):** Model updates and global state.

## Coding Standards
- Feature-first folder structure.
- Separation of concerns: Logic in `application`, data in `infrastructure`, UI in `presentation`.
- English only for code and documentation.