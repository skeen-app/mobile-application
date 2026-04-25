import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_star_field.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/environment_providers.dart';
import '../../application/lesion_summary_providers.dart';
import '../../domain/body_region.dart';
import '../../domain/environment_reading.dart';
import '../../domain/lesion_summary.dart';
import '../../infrastructure/services/location_service.dart';
import '../widgets/body_map_section.dart';
import '../widgets/home_greeting.dart';
import '../widgets/quick_action_tile.dart';
import '../widgets/scan_a_mole_card.dart';
import '../widgets/temperature_card.dart';

/// Home dashboard — Patient bounded context.
///
/// Composes the greeting, primary scan CTA, quick actions, environment
/// reading, body-map preview and the shared bottom nav. Routes for the
/// secondary surfaces (scan, upload, reminder, body map full view) are wired
/// through `go_router` named destinations declared in `app_router.dart`.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final environment = ref.watch(environmentProvider);
    final summariesAsync = ref.watch(lesionSummariesProvider);
    final countsAsync = ref.watch(lesionGroupCountsProvider);
    final firstName = ref.watch(
      authControllerProvider.select((s) => s.user?.name),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.55,
                child: SkeenStarField(seed: 19, density: 16),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        HomeGreeting(
                          firstName: firstName,
                          hasNotifications: true,
                          onNotificationsTap: () {},
                        ),
                        const SizedBox(height: 22),
                        ScanAMoleCard(
                          onPressed: () => context.pushNamed('scan-a-mole'),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: QuickActionTile(
                                title: 'Upload a photo',
                                subtitle: 'from your gallery',
                                iconAsset:
                                    'assets/images/home/upload_icon.svg',
                                iconBackgroundColor: const Color(0xFF172F5A),
                                iconColor: AppColors.turquesa,
                                onPressed: () =>
                                    context.pushNamed('upload-photo'),
                              ),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: QuickActionTile(
                                title: 'Reminder',
                                subtitle: 'set up a check-in',
                                iconAsset:
                                    'assets/images/home/calendar_icon.svg',
                                iconBackgroundColor: const Color(0xFF4C1A47),
                                iconColor: AppColors.fucsia,
                                onPressed: () =>
                                    context.pushNamed('reminder'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _TemperatureSlot(environment: environment),
                        const SizedBox(height: 28),
                        _BodyMapSlot(
                          summaries: summariesAsync,
                          counts: countsAsync,
                          onCompleteView: () =>
                              context.pushNamed('body-map'),
                          onAddNew: () => context.pushNamed('scan-a-mole'),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                SkeenBottomNav(
                  activeTab: SkeenNavTab.home,
                  onTabSelected: (tab) => _onTabSelected(context, tab),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onTabSelected(BuildContext context, SkeenNavTab tab) {
    switch (tab) {
      case SkeenNavTab.home:
        return;
      case SkeenNavTab.history:
        context.goNamed('history');
      case SkeenNavTab.scan:
        context.pushNamed('scan-a-mole');
      case SkeenNavTab.experts:
        context.goNamed('experts');
      case SkeenNavTab.profile:
        context.goNamed('profile');
    }
  }
}

class _TemperatureSlot extends StatelessWidget {
  const _TemperatureSlot({required this.environment});
  final AsyncValue<EnvironmentReading> environment;

  @override
  Widget build(BuildContext context) {
    return environment.when(
      data: (reading) => TemperatureCard.loaded(reading: reading),
      loading: () => const TemperatureCard.loading(),
      error: (error, _) => TemperatureCard.error(message: _describe(error)),
    );
  }

  String _describe(Object error) {
    if (error is LocationPermissionDeniedException) {
      return 'Enable location to see your local UV index';
    }
    if (error is LocationServicesDisabledException) {
      return 'Location services are off on this device';
    }
    return 'Could not load weather right now';
  }
}

class _BodyMapSlot extends StatelessWidget {
  const _BodyMapSlot({
    required this.summaries,
    required this.counts,
    required this.onCompleteView,
    required this.onAddNew,
  });

  final AsyncValue<List<LesionSummary>> summaries;
  final AsyncValue<Map<BodyRegionGroup, int>> counts;
  final VoidCallback onCompleteView;
  final VoidCallback onAddNew;

  @override
  Widget build(BuildContext context) {
    final summariesData = summaries.valueOrNull ?? const <LesionSummary>[];
    final countsData = counts.valueOrNull ??
        <BodyRegionGroup, int>{
          BodyRegionGroup.head: 0,
          BodyRegionGroup.chest: 0,
          BodyRegionGroup.legs: 0,
        };
    return BodyMapSection(
      summaries: summariesData,
      counts: countsData,
      onCompleteView: onCompleteView,
      onAddNew: onAddNew,
    );
  }
}
