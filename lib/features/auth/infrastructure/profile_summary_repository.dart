import '../../patient/infrastructure/repositories/lesion_summary_repository.dart';
import '../domain/patient_profile_summary.dart';
import '../domain/registered_user.dart';
import 'profile_summary_api.dart';

/// Loads the profile dashboard counters with a backend-first strategy:
///
///   1. Try the `GET /me/profile-summary` endpoint (will succeed once it
///      ships). The result is the source of truth.
///   2. On `ProfileSummaryUnavailable` or any network failure, fall back to
///      the local `LesionSummaryRepository` and the persisted user (so the
///      profile screen still renders with sensible numbers offline).
class ProfileSummaryRepository {
  ProfileSummaryRepository({
    required ProfileSummaryApi api,
    required LesionSummaryRepository lesionRepository,
  })  : _api = api,
        _lesionRepository = lesionRepository;

  final ProfileSummaryApi _api;
  final LesionSummaryRepository _lesionRepository;

  Future<PatientProfileSummary> load({
    required String? authToken,
    required RegisteredUser? user,
  }) async {
    if (authToken != null) {
      try {
        return await _api.fetch(authToken: authToken);
      } on ProfileSummaryUnavailable {
        // Endpoint not ready — silently fall through to the local fallback.
      } catch (_) {
        // Network/decoding error — same fallback path.
      }
    }
    final summaries = await _lesionRepository.findAll();
    return PatientProfileSummary(
      registeredMoles: summaries.length,
      lastScanAt: user?.lastScanAt,
    );
  }
}
