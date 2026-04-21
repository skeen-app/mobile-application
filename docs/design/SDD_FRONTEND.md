# Software Design Document — skeen Frontend
**Version:** 1.0  
**Date:** 2026-04-20  
**Source:** Figma file `dm5ifBFxv13VlzlaLCDoHm` (diseño-UI-UX) + project context  
**Stack:** Flutter · Clean Architecture · DDD · Riverpod · TFLite

---

## 1. DDD Architecture — Bounded Contexts mapped to Figma screens

The Figma file contains one page with 33 frames. Each frame belongs to exactly one Bounded Context.

### 1.1 Auth — Identity Validation

| Figma Frame | Node ID | Description |
|---|---|---|
| `pantalla principal` | `39:21` | Splash / landing screen |
| `iniciar sesión` | `55:455` | Login form (email/phone + password) |
| `iniciar sesión completado` | `61:56` | Post-login success state |
| `registro` | `61:272` | Registration (Name, Last Name, DNI, Email, Phone, Password ×2) |
| `registro completado` | `69:124` | Post-registration confirmation |
| `terminos y condiciones` | `54:359` | Terms & Conditions scroll view |
| `permisos` | `30:148` | Camera and storage permissions onboarding |

**Auth routes:** `/` → `/login` → `/register` → `/register/success`  
**Key services:** `AuthService`, `SessionValidator`  
**Session gate:** `authStateProvider` must be authenticated before any other context renders.

---

### 1.2 Patient — Patient Data Management

| Figma Frame | Node IDs | Description |
|---|---|---|
| `inicio` (default) | `82:242` | Home dashboard: greeting, scan CTA, quick actions |
| `inicio` (body map) | `149:125` | Home with expanded body map |
| `inicio` (variants) | `153:549`, `154:807`, `155:338`, `155:1060` | State variants (empty, loaded, alert states) |

**Screen sections visible in `inicio` (82:242):**
- Greeting header ("Good morning, Fabia")
- **"Scan a mole"** primary CTA button (routes to Detection context)
- Quick action grid: `Upload a photo` · `Reminder`
- UV/Temperature card (Lima, Perú — 25°C, UV Index 11, "USE SPF 50+")
- **Body Map** with per-region mole distribution (Head: 1 · Chest: 3 · Legs: 2)
- "6 Registered moles" count · "Complete view" link · "+ Add new mole"

**Key entities:** `Patient`, `LesionHistory`  
**Patient routes:** `/home` · `/home/body-map` · `/history`

---

### 1.3 Detection — Image Analysis Coordination

| Figma Frame | Node ID | Description |
|---|---|---|
| `foto de mano` (instructions) | `43:131` | Step 2/3 — written instructions before capture |
| `foto de mano` (preview) | `45:218` | Step 2/3 — live camera preview without viewfinder |
| `foto de mano` (capture) | `138:812` | Step 2/3 — live camera + AR scanner frame |
| `foto de mano` (upload) | `54:302` | Gallery upload variant |
| `Floating Diagnosis Label` | `153:436` | AR overlay: diagnosis tag on detected lesion |
| `Guidance Pill` | `153:465` | AR guidance overlay: floating instruction strip |

**Detection flow (3-step onboarding for new patients):**
```
Step 1: Permissions       → permisos (30:148) [Auth/System crossover]
Step 2: Hand calibration  → foto de mano screens (43:131 → 138:812)
Step 3: First scan result → resultado (not yet designed)
```

**AR viewfinder** (`138:812`): Purple-bordered rounded rectangle with bracket-corner scanner marks. Guidance checklist below: ✓ illumination · ⏱ hand placement.  
**Key services:** `InferenceService`, `CameraManager`  
**Detection routes:** `/scan` · `/scan/calibrate` · `/scan/result`

---

### 1.4 System — OTA Update Orchestration

