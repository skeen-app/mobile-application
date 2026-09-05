/// Protocol text and layout constants shared by the printed card, the app
/// and the written protocol, so the three cannot drift apart.
library;

/// Placement instruction read to — and printed for — every participant,
/// **identically in both arms**.
///
/// The wording is deliberately inert: it describes where the card goes and
/// nothing about what it is for. The dermatologists judging the captures are
/// blind to the arm, and the card appears in both, so nothing about it may
/// hint that it "does something" in one of them.
const String kMarkerPlacementInstruction =
    'Coloca la tarjeta sobre la piel, plana, justo debajo del lunar, con la '
    'flecha apuntando hacia el lunar y a unos 3 mm de él. Mantén la tarjeta '
    'quieta mientras se toma la foto.';

/// Print-scale check printed on the card. A card printed at 97% is a 3%
/// error in every px/mm the study records, with nothing in the data to show
/// it — so the participant measures before using it.
const String kPrintScaleCheckInstruction =
    'Antes de usar la tarjeta, mide esta línea con una regla: debe medir '
    'exactamente 30 mm. Si mide otra cosa, la impresión no está a escala '
    'real; imprime de nuevo al 100 % (sin "ajustar a la página").';

/// Note surfaced in the README and the protocol document so an emulator
/// showing the exclusion screen is not filed as a bug.
const String kEmulatorEligibilityNote =
    'Emuladores y simuladores no tienen giroscopio ni, en general, reportan '
    'la focal de la cámara: la app los declara NO ELEGIBLES en la pantalla '
    'de escaneo y registra la exclusión en telemetría. Es el comportamiento '
    'correcto (fail-closed), no un defecto. Las pruebas del brazo guiado se '
    'hacen en dispositivo físico.';
