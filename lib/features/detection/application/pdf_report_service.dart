import 'dart:typed_data';

import 'package:intl/intl.dart' show DateFormat;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/class_label.dart';
import '../domain/inference_result.dart';
import '../domain/lesion_analysis.dart';

/// Generates a single-page PDF triage report for a [LesionAnalysis].
///
/// Layout:
///   1. Header: skeen wordmark + report title.
///   2. Captured image, full width, with a quality stripe.
///   3. Risk card: level + class + confidence bar + description.
///   4. Metadata grid: body region, captured date, distance, image hash.
class PdfReportService {
  Future<Uint8List> build({
    required LesionAnalysis analysis,
    required Uint8List? imageBytes,
  }) async {
    final pdf = pw.Document(
      title: 'skeen — triage report',
      author: 'skeen',
      creator: 'skeen mobile app',
    );

    final image = imageBytes != null ? pw.MemoryImage(imageBytes) : null;
    final result = analysis.result;
    final dateFmt = DateFormat('MMMM d, y · HH:mm').format(analysis.capturedAt);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _header(),
            pw.SizedBox(height: 18),
            if (image != null) _imageBlock(image),
            pw.SizedBox(height: 18),
            _riskCard(result),
            pw.SizedBox(height: 18),
            _metadataBlock(analysis, dateFmt),
            pw.Spacer(),
            _footer(analysis.id),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  /// Convenience: hands the PDF to the platform share / save sheet.
  Future<void> shareReport({
    required LesionAnalysis analysis,
    required Uint8List? imageBytes,
  }) async {
    final bytes = await build(analysis: analysis, imageBytes: imageBytes);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'skeen-report-${analysis.id.substring(0, 8)}.pdf',
    );
  }

  // ── Sections ──────────────────────────────────────────────────────

  pw.Widget _header() {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 36,
          height: 36,
          decoration: pw.BoxDecoration(
            color: PdfColor.fromInt(0xFF7B5BE0),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          alignment: pw.Alignment.center,
          child: pw.Text(
            'sk',
            style: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('skeen',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 18,
                  color: PdfColor.fromInt(0xFF1E1444),
                )),
            pw.Text('Dermatological triage report',
                style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColor.fromInt(0xFF6B6098),
                )),
          ],
        ),
      ],
    );
  }

  pw.Widget _imageBlock(pw.MemoryImage image) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColor.fromInt(0xFF2F1B66),
          width: 1,
        ),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      padding: const pw.EdgeInsets.all(4),
      child: pw.AspectRatio(
        aspectRatio: 1,
        child: pw.Image(image, fit: pw.BoxFit.cover),
      ),
    );
  }

  pw.Widget _riskCard(InferenceResult result) {
    final risk = result.warningLevel;
    final color = _riskColor(risk);
    final title = _riskTitle(risk);
    final description = _riskDescription(risk);
    final confidencePct = (result.confidence * 100).clamp(0, 100);

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromInt(0xFF2F1B66)),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 8, height: 28,
                decoration: pw.BoxDecoration(
                  color: color,
                  borderRadius: pw.BorderRadius.circular(2),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(title,
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: color,
                      )),
                  pw.Text(result.topLabel.display,
                      style: pw.TextStyle(
                        fontSize: 12,
                        color: PdfColor.fromInt(0xFF1E1444),
                      )),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text(description,
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColor.fromInt(0xFF4A4A6A),
              )),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Text('Confidence',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColor.fromInt(0xFF6B6098),
                  )),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Stack(
                  children: [
                    pw.Container(
                      height: 8,
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFFE6E1F4),
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                    ),
                    pw.LayoutBuilder(
                      builder: (ctx, constraints) {
                        final w =
                            (constraints?.maxWidth ?? 0) * confidencePct / 100;
                        return pw.Container(
                          width: w,
                          height: 8,
                          decoration: pw.BoxDecoration(
                            color: color,
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text('${confidencePct.toStringAsFixed(1)}%',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: color,
                  )),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _metadataBlock(LesionAnalysis a, String date) {
    final entries = <(String, String)>[
      ('Body region', a.bodyRegion ?? '—'),
      ('Captured at', date),
      if (a.distanceCm != null)
        ('Distance', '${a.distanceCm!.toStringAsFixed(1)} cm'),
      if (a.imageHash != null)
        ('Image SHA-256', '${a.imageHash!.substring(0, 16)}…'),
    ];
    return pw.Wrap(
      spacing: 12,
      runSpacing: 8,
      children: entries
          .map((e) => pw.Container(
                width: 240,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColor.fromInt(0xFFE6E1F4)),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(e.$1,
                        style: pw.TextStyle(
                          fontSize: 8,
                          color: PdfColor.fromInt(0xFF6B6098),
                        )),
                    pw.SizedBox(height: 2),
                    pw.Text(e.$2,
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromInt(0xFF1E1444),
                        )),
                  ],
                ),
              ))
          .toList(),
    );
  }

  pw.Widget _footer(String analysisId) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(color: PdfColor.fromInt(0xFFE6E1F4)),
        pw.SizedBox(height: 6),
        pw.Text(
          'This report was generated by skeen on-device AI for triage support '
          'only. It does not replace a clinical diagnosis. Consult a licensed '
          'dermatologist for any concerning lesion.',
          style: pw.TextStyle(
            fontSize: 8,
            color: PdfColor.fromInt(0xFF6B6098),
            fontStyle: pw.FontStyle.italic,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text('Analysis ID: $analysisId',
            style: pw.TextStyle(
              fontSize: 7,
              color: PdfColor.fromInt(0xFF8A82A8),
            )),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────

  PdfColor _riskColor(WarningLevel level) {
    switch (level) {
      case WarningLevel.alert:
        return PdfColor.fromInt(0xFFE3416B);
      case WarningLevel.caution:
        return PdfColor.fromInt(0xFFE46A1D);
      case WarningLevel.reassuring:
        return PdfColor.fromInt(0xFF1FB89A);
    }
  }

  String _riskTitle(WarningLevel level) {
    switch (level) {
      case WarningLevel.alert:
        return 'High Risk Detected';
      case WarningLevel.caution:
        return 'Medium Risk Detected';
      case WarningLevel.reassuring:
        return 'Low Risk Detected';
    }
  }

  String _riskDescription(WarningLevel level) {
    switch (level) {
      case WarningLevel.alert:
        return 'High-risk patterns identified. Urgent clinical review is '
            'strongly recommended. Please consult a dermatologist.';
      case WarningLevel.caution:
        return 'Atypical patterns identified. Clinical review suggested '
            'based on visual analysis markers.';
      case WarningLevel.reassuring:
        return 'No concerning patterns identified. Continue routine '
            'self-monitoring and periodic dermatological check-ups.';
    }
  }
}
