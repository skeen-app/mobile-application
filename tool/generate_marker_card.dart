import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skeen/features/detection/infrastructure/marker_card_pdf.dart';

/// Generates `docs/protocol/marker_card.pdf` from the marker definition in
/// code, so the printed card and the detector can never disagree.
///
/// Run from the project root:
///
///     flutter test tool/generate_marker_card.dart
///
/// It is written as a test because the marker geometry lives in the domain
/// layer, which imports `dart:ui`; a plain `dart run` cannot load that.
void main() {
  test('writes the marker card PDF', () async {
    final bytes = await buildMarkerCardPdf();
    final out = File('docs/protocol/marker_card.pdf');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes);
    // ignore: avoid_print
    print('wrote ${out.path} (${bytes.length} bytes)');
    expect(bytes.length, greaterThan(1000));
  });
}
