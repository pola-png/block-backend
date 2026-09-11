import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'config/environment.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'screens/account_deletion_screen.dart';
import 'screens/auth/sign_in_screen.dart';
import 'screens/auth/sign_up_screen.dart';
import 'screens/safety_standards_screen.dart';
import 'screens/privacy_policy_screen.dart';
import 'screens/about_xapzap_screen.dart';
import 'screens/drafts_screen.dart';
import 'screens/help_support_screen.dart';
import 'screens/premium_screen.dart';
import 'screens/referrals_screen.dart';
import 'screens/saved_posts_screen.dart';
import 'screens/new_chat_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/boost_center_screen.dart';
import 'screens/main_screen.dart';
import 'screens/terms_of_service_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'services/auth_wrapper.dart';
import 'services/backend_service.dart';
import 'services/firebase_service.dart';
import 'services/play_store_update_service.dart';
import 'services/chat_message_cache.dart';
import 'services/chat_preview_cache.dart';
import 'services/chat_prefetch_service.dart';
import 'services/profile_preview_cache.dart';
import 'services/pending_upload_service.dart';
import 'services/avatar_cache.dart';
import 'services/feed_prefetcher.dart';
import 'services/native_ad_preload_service.dart';
import 'services/post_view_retry_queue.dart';
import 'services/network_status_service.dart';
import 'services/realtime_gateway.dart';
import 'services/device_mode_service.dart';
import 'services/navigation_service.dart';
import 'services/ad_gate_service.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';

final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Silence red error UI in release builds.
  FlutterError.onError = (FlutterErrorDetails details) {
    if (kReleaseMode) {
      // In release, avoid showing error overlays; just log.
      Zone.current.handleUncaughtError(
        details.exception,
        details.stack ?? StackTrace.empty,
      );
    } else {
      FlutterError.presentError(details);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (!kReleaseMode) {
      FlutterError.presentError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    }
    return true;
  };
  // Opt into edge-to-edge for Android 15+ and earlier versions.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  await _bootstrapCriticalServices();

  runApp(const XapZapApp());
  unawaited(_bootstrapBackgroundServices());
}

Future<void> _bootstrapCriticalServices() async {
  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {}
  try {
    await Supabase.initialize(
      url: Environment.supabaseUrl,
      anonKey: Environment.supabaseAnonKey,
    );
  } catch (_) {}
  try {
    await BackendService.initialize();
  } catch (_) {}
  if (!kIsWeb && !DeviceModeService.isTv) {
    try {
      await MobileAds.instance.initialize();
      if (kDebugMode) {
        await MobileAds.instance.updateRequestConfiguration(
          RequestConfiguration(
            testDeviceIds: ['93B5FC3B503A1A45170BFE3370D4426F'],
          ),
        );
      }
      // Wait for the App Open Ad to be preloaded (up to 2.5 seconds timeout inside init)
      await XapZapAdGateService.instance.init();
    } catch (_) {}
  }
}

Future<void> _bootstrapBackgroundServices() async {
  try {
    await FirebaseService.initialize();
  } catch (_) {}
  // Initialize caches concurrently to minimize startup I/O latency
  try {
    await Future.wait([
      ChatMessageCache.initialize().catchError((_) {}),
      ChatPreviewCache.initialize().catchError((_) {}),
      ProfilePreviewCache.initialize().catchError((_) {}),
      PendingUploadService.initialize().catchError((_) {}),
    ]);
  } catch (_) {}
  try {
    await PostViewRetryQueue.initialize();
  } catch (_) {}
  try {
    await AvatarCache.initialize();
  } catch (_) {}
  try {
    await NetworkStatusService.initialize();
  } catch (_) {}
  try {
    RealtimeGateway.initialize();
  } catch (_) {}
  if (!kIsWeb && !DeviceModeService.isTv) {
    unawaited(NativeAdPreloadService.warmupFast(maxSlotIndex: 2));
  }
  unawaited(PostViewRetryQueue.flushPending());
  unawaited(BackendService.processNotificationQueue(limit: 5));
  // Start preloading the home feeds in the background so that
  // the HomeScreen can render instantly when opened.
  // On web we skip this to reduce first-load work and rely on
  // HomeScreen to fetch lazily when it mounts.
  if (!kIsWeb) {
    FeedPrefetcher.preloadHomeFeeds();
    unawaited(ChatPrefetchService.preloadInbox());
  }
}

class XapZapApp extends StatefulWidget {
  const XapZapApp({super.key});

  @override
  State<XapZapApp> createState() => _XapZapAppState();
}