| Figma Frame | Node ID | Description |
|---|---|---|
| `Navigation Shell` | `152:418` | Shared bottom nav bar (all contexts) |
| `Status Indicators Section` | `153:447` | Global status strip (connectivity, model version) |
| `paleta colores` | `16:203` | Design token reference (not a screen) |

**Bottom nav tabs** (from Navigation Shell):
1. **Home** — Patient context (`/home`)
2. **History** — Patient context (`/history`)
3. **Scan** (central FAB, `--violeta` fill) — Detection context (`/scan`)
4. **ACTUALIZAR** — System context (`/system/update`)
5. **Profile** — Auth context (`/profile`)

The "ACTUALIZAR" tab is the primary surface for OTA model updates.

---

## 2. Service Layer

### 2.1 InferenceService

**Location:** `lib/features/detection/infrastructure/services/inference_service.dart`

```
InferenceService
  ├── _interpreter: Interpreter          // TFLite runtime
  ├── load(String modelPath) → Future<void>
  ├── run(Uint8List imageBytes) → InferenceResult
  └── dispose() → void
```

**Pre-processing pipeline** (required by EfficientNetB0 fine-tune):
1. Decode image bytes → raw pixels
2. Bilinear resize to **224×224**
3. Convert to `Float32List` with shape `[1, 224, 224, 3]` — values in `[0, 255]`  
   *(Model includes internal `Rescaling` layer; do NOT divide by 255)*
4. Feed to `Interpreter.run(input, output)`

**Output:**
```dart
class InferenceResult {
  final String topLabel;       // 'melanoma' | 'bcc' | 'scc' | 'nevus' | 'actinic_keratosis'
  final double confidence;     // 0.0 – 1.0
  final List<double> scores;   // all 5 class probabilities
}
```

**Label index map:**
| Index | Label | Clinical name |
|---|---|---|
| 0 | `actinic_keratosis` | AK |
| 1 | `bcc` | Basal Cell Carcinoma |
| 2 | `melanoma` | Melanoma |
| 3 | `nevus` | Benign Nevus |
| 4 | `scc` | Squamous Cell Carcinoma |

**Priority rule:** SCC (Recall target 0.77) and Melanoma are high-risk; the UI must surface these with elevated visual weight (use `--fucsia: #f43f5e` for alert state) regardless of raw confidence rank.

---

### 2.2 UpdateOrchestrator

**Location:** `lib/features/system/application/update_orchestrator.dart`

```
UpdateOrchestrator
  ├── checkForUpdate() → Future<UpdateStatus>
  ├── downloadUpdate(String remoteUrl) → Stream<DownloadProgress>
  ├── applyUpdate(String tempPath) → Future<void>
  └── rollback() → Future<void>
```

**Logic sequence:**
```
1. Fetch remote version manifest (JSON over HTTPS)
2. Compare manifest.modelVersion > localModelVersion
   → No update: emit UpdateStatus.upToDate
   → Update available: emit UpdateStatus.available(remoteUrl, size)
3. User confirms (or auto-download if on Wi-Fi)
4. Stream download of .tflite to app's documents directory (temp path)
5. Verify SHA-256 checksum against manifest
6. Hot-swap: call InferenceService.load(newPath)
   → Dispose old interpreter first
   → Persist new path to local preferences
7. On failure at any step: rollback() restores previous model path
```

**OTA assets:** both the `.tflite` model file and AR guide assets are managed by this orchestrator.  
**Riverpod integration:** `otaUpdateStateProvider` broadcasts `UpdateState` to the System UI tab.

---

## 3. Data Flow — Photo in Detection context → Patient entity

