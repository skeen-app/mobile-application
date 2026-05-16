import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Full-screen image viewer with dark overlay, pinch-to-zoom and tap-to-dismiss.
///
/// Supports two image sources:
///   - `FullScreenImageViewer.network(url)` — loads from a remote URL.
///   - `FullScreenImageViewer.memory(bytes)` — renders raw bytes (scan JPEGs).
///
/// Launched via the static [show] helpers which push a transparent route with
/// a Hero-style fade-scale animation.
class FullScreenImageViewer extends StatefulWidget {
  const FullScreenImageViewer._({
    this.imageUrl,
    this.imageBytes,
    this.heroTag,
  });

  final String? imageUrl;
  final Uint8List? imageBytes;
  final String? heroTag;

  // ── Static launchers ────────────────────────────────────────────────

  /// Open a network image full-screen.
  static void showNetwork(
    BuildContext context, {
    required String url,
    String? heroTag,
  }) {
    Navigator.of(context).push(_fadeRoute(
      FullScreenImageViewer._(imageUrl: url, heroTag: heroTag),
    ));
  }

  /// Open an in-memory image (scan bytes) full-screen.
  static void showMemory(
    BuildContext context, {
    required Uint8List bytes,
    String? heroTag,
  }) {
    Navigator.of(context).push(_fadeRoute(
      FullScreenImageViewer._(imageBytes: bytes, heroTag: heroTag),
    ));
  }

  static Route<void> _fadeRoute(FullScreenImageViewer child) {
    return PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      pageBuilder: (_, _, _) => child,
      transitionsBuilder: (_, animation, _, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
    );
  }

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  final _transformController = TransformationController();

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Dismiss on tap of the background
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          // Zoomable image
          Center(
            child: InteractiveViewer(
              transformationController: _transformController,
              minScale: 0.5,
              maxScale: 4.0,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildImage(),
                ),
              ),
            ),
          ),
          // Close button
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: Material(
              color: AppColors.indigo.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(99),
              child: InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: () => Navigator.of(context).pop(),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(
                    Icons.close_rounded,
                    size: 22,
                    color: AppColors.violetaClaro,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    if (widget.imageBytes != null) {
      return Image.memory(
        widget.imageBytes!,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _errorPlaceholder(),
      );
    }
    if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
      return Image.network(
        widget.imageUrl!,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: 200,
            height: 200,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                        progress.expectedTotalBytes!
                    : null,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.violetaClaro,
                ),
              ),
            ),
          );
        },
        errorBuilder: (_, _, _) => _errorPlaceholder(),
      );
    }
    return _errorPlaceholder();
  }

  Widget _errorPlaceholder() {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: AppColors.indigo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 48,
          color: AppColors.hintText,
        ),
      ),
    );
  }
}
