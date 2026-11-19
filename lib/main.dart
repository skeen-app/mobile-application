import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
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
  // H08: load es/en date symbols so dates follow the UI language.
  await initializeDateFormatting();

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
  StreamSubscription<void>? _scanStoreSub;
  Timer? _scanStoreDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // H02 (QA cycle 1): History, body map and the pending badge used to
    // refresh only where a screen remembered to invalidate them (the
    // gallery flow never did), so new scans, "Not synced" rows and
    // deletions appeared only after an app restart. Every write to the
    // local scan store now funnels through one listener. Short debounce
    // so a burst (save + markUploaded) triggers a single refetch.
    final scanStore = ref.read(lesionRepositoryProvider);
    if (scanStore is SecureLesionRepository) {
      _scanStoreSub = scanStore.changes.listen((_) {
        _scanStoreDebounce?.cancel();
        _scanStoreDebounce = Timer(const Duration(milliseconds: 150), () {
          if (!mounted) return;
          ref.invalidate(pendingScanCountProvider);
          ref.invalidate(scanHistoryProvider);
          ref.invalidate(lesionSummariesProvider);
        });
      });
    }

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
      //
      // The onTap callback receives the system tap on a fired reminder
      // and routes the user to the in-app notifications list — without
      // it the OS notification would still show, but tapping it would
      // do nothing beyond opening the app.
      await ref.read(localNotificationServiceProvider).initialize(
        onTap: (id, payload) {
          try {
            // The router is the source of truth — pushNamed instead of
            // go so the back button returns the user to wherever they
            // were before they tapped the notification.
            ref.read(appRouterProvider).pushNamed('notifications');
          } catch (e, st) {
            AppLogger.warning(
              'onTap reminder route failed: $e',
              tag: 'main',
            );
            if (kDebugMode) debugPrint('$st');
          }
        },
      );
      ref.read(remindersControllerProvider);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh the Firebase ID token FIRST — every other resume task
      // (sync, reminder reconciliation, future API calls) authenticates
      // against /api/v1/* with that token. Firebase IDs expire after 1h,
      // so without this an app that's been backgrounded for a couple of
      // hours starts the foreground burst with a 401 on the very first
      // /scans call (the orchestrator then silently aborts the upload
      // batch). Best-effort: a refresh failure only logs, doesn't crash.
      ref.read(authControllerProvider.notifier).refreshSession();
      ref.read(syncOrchestratorProvider).syncNow(reason: 'foreground');
      // Reconcile past-due reminders the moment we come back to
      // foreground. Without this, a reminder that fired while the app
      // was backgrounded (and the OS notification appeared) wouldn't
      // produce an in-app banner when the user opens skeen — they'd
      // just see it in the activity log on next launch.
      ref.read(remindersControllerProvider.notifier).reconcile();
    }
  }

  @override
  void dispose() {
    _scanStoreDebounce?.cancel();
    _scanStoreSub?.cancel();
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
