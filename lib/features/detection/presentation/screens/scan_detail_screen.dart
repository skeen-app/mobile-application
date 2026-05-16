import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../../../core/logger/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/providers.dart';
import '../../application/sync_orchestrator.dart';
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

      // Path 1: fully local row (captured on this device or already had
      // its image rehydrated). Render straight away.
      if (analysis != null && analysis.imageBytes != null) {
        if (mounted) {
          setState(() {
            _analysis = analysis;
            _imageBytes = analysis.imageBytes;
            _loading = false;
          });
        }
        return;
      }

      // Path 2: local metadata exists (rehydrated from the cloud history
      // fetch) but the image bytes are not on disk — pull the JPEG from
      // the signed URL and present the rich detail card with the
      // synthesized analysis we already have locally.
      final url = widget.remoteImageUrl;
      Uint8List? cloudImage;
      if (url != null && url.isNotEmpty) {
        try {
          final res = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 20));
          if (res.statusCode >= 200 && res.statusCode < 300) {
            cloudImage = res.bodyBytes;
          }
        } catch (e) {
          AppLogger.warning('ScanDetail: image fetch failed: $e',
              tag: 'ScanDetail');
        }
      }

      if (analysis != null && cloudImage != null) {
        if (mounted) {
          setState(() {
            _analysis = analysis;
            _imageBytes = cloudImage;
            _loading = false;
          });
        }
        return;
      }

      // Path 3: nothing local AND no remote URL was passed (e.g. the
      // user deep-linked into the route). Fall back to fetching the
      // scan from the cloud API, then upsert it locally so subsequent
      // opens take Path 2.
      try {
        final token = ref.read(authControllerProvider).token?.value;
        if (token != null) {
          final remote = await ref
              .read(scansApiProvider)
              .getScan(token: token, scanId: widget.scanId);
          await repo.upsertCloudSnapshot(remote);
          final hydrated =
              await repo.findById(widget.scanId, includeImage: false);
          Uint8List? image = cloudImage;
          if (image == null &&
              remote.imageDownloadUrl != null &&
              remote.imageDownloadUrl!.isNotEmpty) {
            try {
              final res = await http
                  .get(Uri.parse(remote.imageDownloadUrl!))
                  .timeout(const Duration(seconds: 20));
              if (res.statusCode >= 200 && res.statusCode < 300) {
                image = res.bodyBytes;
              }
            } catch (e) {
              AppLogger.warning(
                'ScanDetail: fallback image fetch failed: $e',
                tag: 'ScanDetail',
              );
            }
          }
          if (hydrated != null && image != null) {
            if (mounted) {
              setState(() {
                _analysis = hydrated;
                _imageBytes = image;
                _loading = false;
              });
            }
            return;
          }
        }
      } catch (e) {
        AppLogger.warning('ScanDetail: cloud fallback failed: $e',
            tag: 'ScanDetail');
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