```
┌─────────────────────────────────────────────────────────────────┐
│  PATIENT CONTEXT                                                │
│  Home screen (inicio 82:242)                                    │
│  User taps "Scan a mole" CTA                                    │
└────────────────────┬────────────────────────────────────────────┘
                     │ navigate('/scan') + pass patientId
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  DETECTION CONTEXT                                              │
│  1. CameraManager.initialize()                                  │
│     → Request permission (granted via permisos screen)          │
│  2. CameraPreviewWidget shows live feed (foto de mano 138:812)  │
│     → AR ScannerFrame overlay renders bracket-corner guides     │
│     → GuidancePill shows "Be in a well illuminated place"       │
│  3. User taps "Continue"                                        │
│     → CameraManager.capture() → CameraImage (raw bytes)        │
│  4. InferenceService.run(imageBytes)                            │
│     → Pre-process: resize 224×224, Float32 [0-255]             │
│     → TFLite Interpreter → scores[5]                           │
│     → InferenceResult { topLabel, confidence, scores }         │
│  5. FloatingDiagnosisLabel renders on AR frame                  │
└────────────────────┬────────────────────────────────────────────┘
                     │ InferenceResult + bodyRegion (from session)
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  ANTI-CORRUPTION LAYER (Application layer, Detection context)   │
│  DetectionResultMapper.toEntity(result, patientId, region)      │
│  → LesionAnalysis {                                             │
│       id: UUID,                                                 │
│       patientId: String,        ← from currentPatientProvider  │
│       label: ClassLabel,                                        │
│       confidence: double,                                       │
│       scores: List<double>,                                     │
│       bodyRegion: BodyRegion,   ← Head | Chest | Legs | ...    │
│       capturedAt: DateTime,                                     │
│     }                                                           │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  PATIENT CONTEXT                                                │
│  LesionHistoryRepository.save(LesionAnalysis)                   │
│  → Persists to local DB (SQLite / Drift)                        │
│  → NO image saved to public gallery (privacy constraint)        │
│  currentPatientProvider.notifyListeners()                       │
│  → Home screen BodyMapWidget rebuilds with new mole count       │
└─────────────────────────────────────────────────────────────────┘
```

**No image leaves the device.** The raw `CameraImage` is discarded after `InferenceService.run()` completes. Only the `LesionAnalysis` entity (metadata + scores) is persisted.

---

## 4. UI Atoms — Shared widgets (`core/widgets`)

All widgets derive from the design token system below. No raw hex values in widget code.

### 4.1 Design Tokens (`core/theme/app_colors.dart`)

Sourced directly from Figma `paleta colores` (16:203):

| Token | Hex | Usage |
|---|---|---|
| `AppColors.violeta` | `#7c3aed` | Primary CTA, active nav, scan FAB |
| `AppColors.violetaOscuro` | `#4c1d95` | Button depth/shadow layer |
| `AppColors.violetaClaro` | `#ede9fe` | Heading text on dark background |
| `AppColors.naranja` | `#f97316` | Accent, UV warning, secondary labels |
| `AppColors.turquesa` | `#06b6d4` | Secondary progress, stable status |
| `AppColors.fucsia` | `#f43f5e` | High-risk diagnosis alert, error states |
| `AppColors.indigo` | `#1e1b4b` | Deep background variant, card base |
| `AppColors.background` | `#12103a` | App-wide scaffold background |
| `AppColors.hintText` | `#958cba` | Input placeholders, secondary body text |
| `AppColors.stroke` | `#6b6098` | Input borders, dividers |

**Typography:** Poppins family throughout. SemiBold (headings) · Medium (labels, buttons) · Regular (body, hints).

---

### 4.2 Atom Widget Catalogue

