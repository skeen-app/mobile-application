import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' show DateFormat;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/class_label.dart';
import '../domain/inference_result.dart';
import '../domain/lesion_analysis.dart';

// skeen brand palette mirrored on the printable PDF so a clinician
// recognises it as ours at a glance. Light surface tints are used as
// printable backgrounds to keep ink usage low.
const PdfColor _kBrandPurple = PdfColor.fromInt(0xFF7B5BE0);
const PdfColor _kBrandLilac = PdfColor.fromInt(0xFFB5A9E9);
const PdfColor _kBrandIndigo = PdfColor.fromInt(0xFF1E1444);
const PdfColor _kBrandSky = PdfColor.fromInt(0xFF1FB89A);
const PdfColor _kBrandPink = PdfColor.fromInt(0xFFE3416B);
const PdfColor _kBrandOrange = PdfColor.fromInt(0xFFE46A1D);
const PdfColor _kSurfaceTint = PdfColor.fromInt(0xFFF6F3FB);
const PdfColor _kBorderTint = PdfColor.fromInt(0xFFE6E1F4);
const PdfColor _kTextMuted = PdfColor.fromInt(0xFF6B6098);

/// Generates a single-page PDF triage report for a [LesionAnalysis].
///
/// Layout:
///   1. Header: skeen wordmark + report title.
///   2. Captured image, full width, with a quality stripe.
///   3. Risk card: level + class + confidence bar + description.
///   4. Metadata grid: body region, captured date, distance, image hash.
class PdfReportService {
  /// Cached so the brand mark only loads from the asset bundle once per
  /// app lifetime — every report after the first re-uses this image.
  pw.MemoryImage? _logoImage;

  Future<pw.MemoryImage?> _loadLogo() async {
    if (_logoImage != null) return _logoImage;
    try {
      final bytes = await rootBundle.load('assets/images/logo/skeen.png');
      _logoImage = pw.MemoryImage(bytes.buffer.asUint8List());
      return _logoImage;
    } catch (_) {
      return null;
    }
  }

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
    final logo = await _loadLogo();
    final result = analysis.result;
    final dateFmt = DateFormat('MMMM d, y · HH:mm').format(analysis.capturedAt);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _header(logo),
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

  pw.Widget _header(pw.MemoryImage? logo) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _kSurfaceTint,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _kBorderTint),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 44,
            height: 44,
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(10),
              border: pw.Border.all(color: _kBorderTint),
            ),
            alignment: pw.Alignment.center,
            child: logo != null
                ? pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Image(logo, fit: pw.BoxFit.contain),
                  )
                : pw.Text(
                    'sk',
                    style: pw.TextStyle(
                      color: _kBrandPurple,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
          ),
          pw.SizedBox(width: 14),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'skeen',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 20,
                    letterSpacing: 0.4,
                    color: _kBrandIndigo,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Dermatological triage report',
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: _kTextMuted,
                  ),
                ),
              ],
            ),
          ),
          pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: pw.BoxDecoration(
              color: _kBrandPurple,
              borderRadius: pw.BorderRadius.circular(999),
            ),
            child: pw.Text(
              'AI · ON-DEVICE',
              style: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 8,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _imageBlock(pw.MemoryImage image) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _kBrandLilac, width: 1),
        borderRadius: pw.BorderRadius.circular(10),
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
        color: _kSurfaceTint,
        border: pw.Border.all(color: _kBorderTint),
        borderRadius: pw.BorderRadius.circular(10),
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
                        color: _kBrandIndigo,
                      )),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text(description,
              style: pw.TextStyle(
                fontSize: 10,
                color: _kTextMuted,
              )),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Text('Confidence',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: _kTextMuted,
                  )),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Stack(
                  children: [
                    pw.Container(
                      height: 8,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(4),
                        border: pw.Border.all(color: _kBorderTint),
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
                  color: _kSurfaceTint,
                  border: pw.Border.all(color: _kBorderTint),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      e.$1,
                      style: pw.TextStyle(
                        fontSize: 8,
                        letterSpacing: 0.6,
                        color: _kBrandPurple,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      e.$2,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: _kBrandIndigo,
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  pw.Widget _footer(String analysisId) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: pw.BoxDecoration(
        color: _kBrandIndigo,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 4,
                height: 4,
                decoration: pw.BoxDecoration(
                  color: _kBrandPurple,
                  shape: pw.BoxShape.circle,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Text(
                'TRIAGE-ONLY DISCLAIMER',
                style: pw.TextStyle(
                  fontSize: 7,
                  letterSpacing: 0.8,
                  color: _kBrandLilac,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'This report was generated by skeen on-device AI for triage '
            'support only. It does not replace a clinical diagnosis. '
            'Consult a licensed dermatologist for any concerning lesion.',
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfColors.white,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Analysis ID  $analysisId',
            style: pw.TextStyle(
              fontSize: 7,
              color: _kBrandLilac,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────

  PdfColor _riskColor(WarningLevel level) {
    switch (level) {
      case WarningLevel.alert:
        return _kBrandPink;
      case WarningLevel.caution:
        return _kBrandOrange;
      case WarningLevel.reassuring:
        return _kBrandSky;
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
