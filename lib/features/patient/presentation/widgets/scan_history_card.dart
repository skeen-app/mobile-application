import 'package:flutter/material.dart';

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
                            entry.bodyPartLabel,
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
                        if (entry.pendingSync) ...[
                          const SizedBox(width: 8),
                          const _PendingSyncBadge(),
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

  static const List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String _formatDate(DateTime at) {
    final day = at.day.toString().padLeft(2, '0');
    return '${_months[at.month - 1]} $day, ${at.year}';
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.entry});
  final ScanHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: ScanHistoryCard._thumbBg,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: entry.thumbnailUrl != null && entry.thumbnailUrl!.isNotEmpty
          ? Image.network(
              entry.thumbnailUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, _, _) => _Placeholder(entry: entry),
            )
          : _Placeholder(entry: entry),
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

class _PendingSyncBadge extends StatelessWidget {
  const _PendingSyncBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1F5C),
        border: Border.all(color: const Color(0xFF6B58C4)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_upload_outlined, size: 10, color: Color(0xFF9B8DEB)),
          SizedBox(width: 4),
          Text(
            'Pending',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 9,
              letterSpacing: 0.2,
              color: Color(0xFF9B8DEB),
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

