import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_state.dart';
import '../../features/auth/presentation/screens/complete_profile_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_success_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/notifications_settings_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/permissions_screen.dart';
import '../../features/auth/presentation/screens/personal_information_screen.dart';
import '../../features/auth/presentation/screens/privacy_security_screen.dart';
import '../../features/auth/presentation/screens/profile_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/registration_success_screen.dart';
import '../../features/auth/presentation/screens/terms_screen.dart';
import '../../features/detection/presentation/screens/calibrate_screen.dart';
import '../../features/detection/presentation/screens/scan_detail_screen.dart';
import '../../features/detection/presentation/screens/scan_router_screen.dart';
import '../../features/detection/presentation/screens/triage_result_screen.dart';
import '../../features/detection/presentation/screens/upload_photo_screen.dart';
import '../notifications/notifications_screen.dart';
import '../../features/experts/presentation/screens/experts_screen.dart';
import '../../features/patient/presentation/screens/body_map_screen.dart';
import '../../features/patient/presentation/screens/history_screen.dart';
import '../../features/patient/presentation/screens/home_screen.dart';
import '../../features/patient/presentation/screens/reminder_screen.dart';

/// Locations the router considers part of the unauthenticated funnel.
/// Anything else requires `authStateProvider.isAuthenticated == true` to be
/// reachable; the redirect kicks the user back to `/` otherwise.
const _unauthenticatedRoutes = <String>{
  '/',
  '/login',
  '/register',
  '/register/success',
  '/forgot-password',
  '/forgot-password/success',
  '/onboarding/permissions',
  '/onboarding/calibrate',
  '/onboarding/terms',
  '/onboarding/complete-profile',
};

/// Routes that are *exclusively* for signed-out users — even if the auth
/// state is hydrated we must still bounce them away. The onboarding funnel
/// (permissions / terms) is intentionally excluded because the post-
/// registration flow runs while already authenticated.
const _signedOutOnlyRoutes = <String>{
  '/',
  '/login',
  '/register',
  '/register/success',
  '/forgot-password',
  '/forgot-password/success',
};

bool _isUnauthenticatedLocation(String location) {
  for (final route in _unauthenticatedRoutes) {
    if (location == route || location.startsWith('$route/')) return true;
  }
  return false;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authListenable = _AuthRouterListenable(ref);
  ref.onDispose(authListenable.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: authListenable,
    redirect: (context, state) {
      final isAuthenticated =
          ref.read(authControllerProvider).isAuthenticated;
      final location = state.matchedLocation;
      final goingToUnauthRoute = _isUnauthenticatedLocation(location);

      // Hydrated session opening the app: skip the onboarding /
      // sign-in funnel and land straight on /home so users don't
      // re-see the splash. The post-registration onboarding steps are
      // intentionally NOT in [_signedOutOnlyRoutes], so the
      // register → permissions → terms → home flow keeps working.
      if (isAuthenticated && _signedOutOnlyRoutes.contains(location)) {
        return '/home';
      }

      // Protected route + signed-out → bounce to onboarding. After a
      // backend-confirmed logout this guarantees the back stack cannot
      // resurface authenticated screens (Profile, Home, …).
      if (!isAuthenticated && !goingToUnauthRoute) return '/';

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
        routes: [
          GoRoute(
            path: 'success',
            name: 'register-success',
            builder: (context, state) => const RegistrationSuccessScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/onboarding/permissions',
        name: 'onboarding-permissions',
        builder: (context, state) => const PermissionsScreen(),
      ),
      GoRoute(
        path: '/onboarding/calibrate',
        name: 'onboarding-calibrate',
        builder: (context, state) => const CalibrateScreen(),
      ),
      GoRoute(
        path: '/onboarding/terms',
        name: 'onboarding-terms',
        builder: (context, state) => const TermsScreen(),
      ),
      GoRoute(
        path: '/onboarding/complete-profile',
        name: 'onboarding-complete-profile',
        builder: (context, state) => const CompleteProfileScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        name: 'forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
        routes: [
          GoRoute(
            path: 'success',
            name: 'forgot-password-success',
            builder: (context, state) => const ForgotPasswordSuccessScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/calibrate',
        name: 'calibrate',
        builder: (context, state) => const CalibrateScreen(),
      ),

      // Patient context
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
        routes: [
          GoRoute(
            path: 'body-map',
            name: 'body-map',
            builder: (context, state) => const BodyMapScreen(),
          ),
          GoRoute(
            path: 'reminder',
            name: 'reminder',
            builder: (context, state) => const ReminderScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/history',
        name: 'history',
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: '/notifications',
        name: 'notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),

      // Detection context (entered from home / center FAB). The router
      // screen probes ARKit/ARCore + depth and mounts ArScanScreen when
      // available, falling back to ScanAMoleScreen otherwise.
      GoRoute(
        path: '/scan',
        name: 'scan-a-mole',
        builder: (context, state) => const ScanRouterScreen(),
      ),
      GoRoute(
        path: '/upload',
        name: 'upload-photo',
        builder: (context, state) => const UploadPhotoScreen(),
      ),
      GoRoute(
        path: '/scan/result',
        name: 'triage-result',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return TriageResultScreen(
            analysisId: extra['analysisId'] as String? ?? '',
            capturedImageBytes:
                extra['capturedImageBytes'] as Uint8List? ?? Uint8List(0),
            bodyRegion: extra['bodyRegion'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/scan/detail/:scanId',
        name: 'scan-detail',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return ScanDetailScreen(
            scanId: state.pathParameters['scanId']!,
            remoteImageUrl: extra['remoteImageUrl'] as String?,
            bodyRegion: extra['bodyRegion'] as String?,
          );
        },
      ),

      // Experts (consultation directory)
      GoRoute(
        path: '/experts',
        name: 'experts',
        builder: (context, state) => const ExpertsScreen(),
      ),

      // Profile (Auth-context surface)
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) => const ProfileScreen(),
        routes: [
          GoRoute(
            path: 'personal-information',
            name: 'personal-info',
            builder: (context, state) => const PersonalInformationScreen(),
          ),
          GoRoute(
            path: 'privacy-security',
            name: 'privacy-security',
            builder: (context, state) => const PrivacySecurityScreen(),
          ),
          GoRoute(
            path: 'notification-preferences',
            name: 'notifications-settings',
            builder: (context, state) => const NotificationsSettingsScreen(),
          ),
        ],
      ),
    ],
  );
});

/// Adapter that lets `GoRouter.refreshListenable` react to auth-state
/// changes. Re-evaluates `redirect` whenever `AuthStatus` flips so a
/// successful sign-out instantly bounces the user off protected routes.
class _AuthRouterListenable extends ChangeNotifier {
  _AuthRouterListenable(this._ref) {
    _subscription = _ref.listen<AuthStatus>(
      authControllerProvider.select((s) => s.status),
      (previous, next) {
        if (previous != next) notifyListeners();
      },
      fireImmediately: false,
    );
  }

  final Ref _ref;
  late final ProviderSubscription<AuthStatus> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
