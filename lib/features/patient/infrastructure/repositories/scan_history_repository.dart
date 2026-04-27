import '../../domain/body_region.dart';
import '../../domain/risk_level.dart';
import '../../domain/scan_history_entry.dart';

/// Read-side port for the scan history list.
///
/// The mock implementation seeds a deterministic dataset so the UI is
/// reviewable without a backend. The future HTTP implementation maps
/// `GET /me/scan-history` 1:1 onto this contract.
abstract class ScanHistoryRepository {
  Future<List<ScanHistoryEntry>> findAll();
}

class MockScanHistoryRepository implements ScanHistoryRepository {
  const MockScanHistoryRepository();

  @override
  Future<List<ScanHistoryEntry>> findAll() async {
    // Tiny delay so loading states are visible during development.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return _seed;
  }

  // Sorted newest-first; dates are stable so the list looks identical on
  // every cold start during development.
  static final List<ScanHistoryEntry> _seed = [
    ScanHistoryEntry(
      id: 'scan_001',
      bodyPartLabel: 'Chest',
      region: BodyRegion.chest,
      riskLevel: RiskLevel.high,
      scannedAt: DateTime(2026, 4, 19),
    ),
    ScanHistoryEntry(
      id: 'scan_002',
      bodyPartLabel: 'Right Forearm',
      region: BodyRegion.rightArm,
      riskLevel: RiskLevel.low,
      scannedAt: DateTime(2026, 4, 4),
    ),
    ScanHistoryEntry(
      id: 'scan_003',
      bodyPartLabel: 'Upper Back',
      region: BodyRegion.back,
      riskLevel: RiskLevel.medium,
      scannedAt: DateTime(2026, 3, 12),
    ),
    ScanHistoryEntry(
      id: 'scan_004',
      bodyPartLabel: 'Scalp',
      region: BodyRegion.head,
      riskLevel: RiskLevel.medium,
      scannedAt: DateTime(2026, 3, 1),
    ),
    ScanHistoryEntry(
      id: 'scan_005',
      bodyPartLabel: 'Left Leg',
      region: BodyRegion.leftLeg,
      riskLevel: RiskLevel.low,
      scannedAt: DateTime(2026, 2, 5),
    ),
    ScanHistoryEntry(
      id: 'scan_006',
      bodyPartLabel: 'Right Calf',
      region: BodyRegion.rightLeg,
      riskLevel: RiskLevel.low,
      scannedAt: DateTime(2026, 1, 20),
    ),
    ScanHistoryEntry(
      id: 'scan_007',
      bodyPartLabel: 'Left Cheek',
      region: BodyRegion.head,
      riskLevel: RiskLevel.high,
      scannedAt: DateTime(2025, 12, 18),
    ),
    ScanHistoryEntry(
      id: 'scan_008',
      bodyPartLabel: 'Lower Back',
      region: BodyRegion.back,
      riskLevel: RiskLevel.low,
      scannedAt: DateTime(2025, 11, 30),
    ),
    ScanHistoryEntry(
      id: 'scan_009',
      bodyPartLabel: 'Left Shoulder',
      region: BodyRegion.leftArm,
      riskLevel: RiskLevel.medium,
      scannedAt: DateTime(2025, 11, 4),
    ),
    ScanHistoryEntry(
      id: 'scan_010',
      bodyPartLabel: 'Neck',
      region: BodyRegion.head,
      riskLevel: RiskLevel.low,
      scannedAt: DateTime(2025, 10, 22),
    ),
  ];
}
