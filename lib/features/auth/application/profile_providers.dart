import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../patient/application/lesion_summary_providers.dart';
import '../domain/patient_profile_summary.dart';
import '../infrastructure/profile_summary_api.dart';
import '../infrastructure/profile_summary_repository.dart';
import 'auth_controller.dart';

final profileSummaryApiProvider = Provider<ProfileSummaryApi>((ref) {
  final api = ProfileSummaryApi();
  ref.onDispose(api.dispose);
  return api;
});

final profileSummaryRepositoryProvider =
    Provider<ProfileSummaryRepository>((ref) {
  return ProfileSummaryRepository(
    api: ref.watch(profileSummaryApiProvider),
    lesionRepository: ref.watch(lesionSummaryRepositoryProvider),
  );
});

/// Loads the registered-moles count + next-checkup-date for the profile
/// screen. Invalidated by the auth controller after sign-in/out.
final profileSummaryProvider =
    FutureProvider<PatientProfileSummary>((ref) async {
  final auth = ref.watch(authControllerProvider);
  return ref.read(profileSummaryRepositoryProvider).load(
        authToken: auth.token?.value,
        user: auth.user,
      );
});
