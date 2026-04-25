import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_success_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/permissions_screen.dart';
import '../../features/auth/presentation/screens/profile_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/registration_success_screen.dart';
import '../../features/auth/presentation/screens/terms_screen.dart';
import '../../features/detection/presentation/screens/calibrate_screen.dart';
import '../../features/detection/presentation/screens/scan_a_mole_screen.dart';
import '../../features/detection/presentation/screens/upload_photo_screen.dart';
import '../../features/experts/presentation/screens/experts_screen.dart';
import '../../features/patient/presentation/screens/body_map_screen.dart';
import '../../features/patient/presentation/screens/history_screen.dart';
import '../../features/patient/presentation/screens/home_screen.dart';
import '../../features/patient/presentation/screens/reminder_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
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
        path: '/onboarding/terms',
        name: 'onboarding-terms',
        builder: (context, state) => const TermsScreen(),
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

      // Detection context (entered from home / center FAB)
      GoRoute(
        path: '/scan',
        name: 'scan-a-mole',
        builder: (context, state) => const ScanAMoleScreen(),
      ),
      GoRoute(
        path: '/upload',
        name: 'upload-photo',
        builder: (context, state) => const UploadPhotoScreen(),
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
      ),
    ],
  );
});
