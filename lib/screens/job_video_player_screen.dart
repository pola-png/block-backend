import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../models/post.dart';
import '../services/ad_helper.dart';
import '../services/micro_job_service.dart';

class JobVideoPlayerScreen extends StatefulWidget {
  final Post post;
  final double rewardAmount;

  const JobVideoPlayerScreen({
    super.key,
    required this.post,
    required this.rewardAmount,
  });

  @override
  State<JobVideoPlayerScreen> createState() => _JobVideoPlayerScreenState();
}

class _JobVideoPlayerScreenState extends State<JobVideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlayingAd = false;
  bool _adLoaded = false;
  int _secondsRemaining = 0;
  Timer? _countdownTimer;
  bool _videoFinished = false;
  bool _rewarded = false;

  RewardedAd? _startAd;
  RewardedAd? _endAd;
  bool _startAdCompleted = false;
  bool _endAdCompleted = false;

  @override
  void initState() {
    super.initState();
    _startFlow();
  }

  Future<void> _startFlow() async {
    // 1. Play Start Ad
    setState(() => _isPlayingAd = true);
    await _loadAndShowStartAd();
    
    // 2. Initialize Video Player
    setState(() => _isPlayingAd = false);
    _initializeVideo();
  }

  Future<void> _loadAndShowStartAd() async {
    final completer = Completer<void>();
    
    // Attempt to load and show Rewarded Ad for pre-roll
    RewardedAd.load(
      adUnitId: AdHelper.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _startAd = ad;
          _startAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              if (!completer.isCompleted) completer.complete();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              if (!completer.isCompleted) completer.complete();
            },
          );
          _startAd!.show(onUserEarnedReward: (ad, reward) {
            _startAdCompleted = true;
          });
        },
        onAdFailedToLoad: (error) {
          // Fallback if ad failed to load so user isn't stuck/punished for no fill
          _startAdCompleted = true;
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );

    // Add a 45 second timeout to allow user to fully watch the ad
    await completer.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        if (!completer.isCompleted) completer.complete();
      },
    );
  }

  void _initializeVideo() {
    final videoUrl = widget.post.preferredVideoUrl ?? widget.post.videoUrl;
    if (videoUrl == null || videoUrl.isEmpty) {
      // Fallback mock countdown if video url is empty
      setState(() {
        _isInitialized = true;
        _secondsRemaining = 15;
      });
      _startTimer();
      return;
    }
    
    _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _isInitialized = true;
          _secondsRemaining = _controller!.value.duration.inSeconds;
        });
        _controller!.play();
        _startTimer();
      }).catchError((error) {
        debugPrint('Video Player error: $error');
        // Fallback mock countdown if video fails to play
        setState(() {
          _isInitialized = true;
          _secondsRemaining = 15;
        });
        _startTimer();
      });
  }

  void _startTimer() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        _countdownTimer?.cancel();
        _onVideoFinished();
      }
    });
  }

  Future<void> _onVideoFinished() async {
    setState(() {
      _videoFinished = true;
      _isPlayingAd = true;
    });

    // 3. Play End Ad (Rewarded Ad to maximize revenue)
    await _loadAndShowEndAd();

    if (!mounted) return;

    // 4. Claim Reward only if both ads completed playing
    if (_startAdCompleted && _endAdCompleted) {
      final success = await MicroJobService.rewardUser(
        'video_watch_${widget.post.id}',
        widget.rewardAmount,
      );

      setState(() {
        _isPlayingAd = false;
        _rewarded = success;
      });

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully rewarded \$${widget.rewardAmount.toStringAsFixed(2)}!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      setState(() {
        _isPlayingAd = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must watch both ads fully to get the reward.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadAndShowEndAd() async {
    final completer = Completer<void>();

    RewardedAd.load(
      adUnitId: AdHelper.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _endAd = ad;
          _endAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              if (!completer.isCompleted) completer.complete();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              if (!completer.isCompleted) completer.complete();
            },
          );
          _endAd!.show(onUserEarnedReward: (ad, reward) {
            _endAdCompleted = true;
          });
        },
        onAdFailedToLoad: (error) {
          // Fallback if ad failed to load so user isn't stuck/punished for no fill
          _endAdCompleted = true;
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );

    // Add a 45 second timeout to allow user to fully watch the ad
    await completer.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        if (!completer.isCompleted) completer.complete();
      },
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _controller?.dispose();
    _startAd?.dispose();
    _endAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _isPlayingAd ? 'Ad Playing...' : 'Watch & Earn',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _isPlayingAd
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.pinkAccent),
                          SizedBox(height: 16),
                          Text(
                            'Loading sponsored ad...',
                            style: TextStyle(color: Colors.white70, fontSize: 16),
                          ),
                        ],
                      )
                    : (_isInitialized
                        ? AspectRatio(
                            aspectRatio: _controller?.value.aspectRatio ?? 16 / 9,
                            child: Stack(
                              alignment: Alignment.bottomCenter,
                              children: [
                                if (_controller != null) VideoPlayer(_controller!),
                                // Shield overlay to block touch/clicks and prevent seeking
                                Positioned.fill(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      // Toggle play/pause but no scrubbing
                                      if (_controller != null) {
                                        if (_controller!.value.isPlaying) {
                                          _controller!.pause();
                                          _countdownTimer?.cancel();
                                        } else {
                                          _controller!.play();
                                          _startTimer();
                                        }
                                      }
                                    },
                                  ),
                                ),
                                // Countdown/Play Indicator
                                Positioned(
                                  top: 16,
                                  right: 16,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.timer, color: Colors.pinkAccent, size: 16),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${_secondsRemaining}s remaining',
                                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const CircularProgressIndicator(color: Colors.pinkAccent)),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.post.content.isNotEmpty ? widget.post.content : 'Sponsored Task Video',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Reward:',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      Text(
                        '\$${widget.rewardAmount.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_videoFinished)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Job Completed'),
                      onPressed: () => Navigator.pop(context),
                    )
                  else
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: null,
                      child: Text('Complete Video to Earn Reward'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
