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

# General Rules
- Think before acting. Read existing files before writing code.
- Be concise in output but thorough in reasoning.
- Prefer editing over rewriting whole files.
- Do not re-read files you have already read unless the file may have changed.
- Skip files over 100KB unless explicitly required.
- Suggest running /cost when a session is running long to monitor cache ratio.
- Recommend starting a new session when switching to an unrelated task.
- Test your code before declaring done.
- No sycophantic openers or closing fluff.
- Keep solutions simple and direct.
- User instructions always override this file.