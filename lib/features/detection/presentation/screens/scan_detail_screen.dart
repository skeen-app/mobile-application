import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../../../core/logger/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../application/providers.dart';
import '../../domain/lesion_analysis.dart';
import 'triage_result_screen.dart';

/// History row → details screen. Loads the encrypted local copy first
/// (instant + private), and if the row only exists in the cloud falls
/// back to the signed download URL embedded in the history entry.
class ScanDetailScreen extends ConsumerStatefulWidget {
  const ScanDetailScreen({
    super.key,
    required this.scanId,
    this.remoteImageUrl,
    this.bodyRegion,
  });

  final String scanId;
  final String? remoteImageUrl;
  final String? bodyRegion;

  @override
  ConsumerState<ScanDetailScreen> createState() => _ScanDetailScreenState();
}

class _ScanDetailScreenState extends ConsumerState<ScanDetailScreen> {
  bool _loading = true;
  Uint8List? _imageBytes;
  LesionAnalysis? _analysis;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(lesionRepositoryProvider);
      await repo.initialize();
      final analysis = await repo.findById(widget.scanId, includeImage: true);
      if (analysis != null) {
        if (mounted) {
          setState(() {
            _analysis = analysis;
            _imageBytes = analysis.imageBytes;
            _loading = false;
          });
        }
        return;
      }

      // Fallback: cloud-only row → fetch the signed image URL directly.
      final url = widget.remoteImageUrl;
      if (url != null && url.isNotEmpty) {
        final res = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 20));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          if (mounted) {
            setState(() {
              _imageBytes = res.bodyBytes;
              _loading = false;
            });
          }
          return;
        }
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load this scan';
        });
      }
    } catch (e, st) {
      AppLogger.error('ScanDetail: load failed',
          tag: 'ScanDetail', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load scan';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(
            valueColor:
                AlwaysStoppedAnimation<Color>(AppColors.violetaClaro),
          ),
        ),
      );
    }

    final analysis = _analysis;
    final imageBytes = _imageBytes;
    if (analysis != null && imageBytes != null) {
      // Reuse the rich triage layout — the same widget the user saw right
      // after capture. No PDF code duplicated here either.
      return TriageResultScreen(
        analysisId: widget.scanId,
        capturedImageBytes: imageBytes,
        bodyRegion: widget.bodyRegion ?? analysis.bodyRegion,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.image_not_supported_outlined,
                  color: AppColors.hintText, size: 48),
              const SizedBox(height: 16),
              Text(
                _error ?? 'Scan unavailable',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: AppColors.violetaClaro,
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/home'),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
