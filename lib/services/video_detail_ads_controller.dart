import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ad_helper.dart';
import 'rewarded_ad_preload_service.dart';

class VideoDetailAdsController extends ChangeNotifier {
  final String postId;
  final bool adsEnabled;
  final String Function() creatorIdProvider;
  final Future<void> Function() startPlayback;
  final Future<void> Function() pausePlayback;

  VideoDetailAdsController({
    required this.postId,
    required this.adsEnabled,
    required this.creatorIdProvider,
    required this.startPlayback,
    required this.pausePlayback,
  });

  final bool _rewardedLoading = false;
  final bool _showRewardedOverlay = false;
  final bool _blockBackNavigation = false;

  bool get rewardedReady =>
      RewardedAdPreloadService.isLoadedForUnit(AdHelper.rewardedForKey(postId));
  bool get rewardedLoading => _rewardedLoading;
  bool get showRewardedOverlay => _showRewardedOverlay;
  bool get blockBackNavigation => _blockBackNavigation;

  void loadRewarded() {
    // Rewarded ads are disabled on the video details screen.
  }

  Future<void> showRewarded({bool resumePlayback = true}) async {
    // Rewarded ads are disabled on the video details screen.
    if (resumePlayback) {
      await startPlayback();
    }
  }

  @override
  void dispose() {
    RewardedAdPreloadService.clear();
    super.dispose();
  }
}
