# Handoff — capa de registro espacial (WP-0 → WP-5)

**Fecha:** 4 de septiembre de 2026
**Módulo:** `lib/features/detection` — brazo de intervención del estudio pareado (McNemar) con análisis de equidad por fototipo.

## Estado final

- **257 tests** de `detection` en verde (`flutter test test/detection`).
- `flutter analyze lib test tool` en línea base: 7 `info` preexistentes, ninguno en `detection` salvo `scans_api.dart:18` (ajeno).
- Working tree: **24 archivos modificados, 29 nuevos**, +1 555 / −136 líneas en los tracked. Sin `git add`, sin commits, sin ramas.
- `test/widget_test.dart` sigue fallando por la causa preexistente y ajena (`sharedPreferencesProvider must be overridden`, `auth_controller.dart:39`), verificada en worktree limpio sobre HEAD.

---

## 1. Inventario por work package

### WP-0 — Centroide del popup tone-invariante

| Archivo | Cambio |
|---|---|
| `infrastructure/tflite_inference_service.dart` (M) | Eliminado el estimador "píxel más oscuro + guarda absoluta de 10 niveles"; `_preprocess` → `preprocessCapture` (`@visibleForTesting`), delega al segmentador compartido. La ruta del tensor (224², float32, 0–255) no se toca. |
| `domain/roi_metrics_calculator.dart` (M) | Expone el centroide del blob elegido, ROI-normalizado. |
| `domain/roi_frame_metrics.dart` (M) | `lesionCentroid`, `lesion_centroid_x/y`. |
| `test/detection/inference_centroid_test.dart` (N), `lesion_segmentation_test.dart` (M) | Equidad a luma 200/120/55 sobre JPEG real y sobre el segmentador. |

### WP-1 — Detección de marcador y pose

| Archivo | Cambio |
|---|---|
| `domain/fiducial_marker.dart` (N) | Código `0xED41` (Hamming ≥10 entre rotaciones, ≥8 frente a sólido, sin filas/columnas uniformes), 30 mm, zona de silencio. Fuente única para detector y artwork. |
| `domain/skin_plane_pose.dart` (N) | `Matrix3`, `SkinPlanePose` (px/mm, tilt, homografía, R, t, intrínsecos, `project`, `project3`, `pxPerMmAt`, `localTiltDeg`, `distanceMm`, stale 400 ms), `Vec3`, `MarkerType`. |
| `domain/camera_intrinsics.dart` (N) | Intrínsecos pinhole; `zoomed`, `scaledTo`. |
| `domain/homography.dart` (N) | DLT de 4 puntos con pivoteo parcial. |
| `domain/luma_frame.dart` (N) | Frame de luma (+RGB opcional) submuestreado, con `scaleToFull` y zoom. |
| `application/marker_detector.dart` (N) | Umbral adaptativo → componentes conexas → hull convexo → cuadrilátero → unwarp 6×6 → decodificación → match con rotación → esquinas canónicas. Dart puro. |
| `application/pose_estimator.dart` (N) | Homografía; px/mm = √\|det J\|; R, t, normal por `K⁻¹H` con Gram-Schmidt. |
| `application/pose_tracker.dart` (N) | Isolate persistente, cadencia 100 ms, descarte de frames en vuelo, predicción por giroscopio (`K Rᵀ K⁻¹`), stale → `null`, `start()` cancela suscripciones previas. |
| `infrastructure/camera_intrinsics_service.dart` (N) | Canal `skeen.detection/camera_intrinsics`; conversión pura testeable. |
| `android/.../MainActivity.kt` (M) | Camera2: `LENS_INFO_AVAILABLE_FOCAL_LENGTHS`, `SENSOR_INFO_PHYSICAL_SIZE`. **Compila** (`BUILD SUCCESSFUL`). |
| `ios/Runner/AppDelegate.swift` (M) | AVFoundation: `videoFieldOfView`. Sin toolchain aquí — pendiente de `flutter build ios`. |
| `infrastructure/scan_camera_service.dart` (M) | Frames de detección desde el **mismo** stream (nunca un segundo stream); `sensorOrientationDegrees`; zoom rastreado. |
| `infrastructure/gyroscope_stability_service.dart` (M) | Stream vectorial `angularVelocity`. |
| `domain/ports.dart` (M) | `detectionFrames`, `sensorOrientationDegrees`, `angularVelocity`, `CameraIntrinsicsPort`. |
| `domain/capture_stability.dart` (M) | `AngularVelocity`. |
| `application/readiness_evaluator.dart`, `application/providers.dart` (M) | Pose en `CaptureReadiness`; providers de intrínsecos y tracker. |
| `test/detection/marker_pose_test.dart` (N, 18), `pose_tracker_test.dart` (N, 17) | Precisión sintética y contrato del tracker. Benchmark: 13–17 ms @640×360, 8–10 ms @320×180 en este host. |