| Widget | File | Figma origin | Description |
|---|---|---|---|
| `SkeenButton` | `core/widgets/skeen_button.dart` | Buttons (55:523/524) | Primary CTA with stacked shadow layer (`violetaOscuro` offset +5.93 dp). Full-width, 52h, radius 11. |
| `SkeenTextField` | `core/widgets/skeen_text_field.dart` | Inputs (55:507) | Bordered input, stroke `#6b6098`, hint `#958cba`, Poppins Regular 16sp, radius 5, 56h. |
| `SkeenPasswordField` | `core/widgets/skeen_password_field.dart` | Password (55:509) | `SkeenTextField` + eye-icon suffix toggle. |
| `SkeenBrandHeader` | `core/widgets/skeen_brand_header.dart` | Logo (55:532) | "skeen" logotype: `s` in `violeta`, `keen` in naranja. Plus constellation SVG decorations. |
| `SkeenStatusBar` | `core/widgets/skeen_status_bar.dart` | Status Bar - Light (55:456) | Dark-mode status bar wrapper. |
| `SkeenStepIndicator` | `core/widgets/skeen_step_indicator.dart` | Step bar (43:148–150) | N-segment horizontal bar; filled = `violeta`, empty = `violetaOscuro`. |
| `BottomNavBar` | `core/widgets/bottom_nav_bar.dart` | Navigation Shell (152:418) | 4 icon tabs + central `violeta` FAB (Scan). Frosted glass bg `rgba(18,16,58,0.8)`, `backdropFilter: blur(12)`. |
| `ScannerFrame` | `core/widgets/scanner_frame.dart` | Scanner (138:835) | AR bracket-corner overlay. Animated border draw-on. Purple stroke `violeta`. |
| `GuidancePill` | `core/widgets/guidance_pill.dart` | Guidance Pill (153:465) | Floating rounded strip for camera instructions. |
| `FloatingDiagnosisLabel` | `core/widgets/floating_diagnosis_label.dart` | Floating Diagnosis Label (153:436) | High-tech AR data tag. Color varies by risk: `fucsia` (SCC/Melanoma), `turquesa` (stable). |
| `UVIndexCard` | `core/widgets/uv_index_card.dart` | UV widget (82:242 sub-node 145:256) | Semicircular arc progress + temperature + SPF badge. Accent color `naranja`. |
| `BodyMapWidget` | `core/widgets/body_map_widget.dart` | Body Map (128:584) | Human silhouette SVG + per-region `BodyMapBar` rows. |
| `BodyMapBar` | `core/widgets/body_map_bar.dart` | Body map bars (128:591–618) | Label + progress bar + count chip. Color: `violeta` (head) · `turquesa` (chest) · `naranja` (legs). |
| `SectionHeader` | `core/widgets/section_header.dart` | "BODY MAP" label (127:577) | Uppercase label (12sp, `#6b6098`) + right-aligned action link (`naranja`). |
| `QuickActionTile` | `core/widgets/quick_action_tile.dart` | Upload/Reminder tiles (121:469/471) | Dark card with icon + label + sublabel. `#1e1444` bg, `#2f1b66` border. |

---

## 5. State — Riverpod coordination between Bounded Contexts

### 5.1 Provider map

```dart
// ── AUTH CONTEXT ──────────────────────────────────────────────
final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>(...);
// AuthState: unauthenticated | authenticating | authenticated(User) | error

final sessionProvider = Provider<Session?>((ref) {
  return ref.watch(authStateProvider).sessionOrNull;
});

// ── PATIENT CONTEXT ───────────────────────────────────────────
final currentPatientProvider = StreamProvider<Patient>((ref) {
  final session = ref.watch(sessionProvider);
  // Loads patient profile from local DB by session.userId
});

final lesionHistoryProvider = StreamProvider.family<List<LesionAnalysis>, String>(
  (ref, patientId) { ... }
);

// ── DETECTION CONTEXT ─────────────────────────────────────────
final cameraControllerProvider =
    StateNotifierProvider<CameraNotifier, CameraState>(...);

final inferenceResultProvider =
    StateNotifierProvider<InferenceNotifier, AsyncValue<InferenceResult>>(...);
// Depends on: cameraControllerProvider (image source)
//             modelVersionProvider (valid model loaded)

// ── SYSTEM CONTEXT ────────────────────────────────────────────
final modelVersionProvider = StateProvider<String>((ref) => 'v1.0');

final otaUpdateStateProvider =
    StateNotifierProvider<OtaNotifier, OtaState>(...);
// OtaState: idle | checking | available(version) | downloading(progress) | applying | upToDate | error
```

