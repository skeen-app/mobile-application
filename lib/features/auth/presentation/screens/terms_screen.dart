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
      title: 'Triage tool, not a medical diagnosis',
      body:
          'skeen is an AI-assisted dermatological triage tool meant for '
          'self-monitoring and early-warning purposes only. The risk '
          'predictions surfaced by the on-device model are heuristic and '
          "MUST NOT be treated as a clinical diagnosis or substitute for "
          'professional medical advice. Always consult a licensed '
          'dermatologist for any concerning lesion, and seek urgent care '
          'whenever a scan is flagged as high risk.',
    ),
    _Clause(
      title: 'Your account & local data',
      body:
          'You are responsible for the accuracy of the information you '
          'provide at registration (name, DNI, email, phone) and for '
          'safeguarding the credentials used to access skeen. Every '
          'lesion photo captured on this device is encrypted at rest '
          'using AES-256 inside the app sandbox and never leaves your '
          'phone unless you explicitly enable cloud sync from Privacy & '
          'Security.',
    ),
    _Clause(
      title: 'Optional cloud sync',
      body:
          'When cloud sync is ON, your scans are uploaded to a private '
          'bucket bound to your account and re-encrypted server-side. '
          'No personally identifiable fields (name, DNI, email, phone) '
          'are written into the scan documents — the cloud copy is '
          'pseudonymous, tied to an opaque user identifier. You may '
          'turn cloud sync off at any time; future scans will then '
          'remain local-only.',
    ),
    _Clause(
      title: 'AR camera, sensors & permissions',
      body:
          'skeen requests access to the camera, photo library, '
          'notifications, location and motion sensors strictly for the '
          'features you enable: assisted scanning (camera, AR sensors), '
          'gallery uploads (photos), reminder alarms (notifications), '
          'and the local UV index on the home dashboard (location). '
          'Each permission can be revoked from system settings — the '
          'app will gracefully degrade or surface a clear "needs '
          'access" prompt where applicable.',
    ),
    _Clause(
      title: 'Insights & external content',
      body:
          'The Insights feed proxies dermatology articles published by '
          'third-party sources (PubMed / NCBI). skeen does not author '
          'this content nor endorse the views of individual researchers; '
          'it is provided for educational reference only. Tapping an '
          'article opens it in your platform browser — you remain '
          'subject to the publisher\'s own terms of use.',
    ),
    _Clause(
      title: 'Reminders & notifications',
      body:
          'skeen schedules local OS notifications based on the reminders '
          'you create. These alarms run on this device only and are not '
          'shared across phones. We never push marketing or '
          'recommendation notifications without an explicit reminder '
          'you scheduled or a direct response to a feature you used '
          '(e.g. confirming a scan was saved).',
    ),
    _Clause(
      title: 'Right to erasure',
      body:
          'You may delete an individual scan from the Mole detail view '
          'or your entire account from Personal Information → Delete '
          'account. Deleting a scan removes the encrypted record from '
          'this device and, when applicable, from the cloud bucket and '
          'metadata index. Account deletion soft-deletes your profile '
          'for audit purposes and hard-deletes your authentication '
          'identity so the credentials can no longer sign in.',
    ),
    _Clause(
      title: 'Acceptance & governing terms',
      body:
          'By tapping "Accept and continue" you confirm that you have '
          'read and agree to these terms, that you understand skeen is '
          'a screening aid and not a medical device, and that any '
          'clinical decision based on scan results is your own '
          'responsibility. These terms are governed by the laws of the '
          'Republic of Peru. We may revise this document; continued use '
          'after a revision implies acceptance of the updated version.',
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
