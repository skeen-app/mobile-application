import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../patient/application/lesion_summary_providers.dart';
import '../domain/patient_profile_summary.dart';
import 'auth_controller.dart';

/// Computes the registered-moles count + last-scan date for the profile
/// dashboard from local sources only:
///   - Moles count → on-device lesion repository.
///   - Last scan date → the persisted user record (server populates it on
///     login; the avatar upload flow leaves it untouched).
///
/// No `/me/profile-summary` endpoint is involved.
final profileSummaryProvider =
    FutureProvider<PatientProfileSummary>((ref) async {
  final user = ref.watch(authControllerProvider.select((s) => s.user));
  final lesions = await ref.read(lesionSummaryRepositoryProvider).findAll();
  return PatientProfileSummary(
    registeredMoles: lesions.length,
    lastScanAt: user?.lastScanAt,
  );
});
