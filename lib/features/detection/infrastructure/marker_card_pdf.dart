import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/capture_standard.dart';
import '../domain/fiducial_marker.dart';
import '../domain/study_protocol.dart';

/// Geometry of the printed card, in millimetres, card-local (origin at the
/// card's top-left corner, X right, Y down).
///
/// Pure and testable: every rectangle is derived from [FiducialMarker] and
/// [TargetDisc], so the artwork can only ever draw what the detector
/// expects. The PDF painter below just scales these to points.
@immutable
class MarkerCardLayout {
  MarkerCardLayout({this.marker = FiducialMarker.study})
      : _quiet = marker.cellMm * marker.quietZoneCells;

  final FiducialMarker marker;
  final double _quiet;

  static const double margin = 4.0;

  /// Band above the marker for the "lesion here" arrow.
  static const double arrowBand = 10.0;

  /// Band below the marker for the 30 mm verification ruler. The protocol
  /// text is printed under the card, not inside it, so the cut line hugs
  /// the ruler.
  static const double rulerBand = 8.0;

  /// Marker centre in card coordinates.
  Offset get markerCentre => Offset(
        margin + _quiet + marker.sideMm / 2,
        margin + arrowBand + _quiet + marker.sideMm / 2,
      );

  /// Converts a point in the marker's plane frame (mm, origin at the
  /// marker centre) to card coordinates.
  Offset fromPlane(Offset p) => markerCentre + p;

  Rect get markerRect => Rect.fromCenter(
        center: markerCentre,
        width: marker.sideMm,
        height: marker.sideMm,
      );

  /// The white quiet zone around the marker.
  Rect get quietRect => markerRect.inflate(_quiet);

  /// One of the 6×6 cells (border included).
  Rect cellRect(int row, int col) {
    final size = marker.cellMm;
    final origin = markerRect.topLeft;
    return Rect.fromLTWH(
      origin.dx + col * size,
      origin.dy + row * size,
      size,
      size,
    );
  }

  Rect get greyPatchRect => Rect.fromCenter(
        center: fromPlane(marker.greyPatch.centreMm),
        width: marker.greyPatch.sideMm,
        height: marker.greyPatch.sideMm,
      );

  Rect get whitePatchRect => Rect.fromCenter(
        center: fromPlane(marker.whitePatch.centreMm),
        width: marker.whitePatch.sideMm,
        height: marker.whitePatch.sideMm,
      );

  /// Where the target disc centre falls, in card coordinates — above the
  /// card's top edge, on the skin. Not printed (it is skin), but used to
  /// place the arrow that tells the participant where the lesion goes.
  Offset get discCentre => fromPlane(TargetDisc.centreMm());

  /// Arrow tip and base, pointing up from the quiet zone's top edge.
  Offset get arrowBase => Offset(markerCentre.dx, quietRect.top - 1.0);
  Offset get arrowTip => Offset(markerCentre.dx, quietRect.top - 7.0);

  /// The verification ruler: exactly 30 mm, left-aligned under the marker.
  Offset get rulerStart => Offset(quietRect.left, quietRect.bottom + 6.0);
  Offset get rulerEnd => rulerStart + const Offset(30.0, 0);

  /// Outer cut line.
  Rect get cardRect {
    final right = whitePatchRect.right + margin;
    final bottom = rulerStart.dy + rulerBand;
    return Rect.fromLTWH(0, 0, right, bottom);
  }
}

