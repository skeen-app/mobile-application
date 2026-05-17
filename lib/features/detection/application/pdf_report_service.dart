import 'package:skeen/core/localization/locale_controller.dart';
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
// recognises it as ours at a glance. The page paints in the signature
// brand violet — content sits on white cards for legibility, the logo
// rides a white badge in the top-left for maximum contrast against the
// violet field.
const PdfColor _kBrandViolet = PdfColor.fromInt(0xFF7C3AED);
const PdfColor _kBrandVioletDeep = PdfColor.fromInt(0xFF4C1D95);
const PdfColor _kBrandLilac = PdfColor.fromInt(0xFFB5A9E9);
const PdfColor _kBrandLight = PdfColor.fromInt(0xFFEDE9FE);
const PdfColor _kBrandSky = PdfColor.fromInt(0xFF1FB89A);
const PdfColor _kBrandPink = PdfColor.fromInt(0xFFE3416B);
const PdfColor _kBrandOrange = PdfColor.fromInt(0xFFE46A1D);
const PdfColor _kCardBg = PdfColor.fromInt(0xFFFFFFFF);
const PdfColor _kCardBgSoft = PdfColor.fromInt(0xFFF6F3FB);
const PdfColor _kTextDark = PdfColor.fromInt(0xFF1A1340);
const PdfColor _kTextMuted = PdfColor.fromInt(0xFF6B6098);