### WP-2c / WP-2d — Glare registrado y retícula anclada

| Archivo | Cambio |
|---|---|
| `domain/display_mapping.dart` (N) | `roiToDisplay`/`displayToRoi`, `gyroToStreamFrame`, `streamToDisplayPx`, `displayFrameToWidget`, `streamToWidget`. La rotación sensor→pantalla se decide en un solo sitio. |
| `domain/lesion_anchor.dart` (N) | Ancla de la lesión (centro, diámetro, `predicted`, stale 1 s). |
| `application/anchor_smoother.dart` (N) | EMA α=0.5 + predicción por giroscopio con la misma homografía conjugada del tracker; sin intrínsecos, solo suavizado. |
| `domain/roi_metrics_calculator.dart`, `roi_frame_metrics.dart` (M) | Mapa de glare 8×8 por celda + centroide especular. |
| `presentation/widgets/capture_guide_overlay.dart` (M) | `_ReticlePainter`, `_GlarePainter` (sombreado + flecha desde el reflejo alejándose de la lesión); texto solo para lo no espacial. |
| `test/detection/registered_overlay_test.dart` (N, 15) | Mapa de glare, mapeo por orientación, smoother, cableado del evaluador. |

### WP-2a / WP-2b — Disco objetivo y nadir

| Archivo | Cambio |
|---|---|
| `domain/capture_standard.dart` (N) | Estándar físico derivado: 12 mm de ROI (6 mm criterio D / 0.5 fill), `targetPxPerMm(roiSidePx)`, ±15 %, 12°, 0.2 radios, `TargetDisc` (posición respecto al marcador, holgura 3 mm, nadir 15 mm). |
| `domain/skin_plane_pose.dart`, `application/pose_estimator.dart`, `pose_tracker.dart` | Transformación rígida completa; la predicción rota R y t. |
| `presentation/widgets/capture_guide_overlay.dart` (M) | `_PlanePainter` a pantalla completa: disco (elipse bajo tilt, color por escala) y nadir (se cierra cuando el disco se ve de frente; color por inclinación local). |
| `test/detection/plane_registration_test.dart` (N, 14) | Geometría del disco y del nadir; consistencia de las dos rutas de mapeo. |

### WP-3 — Gate físico

| Archivo | Cambio |
|---|---|
| `domain/pose_readiness.dart` (N) | Escala, inclinación local y centrado evaluados **en el disco**; fail-closed en cada eje; `PoseAdvice`. |
| `domain/capture_quality.dart` (M) | `poseReadiness` entra en `isReady` y sustituye al gate de fill; `failingKey` y `coachingPriority` pasan al dominio; checklist Marker/Scale/Tilt/Centred. |
| `domain/device_eligibility.dart`, `application/eligibility_checker.dart`, `providers.dart`, `scan_a_mole_screen.dart` (M) | Requisito `cameraIntrinsics` con exclusión declarada y registrada. |
| `capture_guide_overlay.dart` (M) | Un solo `HintArbiter` con la prioridad del dominio; texto solo para `marker`. |
| `domain/capture_telemetry.dart` (M) | `gate_scale` pasa a ser el gate de px/mm. |
| `test/detection/pose_gate_test.dart` (N, 11); `capture_gate_test`, `eligibility_checker_test`, `readiness_evaluator_test` (M) | Gate por eje, integración con tracker, exclusión por intrínsecos. |

