import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_helper.dart';
import '../services/ad_revenue_service.dart';
import 'rewarded_ad_preload_service.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class XapZapAdGateService {
  static final XapZapAdGateService instance = XapZapAdGateService._();

  XapZapAdGateService._();

  AppOpenAd? _appOpenAd;
  InterstitialAd? _interstitialAd;
  RewardedInterstitialAd? _rewardedInterstitialAd;

  bool _isAppOpenAdLoading = false;
  bool _isInterstitialAdLoading = false;
  bool _isRewardedInterstitialAdLoading = false;

  Completer<void>? _appOpenCompleter;
  Completer<void>? _interstitialCompleter;
  Completer<void>? _rewardedInterstitialCompleter;

  Future<bool> isAdFreeActive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expiry = prefs.getInt('ad_free_expiry_timestamp') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (expiry > now) {
        return true;
      }

      // Authoritative verification against Supabase user profile
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final profileRes = await Supabase.instance.client
            .from('profiles')
            .select('ad_free_expiry')
            .eq('id', user.id)
            .maybeSingle();

        if (profileRes != null && profileRes['ad_free_expiry'] != null) {
          final dbExpiryStr = profileRes['ad_free_expiry'] as String;
          final dbExpiryDt = DateTime.tryParse(dbExpiryStr);
          if (dbExpiryDt != null && dbExpiryDt.millisecondsSinceEpoch > now) {
            final dbExpiryTs = dbExpiryDt.millisecondsSinceEpoch;
            await prefs.setInt('ad_free_expiry_timestamp', dbExpiryTs);
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('[AdGate] Error checking real ad-free status: $e');
    }
    return false;
  }

  // Initialize and trigger initial load
  Future<void> init() async {
    if (kIsWeb) return;
    
    // Start preloading all
    preloadAppOpenAd();
    preloadInterstitialAd();
    preloadRewardedInterstitialAd();
  }

  void preloadAll() {
    preloadAppOpenAd();
    preloadInterstitialAd();
    preloadRewardedInterstitialAd();
  }

  bool _pendingShowOnLoad = false;

  void _showLoadedAppOpenAd(AppOpenAd ad, {String placement = 'app_launch_cold_start'}) {
    _pendingShowOnLoad = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        markPopUpAdShown();
        a.dispose();
        _appOpenAd = null;
        preloadAppOpenAd(); // preload next one immediately
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        a.dispose();
        _appOpenAd = null;
        preloadAppOpenAd();
      },
    );

    ad.onPaidEvent = AdRevenueService.paidEventHandler(
      adUnitId: AdHelper.appOpen,
      format: 'appopen',
      placement: placement,
    );

    markPopUpAdShown();
    debugPrint('[AdGate] Displaying App Open Ad now (placement: $placement, unit: ${AdHelper.appOpen})...');
    ad.show();
  }

  // PRELOAD APP OPEN AD
  Future<void> preloadAppOpenAd() {
    if (kIsWeb) return Future.value();
    if (_appOpenAd != null) return Future.value();
    if (_isAppOpenAdLoading) {
      return _appOpenCompleter?.future ?? Future.value();
    }

    _isAppOpenAdLoading = true;
    _appOpenCompleter = Completer<void>();

    AppOpenAd.load(
      adUnitId: AdHelper.appOpen,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAd = ad;
          _isAppOpenAdLoading = false;
          debugPrint('[AdGate] App Open Ad loaded successfully for unit: ${AdHelper.appOpen}');
          if (_appOpenCompleter != null && !_appOpenCompleter!.isCompleted) {
            _appOpenCompleter!.complete();
          }
          if (_pendingShowOnLoad && !isPopUpAdOnCooldown()) {
            _showLoadedAppOpenAd(ad);
          }
        },
        onAdFailedToLoad: (error) {
          _isAppOpenAdLoading = false;
          _appOpenAd = null;
          _pendingShowOnLoad = false;
          debugPrint('[AdGate] App Open Ad failed to load (code: ${error.code}, message: "${error.message}", domain: ${error.domain}) for unit: ${AdHelper.appOpen}');
          if (_appOpenCompleter != null && !_appOpenCompleter!.isCompleted) {
            _appOpenCompleter!.complete();
          }
        },
      ),
    );

    return _appOpenCompleter!.future;
  }

  // PRELOAD INTERSTITIAL AD
  Future<void> preloadInterstitialAd() {
    if (kIsWeb) return Future.value();
    if (_interstitialAd != null) return Future.value();
    if (_isInterstitialAdLoading) {
      return _interstitialCompleter?.future ?? Future.value();
    }

    _isInterstitialAdLoading = true;
    _interstitialCompleter = Completer<void>();

    InterstitialAd.load(
      adUnitId: AdHelper.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdLoading = false;
          debugPrint('[AdGate] Interstitial Ad loaded successfully.');
          if (_interstitialCompleter != null && !_interstitialCompleter!.isCompleted) {
            _interstitialCompleter!.complete();
          }
        },
        onAdFailedToLoad: (error) {
          _isInterstitialAdLoading = false;
          _interstitialAd = null;
          debugPrint('[AdGate] Interstitial Ad failed to load: $error');
          if (_interstitialCompleter != null && !_interstitialCompleter!.isCompleted) {
            _interstitialCompleter!.complete();
          }
        },
      ),
    );

    return _interstitialCompleter!.future;
  }

  // PRELOAD REWARDED INTERSTITIAL AD
  Future<void> preloadRewardedInterstitialAd() {
    if (kIsWeb) return Future.value();
    if (_rewardedInterstitialAd != null) return Future.value();
    if (_isRewardedInterstitialAdLoading) {
      return _rewardedInterstitialCompleter?.future ?? Future.value();
    }

    _isRewardedInterstitialAdLoading = true;
    _rewardedInterstitialCompleter = Completer<void>();

    RewardedInterstitialAd.load(
      adUnitId: AdHelper.rewardedReelsUnit,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedInterstitialAd = ad;
          _isRewardedInterstitialAdLoading = false;
          debugPrint('[AdGate] Rewarded Interstitial Ad loaded successfully.');
          if (_rewardedInterstitialCompleter != null && !_rewardedInterstitialCompleter!.isCompleted) {
            _rewardedInterstitialCompleter!.complete();
          }
        },
        onAdFailedToLoad: (error) {
          _isRewardedInterstitialAdLoading = false;
          _rewardedInterstitialAd = null;
          debugPrint('[AdGate] Rewarded Interstitial Ad failed to load: $error');
          if (_rewardedInterstitialCompleter != null && !_rewardedInterstitialCompleter!.isCompleted) {
            _rewardedInterstitialCompleter!.complete();
          }
        },
      ),
    );

    return _rewardedInterstitialCompleter!.future;
  }

  DateTime? _lastPopUpAdShownTime;

  // Checks if a pop-up ad (App Open / Interstitial) was shown in the last 5 minutes
  bool isPopUpAdOnCooldown() {
    if (_lastPopUpAdShownTime == null) return false;
    final elapsed = DateTime.now().difference(_lastPopUpAdShownTime!);
    return elapsed < const Duration(minutes: 5);
  }

  void markPopUpAdShown() {
    _lastPopUpAdShownTime = DateTime.now();
  }

  // SHOW APP OPEN AD — rate-limited to 5 minutes between pop-ups
  Future<void> showAppOpenAdIfAvailable({bool isForegroundResume = false}) async {
    if (kIsWeb) return;

    if (await isAdFreeActive()) {
      debugPrint('[AdGate] App Open Ad suppressed: User has active Ad-Free plan.');
      return;
    }

    if (isPopUpAdOnCooldown()) {
      debugPrint('[AdGate] App Open Ad suppressed: 5-minute popup cooldown active.');
      return;
    }

    final placement = isForegroundResume ? 'app_foreground_resume' : 'app_launch_cold_start';

    // 1. If ad is already in memory, display immediately
    if (_appOpenAd != null) {
      debugPrint('[AdGate] App Open Ad is cached. Presenting immediately...');
      _showLoadedAppOpenAd(_appOpenAd!, placement: placement);
      return;
    }

    // 2. Set pending auto-show flag and trigger load
    _pendingShowOnLoad = true;
    debugPrint('[AdGate] App Open Ad not cached. Awaiting network fetch from AdMob...');
    try {
      await preloadAppOpenAd().timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('[AdGate] App Open Ad fetch ongoing in background: $e');
    }
  }

  // SHOW INTERSTITIAL AD (WITH REWARDED INTERSTITIAL FALLBACK) — rate-limited to 5 minutes
  Future<bool> showInterstitialAd({String placement = 'general'}) async {
    if (kIsWeb) return false;

    if (await isAdFreeActive()) {
      debugPrint('[AdGate] Interstitial Ad suppressed ($placement): User has active Ad-Free plan.');
      return false;
    }

    if (isPopUpAdOnCooldown()) {
      debugPrint('[AdGate] Interstitial Ad suppressed ($placement): 5-minute popup cooldown active.');
      return false;
    }

    // If it's not loaded yet but loading, wait up to 2 seconds for it
    if (_interstitialAd == null && _isInterstitialAdLoading) {
      debugPrint('[AdGate] Interstitial is loading. Waiting for it...');
      try {
        await _interstitialCompleter?.future.timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint('[AdGate] Interstitial wait timed out: $e');
      }
    }

    // Check if Interstitial ad is ready
    if (_interstitialAd != null) {
      final ad = _interstitialAd!;
      _interstitialAd = null; // consume
      
      final completer = Completer<bool>();
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (dismissedAd) {
          markPopUpAdShown();
          dismissedAd.dispose();
          preloadInterstitialAd();
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToShowFullScreenContent: (failedAd, error) {
          failedAd.dispose();
          preloadInterstitialAd();
          if (!completer.isCompleted) completer.complete(false);
        },
      );

      ad.onPaidEvent = AdRevenueService.paidEventHandler(
        adUnitId: AdHelper.interstitial,
        format: 'interstitial',
        placement: placement,
      );

      markPopUpAdShown();
      ad.show();
      return completer.future;
    }

    // Try fallback to Rewarded Interstitial
    debugPrint('[AdGate] Interstitial unavailable. Attempting Rewarded Interstitial fallback...');
    
    if (_rewardedInterstitialAd == null && _isRewardedInterstitialAdLoading) {
      debugPrint('[AdGate] Rewarded Interstitial is loading. Waiting for it...');
      try {
        await _rewardedInterstitialCompleter?.future.timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint('[AdGate] Rewarded Interstitial wait timed out: $e');
      }
    }

    if (_rewardedInterstitialAd != null) {
      final ad = _rewardedInterstitialAd!;
      _rewardedInterstitialAd = null; // consume

      final completer = Completer<bool>();
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (dismissedAd) {
          markPopUpAdShown();
          dismissedAd.dispose();
          preloadRewardedInterstitialAd();
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToShowFullScreenContent: (failedAd, error) {
          failedAd.dispose();
          preloadRewardedInterstitialAd();
          if (!completer.isCompleted) completer.complete(false);
        },
      );

      ad.onPaidEvent = AdRevenueService.paidEventHandler(
        adUnitId: AdHelper.rewardedReelsUnit,
        format: 'rewarded_interstitial',
        placement: '${placement}_fallback',
      );

      markPopUpAdShown();
      ad.show(onUserEarnedReward: (ad, reward) {
        debugPrint('[AdGate] User earned fallback reward: ${reward.amount}');
      });
      return completer.future;
    }

    // Trigger preload retry
    preloadInterstitialAd();
    preloadRewardedInterstitialAd();
    return false;
  }

  // SHOW REWARDED AD FOR TASK LIST BUTTONS
  Future<bool> showRewardedAd({String placement = 'task_button'}) async {
    if (kIsWeb) return true;

    final completer = Completer<bool>();

    // 1. Try preloaded ad first
    final unitId = AdHelper.rewarded;
    final preloadedAd = RewardedAdPreloadService.takeForUnit(unitId) ??
        RewardedAdPreloadService.takeForUnit(AdHelper.rewardedReelsUnit);
    if (preloadedAd != null) {
      bool earned = false;
      preloadedAd.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          RewardedAdPreloadService.warmup();
          if (!completer.isCompleted) completer.complete(earned);
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          RewardedAdPreloadService.warmup();
          if (!completer.isCompleted) completer.complete(false);
        },
      );
      preloadedAd.show(onUserEarnedReward: (ad, reward) {
        earned = true;
      });
      return completer.future;
    }

    // 2. Load on-demand rewarded ad
    RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          bool earned = false;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              RewardedAdPreloadService.warmup();
              if (!completer.isCompleted) completer.complete(earned);
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              RewardedAdPreloadService.warmup();
              if (!completer.isCompleted) completer.complete(false);
            },
          );
          ad.show(onUserEarnedReward: (ad, reward) {
            earned = true;
          });
        },
        onAdFailedToLoad: (error) {
          debugPrint('[AdGate] Rewarded Ad failed to load ($placement): $error');
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );

    return completer.future;
  }
}

