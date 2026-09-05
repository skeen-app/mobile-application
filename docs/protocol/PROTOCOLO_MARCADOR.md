# Protocolo de la tarjeta de referencia

Documento de campo para el estudio pareado (McNemar) de calidad de captura.
La tarjeta se usa **en los dos brazos** con la misma instrucción literal.

## 1. Qué es la tarjeta

Una tarjeta impresa con:

- un código de 4×4 celdas con borde negro, **30 mm** de lado (código `ED41`);
- dos parches de referencia de **8 mm**: gris 18 % y blanco;
- una flecha que indica dónde va el lunar;
- una línea de **30 mm** para comprobar que la impresión está a escala.

El archivo es `docs/protocol/marker_card.pdf`. Se genera desde el código con
`flutter test tool/generate_marker_card.dart`, de modo que la tarjeta impresa
y el detector de la app comparten una única definición.

## 2. Impresión

1. Imprimir en papel mate blanco al **100 %** (sin "ajustar a la página").
2. Medir la línea de comprobación con una regla: **debe medir exactamente
   30 mm**. Si no, la tarjeta no sirve: imprimir de nuevo.
3. Recortar por la línea exterior.

Una tarjeta al 97 % introduce un 3 % de error en todos los `px_per_mm`
registrados y nada en los datos lo delataría. Por eso la comprobación es
obligatoria y previa.

## 3. Colocación — idéntica en ambos brazos

Leer al participante, literalmente:

> Coloca la tarjeta sobre la piel, plana, justo debajo del lunar, con la
> flecha apuntando hacia el lunar y a unos 3 mm de él. Mantén la tarjeta
> quieta mientras se toma la foto.

No añadir nada sobre para qué sirve la tarjeta. Los dermatólogos que
juzgan las fotos están ciegos al brazo, y la tarjeta aparece en las fotos
de los dos: cualquier redacción que sugiera que "hace algo" en el brazo
guiado rompe el cegamiento.

## 4. Elegibilidad del dispositivo

Al abrir el escáner, la app comprueba cámara, giroscopio e intrínsecos de
cámara (focal reportada por la plataforma). Si falta cualquiera:

- con participante asignado: pantalla "Este dispositivo no es compatible
  con el estudio" con el motivo, y una fila `kind: "eligibility"` con
  `eligible: false` y el motivo en la telemetría;
- sin participante (uso normal): la cámara funciona sin asistencia y se
  muestra un aviso.

Los dispositivos elegibles también escriben su fila (`eligible: true`):
es el denominador de la tasa de exclusión.

**Emuladores y simuladores no tienen giroscopio ni, en general, reportan la
focal de la cámara: aparecen como no elegibles. Es el comportamiento
correcto (fail-closed), no un defecto.** Las pruebas del brazo guiado se
hacen en dispositivo físico.

## 5. Telemetría por intento

Archivo `capture_telemetry.jsonl` en los documentos de la app. Una fila por
intento, en ambos brazos, con `kind: "capture"`. Campos añadidos por la
capa de registro espacial:

| Campo | Tipo | Significado |
|---|---|---|
| `marker_detected` | bool | había pose válida (no stale) al disparar |
| `marker_type` | `"aruco"` \| null | tipo de referencia; la moneda no está implementada |
| `px_per_mm` | double? | escala **en el disco objetivo**, px de stream por mm |
| `px_per_mm_marker` | double? | escala en el centro del marcador (validación WP-1) |
| `px_per_mm_target` | double? | objetivo para el recorte de este dispositivo |
| `scale_ratio` | double? | `px_per_mm / px_per_mm_target` |
| `tilt_deg` | double? | inclinación **local en el disco** (la gateada) |
| `tilt_global_deg` | double? | inclinación normal vs. eje óptico |
| `centre_offset` | double? | distancia lesión–centro del disco, en radios |
| `pose_age_ms` | int? | antigüedad de la última detección real |
| `detect_ms` | int? | tiempo del detector en ese frame |
| `gate_marker`, `gate_tilt`, `gate_centre` | bool | estado de cada gate físico |
| `color_calibrated` | bool | parches legibles en el frame de la pose |
| `gray_patch_luma`, `white_patch_luma` | double? | luma codificada de cada parche |
| `wb_gain_r/g/b` | double? | ganancias de balance de blancos aplicadas |
| `skin_reference_reflectance` | double? | reflectancia de la piel de referencia relativa al gris 18 % |

Se suman a los campos previos (condición, disparo manual/automático, vector
de readiness en el instante del disparo, `skin_reference_luma`,
`lesion_relative_contrast`, `analysis_id` nulo en rechazos).

## 6. Desenlaces secundarios que habilita

Con la tarjeta en ambas condiciones, por foto y por brazo:

- varianza intra-brazo de `px_per_mm` — la estandarización, medida;
- distribución absoluta de `tilt_deg`;
- `skin_reference_reflectance` por fototipo, comparable entre sesiones y luces.

Variables continuas, con más potencia que el juicio binario del McNemar.

## 7. Criterios de continuación (piloto, ~10 participantes)

1. El gate abre a `px_per_mm` y `tilt_deg` comparables en fototipos I–II,
   III–IV y V–VI. Si en piel oscura se queda en "Point the camera at the
   mole", parar el reclutamiento.
2. `lesion_relative_contrast`, `gate_ready` y `px_per_mm` no correlacionan
   con `skin_reference_luma` ni con `skin_reference_reflectance`. Si
   correlacionan, detener y recalibrar.

## 8. Limitaciones declaradas

- **Sin fallback de moneda.** La tarjeta impresa es requisito. Una moneda
  daría escala y plano pero no orientación (el disco objetivo la necesita),
  y su reflejo especular choca con el gate de glare.
- Las reflectancias nominales de los parches (0.18 / 0.90) son las de la
  impresión ideal; una impresora doméstica introduce un desplazamiento
  global, no una deriva entre sesiones de la misma tarjeta.
- El marcador y la lesión se asumen coplanares; la curvatura de la piel
  entre ambos no se modela.