/// Builds the printable card at 1:1 scale on an A4 page.
///
/// Everything drawn comes from [MarkerCardLayout]; the only other content
/// is the protocol text. The 18% grey patch is printed as sRGB 118/255,
/// which is the encoded value of 18% linear reflectance — the same figure
/// the calibration expects to read back.
Future<Uint8List> buildMarkerCardPdf({
  FiducialMarker marker = FiducialMarker.study,
}) async {
  final layout = MarkerCardLayout(marker: marker);
  final doc = pw.Document(
    title: 'skeen — tarjeta de referencia',
    author: 'skeen',
  );

  const mm = PdfPageFormat.mm;
  final card = layout.cardRect;

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(15 * mm),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Tarjeta de referencia - imprimir al 100 %',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4 * mm),
          pw.SizedBox(
            width: card.width * mm,
            height: card.height * mm,
            child: pw.CustomPaint(
              size: PdfPoint(card.width * mm, card.height * mm),
              painter: (canvas, size) => _paintCard(canvas, layout, marker),
            ),
          ),
          pw.SizedBox(height: 8 * mm),
          pw.Text(
            'Colocación (igual en todas las sesiones)',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2 * mm),
          pw.Text(kMarkerPlacementInstruction,
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 4 * mm),
          pw.Text(
            'Comprobación de escala',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2 * mm),
          pw.Text(kPrintScaleCheckInstruction,
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 4 * mm),
          pw.Text(
            'Código ${marker.bits.toRadixString(16).toUpperCase()} · '
            'lado ${marker.sideMm.toStringAsFixed(0)} mm · '
            'parches ${FiducialMarker.patchSideMm.toStringAsFixed(0)} mm '
            '(gris 18 %, blanco)',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    ),
  );

  return doc.save();
}

/// Paints the card in PDF points; the canvas origin is the bottom-left of
/// the painted box, so Y is flipped from the layout's top-down millimetres.
void _paintCard(PdfGraphics canvas, MarkerCardLayout layout, FiducialMarker marker) {
  const mm = PdfPageFormat.mm;
  final h = layout.cardRect.height;

  double x(double xMm) => xMm * mm;
  double y(double yMm) => (h - yMm) * mm;

  void fillRect(Rect r, PdfColor color) {
    canvas
      ..setFillColor(color)
      ..drawRect(x(r.left), y(r.bottom), r.width * mm, r.height * mm)
      ..fillPath();
  }

  void strokeRect(Rect r, PdfColor color, double width) {
    canvas
      ..setStrokeColor(color)
      ..setLineWidth(width)
      ..drawRect(x(r.left), y(r.bottom), r.width * mm, r.height * mm)
      ..strokePath();
  }

  void line(Offset a, Offset b, PdfColor color, double width) {
    canvas
      ..setStrokeColor(color)
      ..setLineWidth(width)
      ..moveTo(x(a.dx), y(a.dy))
      ..lineTo(x(b.dx), y(b.dy))
      ..strokePath();
  }

  // Cut line.
  strokeRect(layout.cardRect, PdfColors.grey500, 0.5);

  // Quiet zone: explicit white so a coloured page background cannot bleed in.
  fillRect(layout.quietRect, PdfColors.white);

  // Code cells. Only the black ones are painted; white cells are paper.
  for (var row = 0; row < FiducialMarker.cellsPerSide; row++) {
    for (var col = 0; col < FiducialMarker.cellsPerSide; col++) {
      if (!marker.isCellWhite(row, col)) {
        fillRect(layout.cellRect(row, col), PdfColors.black);
      }
    }
  }

  // Reference patches. 118/255 is sRGB for 18% linear reflectance.
  fillRect(layout.greyPatchRect, const PdfColor.fromInt(0xFF767676));
  strokeRect(layout.whitePatchRect, PdfColors.grey400, 0.3);

  // "Lesion here" arrow, pointing up from the quiet zone.
  final base = layout.arrowBase;
  final tip = layout.arrowTip;
  line(base, tip, PdfColors.black, 1.2);
  line(tip, tip + const Offset(-2.0, 2.5), PdfColors.black, 1.2);
  line(tip, tip + const Offset(2.0, 2.5), PdfColors.black, 1.2);

  // Verification ruler: 30 mm with ticks every 10 mm.
  final r0 = layout.rulerStart;
  final r1 = layout.rulerEnd;
  line(r0, r1, PdfColors.black, 0.8);
  for (var i = 0; i <= 3; i++) {
    final tx = r0.dx + i * 10.0;
    line(Offset(tx, r0.dy - 2.0), Offset(tx, r0.dy + 2.0), PdfColors.black, 0.8);
  }
}