### WP-4 — Calibración de color y luma

| Archivo | Cambio |
|---|---|
| `domain/fiducial_marker.dart` (M) | `ColorPatch`; parches gris 18 % y blanco, 8 mm, a la derecha del código, fuera de la zona de silencio y del disco (verificado por test). |
| `domain/color_calibration.dart` (N) | sRGB↔lineal, `PatchReading` con motivos de invalidez, `ColorCalibration` (ganancias, `correct(ColorCast)`, `reflectanceOf`, `toJson`). |
| `application/patch_sampler.dart` (N) | Malla 5×5 sobre el 60 % interior de cada parche, proyectada por la pose. |
| `domain/luma_frame.dart`, `infrastructure/scan_camera_service.dart` (M) | Plano RGB opcional en el frame de detección. |
| `application/pose_tracker.dart` (M) | Lectura de parches con cada detección; `calibration` vive solo con la pose. |
| `domain/capture_quality.dart`, `application/readiness_evaluator.dart` (M) | Cast corregido cuando hay calibración; `colorCalibrated`, `skinReferenceReflectance`. |
| `test/detection/color_calibration_test.dart` (N, 13) | Renderizador físico (reflectancia × iluminante → sRGB); ±5 % entre luz de día, tungsteno, fluorescente y luz tenue. |

### WP-5 — Telemetría y protocolo

| Archivo | Cambio |
|---|---|
| `domain/capture_telemetry.dart` (M) | 22 campos de registro espacial (ver §4), en ambos brazos. |
| `domain/skin_plane_pose.dart` (M) | `MarkerType` (`aruco`; `coin` en el vocabulario, nunca reportado). |
| `domain/study_protocol.dart` (N) | Instrucción de colocación literal, comprobación de escala, nota de emuladores. |
| `infrastructure/marker_card_pdf.dart` (N) | `MarkerCardLayout` (mm, derivado del marcador) + `buildMarkerCardPdf`. |
| `tool/generate_marker_card.dart` (N) | `flutter test tool/generate_marker_card.dart` → `docs/protocol/marker_card.pdf`. |
| `docs/protocol/marker_card.pdf` (N) | Tarjeta A4 a 1:1 con regla de 30 mm. Revisada visualmente. |
| `docs/protocol/PROTOCOLO_MARCADOR.md` (N) | Impresión, comprobación, colocación, elegibilidad, esquema de telemetría, desenlaces secundarios, criterios de continuación, limitaciones. |
| `README.md` (M) | Sección "Study protocol & device eligibility". |
| `scan_a_mole_screen.dart` (M) | Pasa el lado del recorte para registrar `px_per_mm_target`. |
| `test/detection/marker_card_test.dart` (N, 12); `capture_telemetry_test` (M) | Layout ≡ marcador; texto de colocación sin lenguaje de propósito; campos de telemetría con pose real. |

---

## 2. Pipeline resultante (ruta de cámara, 100 % de participantes)

```
CameraImage (un solo stream)
 ├─ cada 320 ms → computeRoiMetrics (luma, nitidez, glare 8×8, cast, blob tone-invariante)
 └─ cada 100 ms → LumaFrame(+RGB) → PoseTracker (isolate) → detectMarker → estimatePose
                                           ↓                        ↓
                                     samplePatches → ColorCalibration
 giroscopio (50 ms) → AnchorSmoother (retícula) + predicción de pose
                 ↓
 ReadinessEvaluator → CaptureReadiness { luma, focus, glare, cast corregido, quietud,
                                         anchor, pose, poseReadiness (escala/tilt/centro en el disco) }
                 ↓                                     ↓
 CaptureGuideOverlay (disco, nadir, retícula, glare)   isReady → gate → auto-disparo 600 ms
                                                        ↓
                                        CaptureTelemetryRecord (una fila por intento, ambos brazos)
```

