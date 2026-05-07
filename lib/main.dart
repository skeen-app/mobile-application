import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/notifications/in_app_banner.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/detection/application/detection_controller.dart';
import 'features/detection/application/sync_orchestrator.dart';
import 'features/patient/application/lesion_summary_providers.dart';
import 'features/patient/application/scan_history_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const SkeenApp(),
    ),
  );
}

class SkeenApp extends ConsumerStatefulWidget {
  const SkeenApp({super.key});

  @override
  ConsumerState<SkeenApp> createState() => _SkeenAppState();
}

class _SkeenAppState extends ConsumerState<SkeenApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Wire the post-capture hook so a fresh scan: (a) refreshes the
    // history + body-map projections, and (b) attempts an immediate
    // upload (no-op when offline / opted out).
    bindPostCaptureHook(() {
      ref.invalidate(pendingScanCountProvider);
      ref.invalidate(scanHistoryProvider);
      ref.invalidate(lesionSummariesProvider);
      ref.read(syncOrchestratorProvider).syncNow(reason: 'post-capture');
    });

    // Fire-and-forget: kick the offline sync after the first frame so
    // the splash isn't blocked. The orchestrator no-ops when the user
    // has no session yet — it'll re-run on auth + on resume.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncOrchestratorProvider).start();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(syncOrchestratorProvider).syncNow(reason: 'foreground');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'skeen',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
      builder: (context, child) {
        // Mounts the in-app banner overlay above every route, including
        // the auth funnel — once a notification is recorded the banner
        // shows wherever the user happens to be.
        return InAppNotificationBannerHost(child: child ?? const SizedBox());
      },
    );
  }
}
