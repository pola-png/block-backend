import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_helper.dart';
import '../services/ad_revenue_service.dart';

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

  // Initialize and trigger initial load
  Future<void> init() async {
    if (kIsWeb) return;
    
    // Start preloading all
    final appOpenFuture = preloadAppOpenAd();
    preloadInterstitialAd();
    preloadRewardedInterstitialAd();

    // Await the app open ad with a short timeout during initialization
    try {
      await appOpenFuture.timeout(const Duration(milliseconds: 2500));
    } catch (e) {
      debugPrint('[AdGate] Initial App Open Ad load timed out: $e');
    }
  }

  void preloadAll() {
    preloadAppOpenAd();
    preloadInterstitialAd();
    preloadRewardedInterstitialAd();
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
          debugPrint('[AdGate] App Open Ad loaded successfully.');
          if (_appOpenCompleter != null && !_appOpenCompleter!.isCompleted) {
            _appOpenCompleter!.complete();
          }
        },
        onAdFailedToLoad: (error) {
          _isAppOpenAdLoading = false;
          _appOpenAd = null;
          debugPrint('[AdGate] App Open Ad failed to load: $error');
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

  // SHOW APP OPEN AD — shows every time the app is launched or resumed
  void showAppOpenAdIfAvailable() {
    if (kIsWeb) return;

    if (_appOpenAd == null) {
      debugPrint('[AdGate] App Open Ad not loaded yet. Attempting to fetch.');
      preloadAppOpenAd();
      return;
    }

    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _appOpenAd = null;
        preloadAppOpenAd(); // preload next one immediately
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _appOpenAd = null;
        preloadAppOpenAd();
      },
    );

    _appOpenAd!.onPaidEvent = AdRevenueService.paidEventHandler(
      adUnitId: AdHelper.appOpen,
      format: 'appopen',
      placement: 'app_launch_resume',
    );

    _appOpenAd!.show();
  }

  // SHOW INTERSTITIAL AD (WITH REWARDED INTERSTITIAL FALLBACK)
  Future<bool> showInterstitialAd({String placement = 'general'}) async {
    if (kIsWeb) return false;

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
}
