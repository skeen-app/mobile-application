import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_button.dart';
import '../../../../core/widgets/skeen_star_field.dart';
import '../../../../core/widgets/skeen_step_indicator.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const List<_Clause> _clauses = [
    _Clause(
      title: 'Lorem ipsum',
      body:
          'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod '
          'tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim '
          'veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea '
          'commodo consequat.',
    ),
    _Clause(
      title: 'Dolor sit amet',
      body:
          'Duis aute irure dolor in reprehenderit in voluptate velit esse cillum '
          'dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non '
          'proident, sunt in culpa qui officia deserunt mollit anim id est laborum.',
    ),
    _Clause(
      title: 'Lorem ipsum',
      body:
          'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod '
          'tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim '
          'veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea '
          'commodo consequat.',
    ),
    _Clause(
      title: 'Dolor sit amet',
      body:
          'Duis aute irure dolor in reprehenderit in voluptate velit esse cillum '
          'dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non '
          'proident, sunt in culpa qui officia deserunt mollit anim id est laborum.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned(
              top: 90,
              left: 0,
              right: 0,
              height: 160,
              child: SkeenStarField(seed: 33, density: 14),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  const SkeenStepIndicator(currentStep: 2, totalSteps: 2),
                  const SizedBox(height: 40),
                  const _TermsHeading(),
                  const SizedBox(height: 32),
                  Expanded(
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: _clauses.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        return _ClauseTile(
                          index: index + 1,
                          clause: _clauses[index],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SkeenButton.primary(
                    label: 'Accept and continue',
                    onPressed: () => context.go('/home'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TermsHeading extends StatelessWidget {
  const _TermsHeading();

  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: TextAlign.center,
      text: const TextSpan(
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 20,
          height: 1.1,
          letterSpacing: -0.2,
        ),
        children: [
          TextSpan(
            text: 'Terms ',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.violeta,
            ),
          ),
          TextSpan(
            text: '& ',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: AppColors.violetaClaro,
            ),
          ),
          TextSpan(
            text: 'conditions',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: AppColors.naranja,
            ),
          ),
        ],
      ),
    );
  }
}

class _Clause {
  const _Clause({required this.title, required this.body});
  final String title;
  final String body;
}

class _ClauseTile extends StatelessWidget {
  const _ClauseTile({required this.index, required this.clause});

  final int index;
  final _Clause clause;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$index. ${clause.title}',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w500,
            fontSize: 16,
            height: 1.5,
            letterSpacing: -0.16,
            color: AppColors.violetaClaro,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          clause.body,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            height: 1.5,
            letterSpacing: -0.14,
            color: AppColors.hintText,
          ),
        ),
      ],
    );
  }
}
