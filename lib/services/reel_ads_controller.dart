import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_frequency_service.dart';
import 'ad_helper.dart';
import 'ad_revenue_service.dart';
import 'rewarded_ad_preload_service.dart';

class ReelAdsController extends ChangeNotifier {
  final String postId;
  final String Function() creatorIdProvider;
  final Future<void> Function() startPlayback;
  final Future<void> Function() pausePlayback;
  final bool adsEnabled;

  ReelAdsController({
    required this.postId,
    required this.creatorIdProvider,
    required this.startPlayback,
    required this.pausePlayback,
    required this.adsEnabled,
  });

  bool _rewardedLoading = false;
  bool _showRewardedOverlay = false;

  bool get rewardedReady =>
      RewardedAdPreloadService.isLoadedForUnit(AdHelper.rewardedReelsUnit);
  bool get rewardedLoading => _rewardedLoading;
  bool get showRewardedOverlay => _showRewardedOverlay;

  void loadRewarded() {
    if (!adsEnabled ||
        _rewardedLoading ||
        RewardedAdPreloadService.isLoadedForUnit(AdHelper.rewardedReelsUnit)) {
      return;
    }
    _rewardedLoading = true;
    notifyListeners();
    unawaited(
      RewardedAdPreloadService.ensureUnit(AdHelper.rewardedReelsUnit).whenComplete(
        () {
          _rewardedLoading = false;
          notifyListeners();
        },
      ),
    );
  }

  Future<void> showRewarded({bool resumePlayback = true}) async {
    if (!adsEnabled) {
      if (resumePlayback) {
        await startPlayback();
      }
      return;
    }
    final ad = RewardedAdPreloadService.takeForUnit(AdHelper.rewardedReelsUnit);
    if (ad == null) {
      loadRewarded();
      if (resumePlayback) {
        await startPlayback();
      }
      return;
    }

    _showRewardedOverlay = true;
    await pausePlayback();
    notifyListeners();

    final completer = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {
        final creatorId = creatorIdProvider();
        if (creatorId.isEmpty) return;
        unawaited(
          AdRevenueService.recordCreatorImpression(
            adUnitId: AdHelper.rewardedReelsUnit,
            creatorId: creatorId,
            format: 'rewarded',
            placement: 'rewarded_reels',
            postId: postId,
          ),
        );
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _showRewardedOverlay = false;
        notifyListeners();
        if (resumePlayback) {
          unawaited(startPlayback());
        }
        completer.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _showRewardedOverlay = false;
        notifyListeners();
        if (resumePlayback) {
          unawaited(startPlayback());
        }
        completer.complete();
      },
    );
    ad.show(onUserEarnedReward: (_, __) {});
    await completer.future;
    await AdFrequencyService.markRewarded(postId);
  }

  @override
  void dispose() {
    RewardedAdPreloadService.clear();
    super.dispose();
  }
}
