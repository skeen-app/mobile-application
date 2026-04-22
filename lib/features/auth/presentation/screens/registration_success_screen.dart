import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_auth_header.dart';
import '../../../../core/widgets/skeen_button.dart';
import '../../application/auth_controller.dart';

class RegistrationSuccessScreen extends ConsumerWidget {
  const RegistrationSuccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;

    if (user == null) {
      // Guard against direct navigation without a registered user in state.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/register');
      });
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: SizedBox.shrink(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                const SkeenAuthHeader(),
                const SizedBox(height: 24),
                const Text(
                  'Your information',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.22,
                    color: AppColors.violetaClaro,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please confirm the details below before continuing.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    height: 1.4,
                    letterSpacing: -0.16,
                    color: AppColors.hintText,
                  ),
                ),
                const SizedBox(height: 24),
                _ReadOnlyField(label: 'Name', value: user.name),
                const SizedBox(height: 16),
                _ReadOnlyField(label: 'Last Name', value: user.lastName),
                const SizedBox(height: 16),
                _ReadOnlyField(label: 'DNI', value: user.dni),
                const SizedBox(height: 16),
                _ReadOnlyField(label: 'Email', value: user.email),
                const SizedBox(height: 16),
                _ReadOnlyField(label: 'Phone Number', value: user.phone),
                const SizedBox(height: 16),
                const _ReadOnlyField(label: 'Password', value: '••••••••••••'),
                const SizedBox(height: 32),
                SkeenButton.primary(
                  label: 'Continue',
                  onPressed: () => context.go('/onboarding/permissions'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              letterSpacing: -0.12,
              color: Color(0xFF817691),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              letterSpacing: -0.16,
              color: AppColors.violetaClaro,
            ),
          ),
        ],
      ),
    );
  }
}