---

### 5.2 Cross-context event flows

#### A. Detection result → Patient persistence

```
inferenceResultProvider.state = AsyncData(result)
    │
    ▼
DetectionResultSaver (ApplicationService, listens to inferenceResultProvider)
    │  ref.read(currentPatientProvider) → patientId
    │  ref.read(sessionProvider) → userId
    ▼
LesionHistoryRepository.save(LesionAnalysis)
    │
    ▼
lesionHistoryProvider invalidated → BodyMapWidget rebuilds
```

#### B. System OTA update → Detection context

```
otaUpdateStateProvider.state = OtaState.applying
    │
    ▼
UpdateOrchestrator.applyUpdate(tempPath)
    │  InferenceService.load(newPath)   ← hot-swap
    ▼
modelVersionProvider.state = newVersion
    │
    ▼
inferenceResultProvider is reset (model changed)
    → UI shows "Model updated" snackbar via SnackbarNotifier
```

#### C. Auth gate — context isolation

```
GoRouter redirect logic:
  if authStateProvider == unauthenticated
    → redirect to /login
    → all Patient / Detection / System routes are unreachable

  if authStateProvider == authenticated
    → /home is the root shell (Navigation Shell rendered)
    → BottomNavBar enables all 4 contexts
```

---

### 5.3 Navigation shell structure

```
AppShell (StatefulShellRoute)
 ├── Branch 0: /home          → Patient context (HomeScreen)
 ├── Branch 1: /history       → Patient context (HistoryScreen)
 ├── FAB (no branch):  /scan  → Detection context (ScanRouter)
 ├── Branch 2: /system/update → System context (UpdateScreen)
 └── Branch 3: /profile       → Auth context (ProfileScreen)
```

The `BottomNavBar` widget (152:418) is the single shared UI component that spans all four Bounded Contexts. It must be rendered by the `AppShell`, never by individual screens.

---

## 6. Folder structure (feature-first DDD)

```
lib/
├── core/
│   ├── theme/
│   │   ├── app_colors.dart        ← design tokens (Section 4.1)
│   │   └── app_typography.dart    ← Poppins TextTheme
│   └── widgets/                   ← atom widgets (Section 4.2)
│
├── features/
│   ├── auth/
│   │   ├── application/           ← AuthNotifier, SessionValidator
│   │   ├── domain/                ← User, Session
│   │   ├── infrastructure/        ← AuthRepository, SecureStorage
│   │   └── presentation/          ← LoginScreen, RegisterScreen
│   │
│   ├── patient/
│   │   ├── application/           ← PatientNotifier, LesionHistoryNotifier
│   │   ├── domain/                ← Patient, LesionAnalysis, BodyRegion
│   │   ├── infrastructure/        ← PatientRepository (Drift/SQLite)
│   │   └── presentation/          ← HomeScreen, BodyMapScreen, HistoryScreen
│   │
│   ├── detection/
│   │   ├── application/           ← InferenceNotifier, CameraNotifier, DetectionResultSaver
│   │   ├── domain/                ← InferenceResult, ClassLabel
│   │   ├── infrastructure/        ← InferenceService (TFLite), CameraManager
│   │   └── presentation/          ← ScanScreen, CalibrateScreen, ResultScreen
│   │
│   └── system/
│       ├── application/           ← OtaNotifier, UpdateOrchestrator
│       ├── domain/                ← ModelManifest, OtaState
│       ├── infrastructure/        ← ManifestRepository (HTTP), ModelStorage
│       └── presentation/          ← UpdateScreen
│
└── app/
    ├── router.dart                ← GoRouter with auth redirect + AppShell
    └── providers.dart             ← ProviderScope overrides for test
```