class _XapZapAppState extends State<XapZapApp> with WidgetsBindingObserver {
  bool _checkedForUpdate = false;
  bool _isCheckingForUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForAppUpdate();
      XapZapAdGateService.instance.showAppOpenAdIfAvailable();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(PostViewRetryQueue.flushPending());
      XapZapAdGateService.instance.showAppOpenAdIfAvailable();
    }
  }

  Future<void> _checkForAppUpdate() async {
    if (_checkedForUpdate || _isCheckingForUpdate) {
      return;
    }
    _checkedForUpdate = true;
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        DeviceModeService.isTv) {
      return;
    }

    _isCheckingForUpdate = true;
    try {
      await PlayStoreUpdateService.tryImmediatePlayCoreUpdate();
    } catch (_) {
      // Ignore update check failures. The app should continue normally.
    } finally {
      _isCheckingForUpdate = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'XapZap',
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRouteObserver],
            scrollBehavior: const MaterialScrollBehavior().copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
                PointerDeviceKind.stylus,
              },
            ),
            builder: (context, child) {
              final theme = Theme.of(context);
              final overlayStyle = theme.brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light.copyWith(
                      statusBarColor: Colors.transparent,
                      systemNavigationBarColor: theme.scaffoldBackgroundColor,
                      systemNavigationBarDividerColor:
                          theme.scaffoldBackgroundColor,
                    )
                  : SystemUiOverlayStyle.dark.copyWith(
                      statusBarColor: Colors.transparent,
                      systemNavigationBarColor: theme.scaffoldBackgroundColor,
                      systemNavigationBarDividerColor:
                          theme.scaffoldBackgroundColor,
                    );
              // On web/desktop, let the app use full width with no global centering.
              if (kIsWeb) {
                return AnnotatedRegion<SystemUiOverlayStyle>(
                  value: overlayStyle,
                  child: _NetworkStatusOverlay(
                    child: child ?? const SizedBox.shrink(),
                  ),
                );
              }
              // On mobile, keep safe areas and optional max-width centering.
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: overlayStyle,
                child: _NetworkStatusOverlay(
                  child: Container(
                    color: theme.scaffoldBackgroundColor,
                    child: SafeArea(
                      top: true,
                      bottom: true,
                      left: false,
                      right: false,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: child ?? const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const _LaunchRouter(),
            routes: {
              '/main': (context) => (kIsWeb || DeviceModeService.isTv)
                  ? const MainScreen()
                  : const AuthWrapper(),
              '/signin': (context) => const SignInScreen(),
              '/signup': (context) => const SignUpScreen(),
              '/privacy': (context) => const PrivacyPolicyScreen(),
              '/terms': (context) => const TermsOfServiceScreen(),
              '/safety-standards': (context) => const SafetyStandardsScreen(),
              '/account-deletion': (context) => const AccountDeletionScreen(),
              '/referrals': (context) => const ReferralsScreen(),
              '/saved-posts': (context) => const SavedPostsScreen(),
              '/drafts': (context) => const DraftsScreen(),
              '/premium': (context) => const PremiumScreen(),
              '/help-support': (context) => const HelpSupportScreen(),
              '/about': (context) => const AboutXapZapScreen(),
              '/new_chat': (context) => const NewChatScreen(),
              '/admin': (context) => const AdminDashboardScreen(),
              '/boosts': (context) => const BoostCenterScreen(),
            },
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

class _NetworkStatusOverlay extends StatelessWidget {
  final Widget child;

  const _NetworkStatusOverlay({required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NetworkBannerState>(
      valueListenable: NetworkStatusService.bannerState,
      builder: (context, bannerState, _) {
        final isVisible = bannerState != NetworkBannerState.hidden;
        final isOffline = bannerState == NetworkBannerState.offline;
        final bannerColor =
            isOffline ? const Color(0xFFB3261E) : const Color(0xFF10B981);
        final bannerText = isOffline ? 'No network' : 'Back online';
        return Stack(
          children: [
            child,
            if (isVisible)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    color: bannerColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: SafeArea(
                      bottom: false,
                      left: false,
                      right: false,
                      child: Text(
                        bannerText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LaunchRouter extends StatefulWidget {
  const _LaunchRouter();

  @override
  State<_LaunchRouter> createState() => _LaunchRouterState();
}

class _LaunchRouterState extends State<_LaunchRouter> {
  Uri? _initialUri;

  @override
  void initState() {
    super.initState();
    final rawRoute =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    _initialUri = _parseInitialUri(rawRoute);
  }

  @override
  Widget build(BuildContext context) {
    final uri = _initialUri;
    if (_isResetPasswordLink(uri)) {
      return ResetPasswordScreen(initialUri: uri!);
    }
    return const DecisionScreen();
  }

  Uri? _parseInitialUri(String value) {
    final raw = value.trim();
    if (raw.isEmpty || raw == '/') {
      return null;
    }
    try {
      return Uri.parse(raw);
    } catch (_) {
      return null;
    }
  }

  bool _isResetPasswordLink(Uri? uri) {
    if (uri == null) return false;
    return (uri.scheme == 'xapzap' && uri.host == 'reset-password') ||
        uri.path == '/reset-password' ||
        (uri.pathSegments.isNotEmpty &&
            uri.pathSegments.first == 'reset-password');
  }
}

class DecisionScreen extends StatelessWidget {
  const DecisionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // On web and TV, let users browse as guests without forcing auth.
    if (kIsWeb || DeviceModeService.isTv) {
      return const MainScreen();
    }
    return const AuthWrapper();
  }
}

