import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ad_helper.dart';
import '../services/ad_revenue_service.dart';

class RewardedAdPreloadService {
  static RewardedAd? _ad;
  static String? _loadedUnitId;
  static String? _loadingUnitId;
  static final Set<String> _failed = <String>{};
  static final Map<String, Timer> _retryTimers = <String, Timer>{};
  static final ValueNotifier<int> _version = ValueNotifier<int>(0);

  static ValueListenable<int> get changes => _version;

  static void _notify() {
    _version.value += 1;
  }

  static Future<void> warmup() async {
    if (kIsWeb) return;
    await ensureUnit(AdHelper.rewardedReelsUnit);
  }

  static Future<void> ensureUnit(String unitId) async {
    if (kIsWeb) return;
    if (_loadedUnitId == unitId && _ad != null) return;
    if (_loadingUnitId == unitId) return;
    if (_loadingUnitId != null) return;
    clear();
    _retryTimers.remove(unitId)?.cancel();
    _failed.remove(unitId);
    _loadingUnitId = unitId;

    final completer = Completer<void>();
    RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (loadedAd) {
          clear();
          loadedAd.onPaidEvent = AdRevenueService.paidEventHandler(
            adUnitId: unitId,
            format: 'rewarded',
            placement: 'startup_preload',
          );
          _ad = loadedAd;
          _loadedUnitId = unitId;
          _loadingUnitId = null;
          _notify();
          if (!completer.isCompleted) completer.complete();
        },
        onAdFailedToLoad: (error) {
          _loadingUnitId = null;
          _failed.add(unitId);
          _notify();
          final retryDelay = error.code == 0
              ? const Duration(seconds: 20)
              : const Duration(seconds: 45);
          _retryTimers[unitId]?.cancel();
          _retryTimers[unitId] = Timer(retryDelay, () {
            _retryTimers.remove(unitId);
            unawaited(ensureUnit(unitId));
          });
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );
    await completer.future;
  }

  static RewardedAd? takeForUnit(String unitId) {
    if (_loadedUnitId != unitId || _ad == null) {
      return null;
    }
    final ad = _ad;
    _ad = null;
    _loadedUnitId = null;
    _notify();
    return ad;
  }

  static RewardedAd? takeForKey(String key) {
    return takeForUnit(AdHelper.rewardedForKey(key));
  }

  static bool isLoadedForUnit(String unitId) =>
      _loadedUnitId == unitId && _ad != null;

  static bool isLoadingForUnit(String unitId) => _loadingUnitId == unitId;

  static bool isFailedForUnit(String unitId) => _failed.contains(unitId);

  static void clear() {
    _ad?.dispose();
    _ad = null;
    _loadedUnitId = null;
    _loadingUnitId = null;
    _notify();
  }

  static void disposeAll() {
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    clear();
    _failed.clear();
    _notify();
  }
}
