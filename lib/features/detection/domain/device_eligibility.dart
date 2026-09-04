import 'package:flutter/foundation.dart';

/// A hardware capability the guided capture arm depends on.
enum EligibilityRequirement {
  /// No usable camera at all — nothing in the flow works.
  camera,

  /// No gyroscope. The stability signal is measured, never inferred from the
  /// image, so without the sensor `CaptureStability` stays `unknown` and the
  /// fail-closed rule holds the shutter shut permanently.
  gyroscope,
}

extension EligibilityRequirementX on EligibilityRequirement {
  String get slug => switch (this) {
        EligibilityRequirement.camera => 'camera',
        EligibilityRequirement.gyroscope => 'gyroscope',
      };
}

/// Result of the start-of-session capability probe.
///
/// Why this exists: a phone without a gyroscope used to sit in the guided arm
/// with the shutter silently locked forever. Fail-closed was the correct
/// behaviour, but being silent was not — the participant simply could not
/// produce a capture, dropped out, and the study recorded nothing about why.
/// Because gyroscope availability correlates with device tier, and device tier
/// correlates with income, that silent failure would have quietly reshaped the
/// sample.
///
/// An exclusion has to be **declared and countable**: the person is told the
/// device cannot run the study, and a row is written saying so.
@immutable
class DeviceEligibility {
  const DeviceEligibility({required this.missing});

  final Set<EligibilityRequirement> missing;

  bool get isEligible => missing.isEmpty;

  bool lacks(EligibilityRequirement requirement) =>
      missing.contains(requirement);

  static const DeviceEligibility eligible =
      DeviceEligibility(missing: <EligibilityRequirement>{});

  @override
  String toString() => isEligible
      ? 'DeviceEligibility(eligible)'
      : 'DeviceEligibility(missing: '
          '${missing.map((r) => r.slug).join(', ')})';
}
