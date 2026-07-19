import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ad_helper.dart';
import '../services/ad_revenue_service.dart';

class NativeAdPreloadService {
  static const int _maxLoadedAds = 2;
  static final Map<int, NativeAd> _ads = <int, NativeAd>{};
  static final Set<int> _loading = <int>{};
  static final Set<int> _loaded = <int>{};
  static final Set<int> _shown = <int>{};
  static final Set<int> _failed = <int>{};
  static final Map<int, Timer> _retryTimers = <int, Timer>{};
  static final ValueNotifier<int> _version = ValueNotifier<int>(0);
  static bool _fastWarmupRunning = false;

  static ValueListenable<int> get changes => _version;

  static void _notify() {
    _version.value += 1;
  }

  static Future<void> warmup({int maxSlotIndex = 2}) async {
    if (kIsWeb) return;
    for (var slotIndex = 0; slotIndex <= maxSlotIndex; slotIndex++) {
      await ensureSlot(slotIndex);
    }
  }

  static Future<void> warmupFast({int maxSlotIndex = 2}) async {
    if (kIsWeb || _fastWarmupRunning) return;
    _fastWarmupRunning = true;
    try {
      final cappedMaxSlot = maxSlotIndex.clamp(0, _maxLoadedAds - 1);
      for (var slotIndex = 0; slotIndex <= cappedMaxSlot; slotIndex++) {
        await ensureSlot(slotIndex);
      }
    } finally {
      _fastWarmupRunning = false;
    }
  }

  static Future<void> refresh({int maxSlotIndex = 2}) async {
    if (kIsWeb) return;
    for (var slotIndex = 0; slotIndex <= maxSlotIndex; slotIndex++) {
      _retryTimers[slotIndex]?.cancel();
      _retryTimers.remove(slotIndex);
      _failed.remove(slotIndex);
      _shown.remove(slotIndex);
      if (_loaded.contains(slotIndex) || _loading.contains(slotIndex)) {
        continue;
      }
      await ensureSlot(slotIndex);
    }
  }

  static Future<void> ensureSlot(int slotIndex) async {
    if (kIsWeb) return;
    if (_shown.contains(slotIndex) ||
        _loaded.contains(slotIndex) ||
        _loading.contains(slotIndex) ||
        _loaded.length >= _maxLoadedAds) {
      return;
    }
    _retryTimers.remove(slotIndex)?.cancel();
    _failed.remove(slotIndex);
    _loading.add(slotIndex);

    final completer = Completer<void>();
    late final NativeAd ad;
    ad = NativeAd(
      adUnitId: AdHelper.nativeForFeedSlot(slotIndex),
      factoryId: 'cardNative',
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (loadedAd) {
          _trimLoadedAds(exceptSlot: slotIndex);
          _loaded.add(slotIndex);
          _loading.remove(slotIndex);
          _notify();
          if (!completer.isCompleted) completer.complete();
        },
        onPaidEvent: AdRevenueService.paidEventHandler(
          adUnitId: AdHelper.nativeForFeedSlot(slotIndex),
          format: 'native',
          placement: 'home_feed',
        ),
        onAdFailedToLoad: (loadedAd, error) {
          loadedAd.dispose();
          _ads.remove(slotIndex);
          _loaded.remove(slotIndex);
          _loading.remove(slotIndex);
          _failed.add(slotIndex);
          _notify();
          final retryDelay = error.code == 0
              ? const Duration(seconds: 20)
              : const Duration(seconds: 45);
          _retryTimers[slotIndex]?.cancel();
          _retryTimers[slotIndex] = Timer(retryDelay, () {
            _retryTimers.remove(slotIndex);
            unawaited(ensureSlot(slotIndex));
          });
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );
    _ads[slotIndex] = ad;
    ad.load();
    await completer.future;
  }

  static NativeAd? adForSlot(int slotIndex) => _ads[slotIndex];

  static NativeAd? takeAnyLoadedAd() {
    final loadedSlot = _loaded.isEmpty ? null : _loaded.first;
    if (loadedSlot == null) return null;
    return takeForSlot(loadedSlot);
  }

  static NativeAd? takeForSlot(int slotIndex) {
    if (!_loaded.contains(slotIndex)) {
      return null;
    }
    final ad = _ads.remove(slotIndex);
    if (ad == null) return null;
    _loaded.remove(slotIndex);
    _shown.add(slotIndex);
    _notify();
    return ad;
  }

  static void _trimLoadedAds({int? exceptSlot}) {
    while (_loaded.length >= _maxLoadedAds) {
      final removable = _loaded.cast<int?>().firstWhere(
            (slot) => slot != exceptSlot,
            orElse: () => null,
          );
      if (removable == null) {
        return;
      }
      _loaded.remove(removable);
      _ads.remove(removable)?.dispose();
      _failed.remove(removable);
      _retryTimers.remove(removable)?.cancel();
    }
  }

  static bool isLoaded(int slotIndex) => _loaded.contains(slotIndex);

  static bool isLoading(int slotIndex) => _loading.contains(slotIndex);

  static bool isShown(int slotIndex) => _shown.contains(slotIndex);

  static bool isFailed(int slotIndex) => _failed.contains(slotIndex);

  static bool hasLoadedAds() => _loaded.isNotEmpty;

  static bool hasAnyLoadingAds() => _loading.isNotEmpty;

  static bool hasAnyFailedAds() => _failed.isNotEmpty;

  static void releaseAll() {
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    for (final ad in _ads.values) {
      ad.dispose();
    }
    _ads.clear();
    _loading.clear();
    _loaded.clear();
    _shown.clear();
    _failed.clear();
    _notify();
  }

  static void disposeAll() {
    releaseAll();
  }
}