/// Generates a single-page PDF triage report for a [LesionAnalysis].
///
/// Design language:
///   • Brand-violet full-page canvas — the same purple the app uses for
///     its primary accent. Every element sits on top of this.
///   • White circular badge holding the launcher logo, top-left corner,
///     so the mark reads at glance even at thumbnail size.
///   • Hero risk band — the typographic centrepiece. Risk level set in
///     32 pt, colour-coded, replaces the cramped row of the old report.
///   • White content cards with a leading colour stripe per section
///     (image, AI verdict, metadata) — adds visual hierarchy without
///     dragging in shadows that don't render the same across viewers.
///   • Confidence bar drawn full-width inside the verdict card with a
///     tick scale (0–100) so a clinician can read the percentage at a
///     glance even without the numeric label.
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
      title: 'skeen — triage report'.tr,
      author: 'skeen',
      creator: 'skeen mobile app',
    );

    final image = imageBytes != null ? pw.MemoryImage(imageBytes) : null;
    final logo = await _loadLogo();
    final result = analysis.result;
    final dateFmt = DateFormat('MMMM d, y · HH:mm').format(analysis.capturedAt);

    pdf.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 24),
          buildBackground: (ctx) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: _kBrandViolet),
          ),
        ),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _header(logo),
            pw.SizedBox(height: 18),
            _heroRisk(result),
            pw.SizedBox(height: 14),
            if (image != null) _imageCard(image),
            if (image != null) pw.SizedBox(height: 14),
            _confidenceCard(result),
            pw.SizedBox(height: 14),
            _metadataGrid(analysis, dateFmt),
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

  /// Top strip:
  ///   ┌──────┐  skeen                                  AI · ON-DEVICE
  ///   │ logo │  Dermatological triage report
  ///   └──────┘
  ///
  /// The logo rides a white rounded badge so it pops on the violet
  /// canvas — same trick the iOS / Android launcher uses against the
  /// dark-indigo background it was designed for.
  pw.Widget _header(pw.MemoryImage? logo) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 70,
          height: 70,
          decoration: pw.BoxDecoration(
            color: _kCardBg,
            borderRadius: pw.BorderRadius.circular(18),
          ),
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.all(6),
          child: logo != null
              ? pw.Image(logo, fit: pw.BoxFit.contain)
              : pw.Text(
                  'sk'.tr,
                  style: pw.TextStyle(
                    color: _kBrandViolet,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 28,
                  ),
                ),
        ),
        pw.SizedBox(width: 16),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'skeen'.tr,
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 28,
                  letterSpacing: -0.4,
                  color: _kCardBg,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Dermatological triage report'.tr,
                style: pw.TextStyle(
                  fontSize: 11,
                  color: _kBrandLight,
                ),
              ),
            ],
          ),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: pw.BoxDecoration(
            color: _kBrandVioletDeep,
            borderRadius: pw.BorderRadius.circular(999),
            border: pw.Border.all(color: _kBrandLight, width: 0.5),
          ),
          child: pw.Text(
            'AI · ON-DEVICE'.tr,
            style: pw.TextStyle(
              color: _kCardBg,
              fontWeight: pw.FontWeight.bold,
              fontSize: 8,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }

  /// Typographic hero: the risk level set in a heavy 30-pt face on the
  /// flat violet canvas. The class display name sits underneath in a
  /// lighter tint so the eye is funnelled top→down. No card chrome here
  /// — the contrast against the violet IS the chrome.
  pw.Widget _heroRisk(InferenceResult result) {
    final risk = result.warningLevel;
    final color = _riskColor(risk);
    final title = _riskTitle(risk).toUpperCase();

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(6, 4, 6, 0),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: pw.BoxDecoration(
              color: color,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              'AI verdict'.tr.toUpperCase(),
              style: pw.TextStyle(
                color: _kCardBg,
                fontWeight: pw.FontWeight.bold,
                fontSize: 8,
                letterSpacing: 1.4,
              ),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            title,
            style: pw.TextStyle(
              color: _kCardBg,
              fontWeight: pw.FontWeight.bold,
              fontSize: 30,
              letterSpacing: -0.6,
              lineSpacing: -2,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              pw.Container(width: 22, height: 2, color: color),
              pw.SizedBox(width: 8),
              pw.Text(
                result.topLabel.display,
                style: pw.TextStyle(
                  color: _kBrandLight,
                  fontSize: 13,
                  fontWeight: pw.FontWeight.normal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Captured image card. Vertical accent stripe on the left echoes the
  /// risk colour without overwhelming the photograph itself.
  pw.Widget _imageCard(pw.MemoryImage image) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _kCardBg,
        borderRadius: pw.BorderRadius.circular(14),
      ),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 4,
            height: 110,
            decoration: pw.BoxDecoration(
              color: _kBrandViolet,
              borderRadius: pw.BorderRadius.circular(2),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Captured lesion'.tr.toUpperCase(),
                  style: pw.TextStyle(
                    color: _kBrandViolet,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 8,
                    letterSpacing: 1.2,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.ClipRRect(
                  horizontalRadius: 10,
                  verticalRadius: 10,
                  child: pw.AspectRatio(
                    aspectRatio: 1.6,
                    child: pw.Image(image, fit: pw.BoxFit.cover),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Confidence card with a tick-scaled bar so a clinician sees the
  /// numeric percentage AND its relative position vs. the 0–100 range
  /// without parsing fine print.
  pw.Widget _confidenceCard(InferenceResult result) {
    final risk = result.warningLevel;
    final color = _riskColor(risk);
    final description = _riskDescription(risk);
    final confidencePct = (result.confidence * 100).clamp(0.0, 100.0);

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _kCardBg,
        borderRadius: pw.BorderRadius.circular(14),
      ),
      padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'AI Confidence'.tr.toUpperCase(),
                style: pw.TextStyle(
                  color: _kBrandViolet,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8,
                  letterSpacing: 1.2,
                ),
              ),
              pw.Text(
                '${confidencePct.toStringAsFixed(1)}%',
                style: pw.TextStyle(
                  color: color,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 22,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          // Tick-scaled confidence bar.
          pw.Stack(
            children: [
              pw.Container(
                height: 10,
                decoration: pw.BoxDecoration(
                  color: _kCardBgSoft,
                  borderRadius: pw.BorderRadius.circular(5),
                ),
              ),
              pw.LayoutBuilder(
                builder: (ctx, constraints) {
                  final w =
                      (constraints?.maxWidth ?? 0) * confidencePct / 100;
                  return pw.Container(
                    width: w,
                    height: 10,
                    decoration: pw.BoxDecoration(
                      color: color,
                      borderRadius: pw.BorderRadius.circular(5),
                    ),
                  );
                },
              ),
            ],
          ),
          pw.SizedBox(height: 5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('0%',
                  style:
                      pw.TextStyle(fontSize: 7, color: _kTextMuted)),
              pw.Text('25',
                  style:
                      pw.TextStyle(fontSize: 7, color: _kTextMuted)),
              pw.Text('50',
                  style:
                      pw.TextStyle(fontSize: 7, color: _kTextMuted)),
              pw.Text('75',
                  style:
                      pw.TextStyle(fontSize: 7, color: _kTextMuted)),
              pw.Text('100%',
                  style:
                      pw.TextStyle(fontSize: 7, color: _kTextMuted)),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Container(height: 0.5, color: _kCardBgSoft),
          pw.SizedBox(height: 10),
          pw.Text(
            description,
            style: pw.TextStyle(
              fontSize: 10,
              color: _kTextDark,
              lineSpacing: 2.5,
            ),
          ),
        ],
      ),
    );
  }

  /// Metadata as a 2×N grid of tiles, each with a coloured top accent
  /// to give the page a touch of rhythm.
  pw.Widget _metadataGrid(LesionAnalysis a, String date) {
    final entries = <(String, String, PdfColor)>[
      ('Body region'.tr, a.bodyRegion ?? '—', _kBrandViolet),
      ('Captured at'.tr, date, _kBrandSky),
      if (a.distanceCm != null)
        ('Distance'.tr, '${a.distanceCm!.toStringAsFixed(1)} cm',
            _kBrandOrange),
      if (a.imageHash != null)
        ('Image SHA-256'.tr, '${a.imageHash!.substring(0, 16)}…',
            _kBrandPink),
    ];
    return pw.Wrap(
      spacing: 10,
      runSpacing: 10,
      children: entries
          .map((e) => pw.Container(
                width: 244,
                decoration: pw.BoxDecoration(
                  color: _kCardBg,
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Container(
                      height: 4,
                      decoration: pw.BoxDecoration(
                        color: e.$3,
                        borderRadius: const pw.BorderRadius.only(
                          topLeft: pw.Radius.circular(12),
                          topRight: pw.Radius.circular(12),
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            e.$1.toUpperCase(),
                            style: pw.TextStyle(
                              fontSize: 8,
                              letterSpacing: 0.8,
                              color: e.$3,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            e.$2,
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: _kTextDark,
                            ),
                          ),
                        ],
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
      padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: pw.BoxDecoration(
        color: _kBrandVioletDeep,
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 6,
                height: 6,
                decoration: pw.BoxDecoration(
                  color: _kBrandLilac,
                  shape: pw.BoxShape.circle,
                ),
              ),
              pw.SizedBox(width: 7),
              pw.Text(
                'TRIAGE-ONLY DISCLAIMER'.tr,
                style: pw.TextStyle(
                  fontSize: 7,
                  letterSpacing: 1.0,
                  color: _kBrandLilac,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            ('This report was generated by skeen on-device AI for triage '
            'support only. It does not replace a clinical diagnosis. '
            'Consult a licensed dermatologist for any concerning lesion.').tr,
            style: pw.TextStyle(
              fontSize: 8,
              color: _kCardBg,
              fontStyle: pw.FontStyle.italic,
              lineSpacing: 2,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                '${'Analysis ID'.tr}  $analysisId',
                style: pw.TextStyle(
                  fontSize: 7,
                  color: _kBrandLilac,
                ),
              ),
              pw.Text(
                'skeen · ${DateFormat('y').format(DateTime.now())}',
                style: pw.TextStyle(
                  fontSize: 7,
                  color: _kBrandLilac,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
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
        return 'High Risk Detected'.tr;
      case WarningLevel.caution:
        return 'Medium Risk Detected'.tr;
      case WarningLevel.reassuring:
        return 'Low Risk Detected'.tr;
    }
  }

  String _riskDescription(WarningLevel level) {
    switch (level) {
      case WarningLevel.alert:
        return ('High-risk patterns identified. Urgent clinical review is '
                'strongly recommended. Please consult a dermatologist.')
            .tr;
      case WarningLevel.caution:
        return ('Atypical patterns identified. Clinical review suggested '
                'based on visual analysis markers.')
            .tr;
      case WarningLevel.reassuring:
        return ('No concerning patterns identified. Continue routine '
                'self-monitoring and periodic dermatological check-ups.')
            .tr;
    }
  }
}