Brazo control: mismo pipeline sin overlay, sin gate y sin auto-disparo; la telemetría se registra igual.

---

## 3. Constantes del estándar — un solo sitio

`domain/capture_standard.dart`:

| Constante | Valor | Derivación |
|---|---|---|
| `kLesionReferenceMm` | 6 mm | criterio D del ABCD |
| `kLesionFillTarget` | 0.5 | centro de la banda de fill [0.25, 0.80] |
| `kRoiSideMm` | **12 mm** | 6 / 0.5 |
| `targetPxPerMm(roiSidePx)` | `roiSidePx / 12` | función de la resolución del stream |
| `kScaleTolerance` | ±15 % | temblor axial sin deriva de tamaño |
| `kMaxTiltDeg` | 12° (local en el disco) | escorzo visible en el borde a partir de ahí |
| `kCentreTolerance` | 0.2 radios | ≥40 % de margen perilesional |
| `TargetDisc.gapMm` | 3 mm | el recorte nunca contiene la tarjeta |
| `TargetDisc.nadirHeightMm` | 15 mm | ~16 px de desplazamiento a 12° / 15 cm |

Sin cambio respecto a sprints anteriores: glare 2 %, cast 18 %, giroscopio 0.15 rad/s, nitidez 0.60 del máximo de sesión, suelo 25, calentamiento 5 muestras, histéresis 1 500 ms, auto-disparo 600 ms. Nuevos: pose stale 400 ms, retícula stale 1 000 ms, parches σ ≤ 12 / blanco ≤ 250 / gris ≥ 15.

---

## 4. Esquema de telemetría (campos añadidos)

`marker_detected`, `marker_type`, `px_per_mm` (en el disco), `px_per_mm_marker`, `px_per_mm_target`, `scale_ratio`, `tilt_deg` (local en el disco), `tilt_global_deg`, `centre_offset`, `pose_age_ms`, `detect_ms`, `gate_marker`, `gate_tilt`, `gate_centre`, `color_calibrated`, `gray_patch_luma`, `white_patch_luma`, `wb_gain_r`, `wb_gain_g`, `wb_gain_b`, `skin_reference_reflectance`. Además, `gate_scale` pasa a significar el gate de px/mm. Filas `kind: "eligibility"` con el motivo nuevo `camera_intrinsics`.

Todos nulos o falsos sin pose — nunca un valor plausible.

---

## 5. Verificado / no verificado

**Verificado en esta máquina**

- 257 tests: equidad a tres tonos (centroide, detector, pose, glare, calibración); precisión sintética (esquinas < 2 px, px/mm < 5 %, tilt ±3° en 5°/12°/20°/25°); fail-closed en cada señal; sin fugas de suscripción tras 3 `start()`; el recorte nunca contiene la tarjeta ni los parches.
- Kotlin compila (`:app:compileDebugKotlin` → `BUILD SUCCESSFUL`).
- PDF generado y revisado visualmente.

**No verificado — bloquea el reclutamiento**

1. `px_per_mm` con regla y `tilt_deg` con goniómetro en teléfono real.
2. Signo del mapeo de ejes del giroscopio por `sensorOrientation` (un error se ve como deriva ≤100 ms de la predicción; no corrompe ninguna medida).
3. Compilación iOS (`AppDelegate.swift`, `SkeenArPlugin.swift`).
4. **Equidad con piel real** (fototipos I–II, III–IV, V–VI) y análisis de correlación del piloto: `lesion_relative_contrast`, `gate_ready`, `px_per_mm` frente a `skin_reference_luma` y `skin_reference_reflectance`. Criterio de continuación del protocolo, no comprobación opcional.
5. `detect_ms` en un dispositivo de gama baja (umbral de decisión ~80 ms → bajar `detectionMaxWidth` a 256 antes de considerar nativo).

