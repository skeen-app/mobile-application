import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/permissions_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/registration_success_screen.dart';
import '../../features/auth/presentation/screens/terms_screen.dart';

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
    ],
  );
});
