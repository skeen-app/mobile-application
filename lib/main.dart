import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/localization/locale_controller.dart';
import 'core/logger/app_logger.dart';

import 'core/notifications/in_app_banner.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/detection/application/detection_controller.dart';
import 'features/detection/application/providers.dart';
import 'features/detection/application/sync_orchestrator.dart';
import 'features/detection/infrastructure/secure_lesion_repository.dart';
import 'features/patient/application/lesion_summary_providers.dart';
import 'features/patient/application/scan_history_providers.dart';
import 'features/reminders/application/reminders_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // Federated sign-in (Google) is Android-only in this iteration. On
  // iOS the GoogleService-Info.plist isn't shipped yet so we skip the
  // Firebase mobile SDK init there to avoid crashes — the email +
  // password flow keeps working untouched.
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Firebase.initializeApp();
    } catch (e, st) {
      AppLogger.error(
        'Firebase mobile SDK init failed (Google sign-in disabled)',
        tag: 'main',
        error: e,
        stackTrace: st,
      );
    }
  }

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

    // Session-boundary purge — when the authenticated user changes
    // (sign-out, or login as a different account), every row in the
    // local encrypted scan DB must go. Otherwise the next session sees
    // a stale "pending sync" badge, body-map dots, or even uploads the
    // previous user's offline rows under the new token.
    //
    // The previous→next pair filters out the initial hydrate (null→A is
    // expected on a fresh launch and must NOT purge). Only real session
    // transitions (A→null, A→B, null→B-after-prior-A) trigger the wipe.
    ref.listenManual<String?>(
      authControllerProvider.select((s) => s.user?.id),
      (previous, next) async {
        if (previous == next) return;
        if (previous == null) return; // initial hydrate, no prior session
        AppLogger.info(
          'Session boundary detected ($previous → $next) — '
          'purging local scan database',
          tag: 'SessionPurge',
        );
        try {
          final repo = ref.read(lesionRepositoryProvider);
          if (repo is SecureLesionRepository) {
            await repo.initialize();
          }
          await repo.clearAll();
          ref.invalidate(pendingScanCountProvider);
          ref.invalidate(scanHistoryProvider);
          ref.invalidate(lesionSummariesProvider);
        } catch (e, st) {
          AppLogger.error(
            'Failed to purge local scan database on session boundary',
            tag: 'SessionPurge',
            error: e,
            stackTrace: st,
          );
        }
      },
    );

    // Fire-and-forget: kick the offline sync after the first frame so
    // the splash isn't blocked. The orchestrator no-ops when the user
    // has no session yet — it'll re-run on auth + on resume.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(syncOrchestratorProvider).start();
      // Initialise the OS notification plugin so any scheduled
      // reminder fires even when the app is closed. Reading the
      // controller provider also triggers reconciliation of past-due
      // reminders into the activity log.
      await ref.read(localNotificationServiceProvider).initialize();
      ref.read(remindersControllerProvider);
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
    final locale = ref.watch(localeControllerProvider);

    return MaterialApp.router(
      key: ValueKey(locale),
      title: 'skeen'.tr,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      locale: locale,
      supportedLocales: const [
        Locale('en', ''),
        Locale('es', ''),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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