---

## 6. Checklist consolidada en dispositivo (antes del participante 1)

1. Imprimir el PDF al 100 % y **medir la regla**: 30 mm o no se usa.
2. Marcador sobre la mesa a 10 / 15 / 20 cm: `px_per_mm × 30` ≈ lado del marcador en px; `tilt_deg` ±3° a 0° / 12° / 25° con goniómetro.
3. Tapar el marcador: pose a `null` en < 0.5 s; el obturador se bloquea; texto "Show the marker card".
4. Girar la tarjeta 90°/180°/270°: el disco y el marco canónico no saltan.
5. Mover el teléfono: disco y retícula quedan sobre el mismo punto físico; si oscilan al lado contrario y corrigen, revisar el signo del eje.
6. Inclinar 25°: elipse, anillo del nadir abierto y naranja, obturador bloqueado; nivelar **sobre el disco** lo cierra y dispara a ~600 ms.
7. Acercar hasta desbordar / alejar hasta que el disco sea pequeño: bloqueado; verde cuando el disco llena el recuadro.
8. Lunar fuera del disco: retícula naranja, bloqueado; centrar → verde.
9. Pulsar el obturador con algo en rojo: **no dispara**.
10. Flash a corta distancia: sombreado sobre el reflejo real, flecha alejándose de la lesión; `white patch clipped` en telemetría.
11. Misma persona bajo bombilla, fluorescente y ventana: `skin_reference_reflectance` ±5 %; `gate_color` verde en las tres.
12. Fototipos I–II y V–VI: pasos 6–11 equivalentes; `skin_reference_reflectance` difiere entre personas, no entre luces.
13. Background/resume ×3: `detectionCount` crece a ~10/s, no a 30/s; retícula y disco siguen vivos.
14. Sesión en cada brazo con el mismo participante: las filas del **control** traen `marker_detected`, `px_per_mm`, `tilt_deg`, `color_calibrated`.
15. `pose_age_ms` en disparos automáticos < 400.
16. Emulador: fila `eligibility` con `eligible: false` y motivo; sin filas de captura.

---

## 7. Decisiones abiertas

- **Fallback de moneda:** no implementado. Implica un segundo detector (Hough + elipse), el reflejo especular de una moneda choca con el gate de glare, y una moneda no da orientación (el disco objetivo la necesita). Recomendación: declararlo limitación y exigir la tarjeta impresa; si hace falta, WP aparte y **antes del participante 1**.
- **Diccionario ArUco oficial:** `0xED41` es propio. Si se prefiere un ID de `DICT_4X4_50`, el cambio es una constante + regenerar el PDF.
- **Reflectancias del impreso:** 0.18 / 0.90 nominales; para valor absoluto, medir el parche impreso una vez.

## 8. Limitaciones declaradas

- Sin fallback de moneda.
- Marcador y lesión se asumen coplanares; la curvatura de la piel entre ambos no se modela.
- Punto principal en el centro del frame; el stream abarca el ancho completo del sensor (válido para mismo aspect y recorte 16:9-de-4:3).
- `reflectanceOf` linealiza una luma codificada (aproximación; dentro del ±5 % en sintético).
- Los painters no tienen golden tests; son funciones directas de valores testeados.

## 9. Sugerencia de versionado (no ejecutada)

Un commit por work package, en orden de dependencia: WP-0, WP-1, WP-2c/2d, WP-2a/2b, WP-3, WP-4, WP-5. Versionar `docs/protocol/marker_card.pdf` junto a su generador para que la tarjeta impresa quede trazable al código que la produjo.
