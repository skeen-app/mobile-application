import 'package:skeen/core/localization/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/scan_thumbnail_provider.dart';
import '../../domain/risk_level.dart';
import '../../domain/scan_history_entry.dart';
import 'body_part_icon.dart';

/// One row of the history list. Renders the captured photo (or a tinted
/// placeholder), the body-part label and date, the risk pill, and a
/// trailing chevron for affordance.
class ScanHistoryCard extends StatelessWidget {
  const ScanHistoryCard({
    super.key,
    required this.entry,
    required this.onTap,
  });

  final ScanHistoryEntry entry;
  final VoidCallback onTap;

  static const Color _cardBg = Color(0xFF1C1A44);
  static const Color _cardBorder = Color(0x1A4A4455); // rgba(74,68,85,0.1)
  static const Color _thumbBg = Color(0xFF0A0732);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(21),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _cardBorder),
          ),
          child: Row(
            children: [
              _Thumbnail(entry: entry),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.bodyPartLabel.tr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                              height: 1.25,
                              color: Color(0xFFE2DFFF),
                            ),
                          ),
                        ),
                        if (entry.syncStatus != ScanSyncStatus.synced) ...[
                          const SizedBox(width: 8),
                          _SyncStatusBadge(status: entry.syncStatus),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(entry.scannedAt),
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontSize: 14,
                        height: 1.43,
                        color: Color(0xFFCCC3D8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _RiskPill(level: entry.riskLevel),
                  const SizedBox(height: 8),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Color(0xFF958DA1),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime at) => formatLongDate(at);
}

/// Crops + decrypts the saved scan locally so the history miniature
/// shows the actual lunar (centroid-cropped). Falls back, in order:
///   1. Cropped mole thumbnail from the local encrypted store.
///   2. Cloud signed-URL thumbnail (full image, when only the cloud
///      copy is available — e.g. signed in on a fresh device).
///   3. Tinted placeholder with the body-part icon.
class _Thumbnail extends ConsumerWidget {
  const _Thumbnail({required this.entry});
  final ScanHistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cropped = ref.watch(scanThumbnailProvider(entry.id));
    final remoteUrl = entry.thumbnailUrl;

    Widget child;
    if (cropped.value != null) {
      child = Image.memory(
        cropped.value!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else if (cropped.isLoading) {
      child = remoteUrl != null && remoteUrl.isNotEmpty
          ? Image.network(
              remoteUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _Placeholder(entry: entry),
            )
          : _Placeholder(entry: entry);
    } else if (remoteUrl != null && remoteUrl.isNotEmpty) {
      child = Image.network(
        remoteUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _Placeholder(entry: entry),
      );
    } else {
      child = _Placeholder(entry: entry);
    }

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: ScanHistoryCard._thumbBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: entry.region.group.accent.withValues(alpha: 0.25),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.entry});
  final ScanHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            entry.region.group.accent.withValues(alpha: 0.18),
            ScanHistoryCard._thumbBg,
          ],
        ),
      ),
      child: Center(
        child: BodyPartIcon.fromLabel(
          label: entry.bodyPartLabel,
          color: entry.region.group.accent.withValues(alpha: 0.95),
          size: 28,
        ),
      ),
    );
  }
}

/// Pill that surfaces the cloud-sync state of a scan. Two variants:
///   • Pending   — purple, cloud-upload icon. The row is queued and will
///                 upload as soon as the device gets back online.
///   • Not synced — grey, cloud-off icon. The user disabled cloud sync,
///                  so the row is permanently on-device only.
class _SyncStatusBadge extends StatelessWidget {
  const _SyncStatusBadge({required this.status});

  final ScanSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final isPending = status == ScanSyncStatus.pending;
    final fg = isPending ? const Color(0xFF9B8DEB) : const Color(0xFF8A8295);
    final bg = isPending ? const Color(0xFF2A1F5C) : const Color(0xFF272235);
    final border =
        isPending ? const Color(0xFF6B58C4) : const Color(0xFF4A4455);
    final icon = isPending
        ? Icons.cloud_upload_outlined
        : Icons.cloud_off_outlined;
    final label = isPending ? 'Pending'.tr : 'Not synced'.tr;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 9,
              letterSpacing: 0.2,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskPill extends StatelessWidget {
  const _RiskPill({required this.level});
  final RiskLevel level;

  @override
  Widget build(BuildContext context) {
    final color = level.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        level.label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 12,
          height: 1.33,
          letterSpacing: 0.3,
          color: color,
        ),
      ),
    );
  }
}

