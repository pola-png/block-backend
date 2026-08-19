import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/micro_job_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_helper.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class VideoReviewScreen extends StatefulWidget {
  final Map<String, dynamic> campaign;
  final double rewardAmount;
  final int userLevel;

  const VideoReviewScreen({
    super.key,
    required this.campaign,
    required this.rewardAmount,
    required this.userLevel,
  });

  @override
  State<VideoReviewScreen> createState() => _VideoReviewScreenState();
}

class _VideoReviewScreenState extends State<VideoReviewScreen> {
  WebViewController? _webViewController;
  YoutubePlayerController? _youtubeController;
  bool _isVideoLoaded = false;
  bool _watchComplete = false;
  int _secondsRemaining = 15; // Default short test countdown, will calculate below
  Timer? _countdownTimer;

  // Review fields
  int _ratingStars = 5;
  int _ratingActors = 5;
  final _feedbackController = TextEditingController();
  bool _isSavingReview = false;

  bool _isPlayingAd = false;
  RewardedAd? _startAd;
  RewardedAd? _endAd;
  bool _startAdCompleted = false;
  bool _endAdCompleted = false;
  @override
  void initState() {
    super.initState();
    _calculateWatchTarget();
    _startFlow();
  }

  Future<void> _startFlow() async {
    setState(() => _isPlayingAd = true);
    await _loadAndShowStartAd();
    
    if (mounted) {
      setState(() => _isPlayingAd = false);
      _initializePlayer();
    }
  }

  void _calculateWatchTarget() {
    final int videoDurationMins = widget.campaign['duration_minutes'] as int? ?? 1;
    _secondsRemaining = videoDurationMins * 60;
  }

  void _initializePlayer() {
    final String originalUrl = widget.campaign['video_url'] ?? '';
    final videoId = YoutubePlayerController.convertUrlToId(originalUrl);

    if (videoId != null) {
      _youtubeController = YoutubePlayerController.fromVideoId(
        videoId: videoId,
        autoPlay: false,
        params: const YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: true,
          mute: false,
        ),
      );
      _youtubeController!.listen((value) {
        if (!mounted) return;
        if (value.playerState == PlayerState.playing && !_isVideoLoaded) {
          setState(() {
            _isVideoLoaded = true;
          });
          _startTimer();
        }
      });
    } else {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (String url) {
              if (!mounted) return;
              setState(() {
                _isVideoLoaded = true;
              });
              _startTimer();
            },
          ),
        );

      final htmlString = '''
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
          <style>
            body, html { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background-color: #000; }
            video { width: 100%; height: 100%; object-fit: contain; }
          </style>
        </head>
        <body>
          <video src="$originalUrl" controls playsinline style="width:100%; height:100%;"></video>
        </body>
        </html>
      ''';
      _webViewController!.loadHtmlString(htmlString);
    }
  }

  void _startTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      
      // Pause countdown if YouTube video is paused/buffering/etc.
      if (_youtubeController != null && _youtubeController!.value.playerState != PlayerState.playing) {
        return;
      }

      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        _countdownTimer?.cancel();
        setState(() {
          _watchComplete = true;
        });
      }
    });
  }

  Future<void> _submitReview() async {
    if (_feedbackController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write a brief feedback critique.'), backgroundColor: Colors.amber),
      );
      return;
    }

    setState(() {
      _isSavingReview = true;
    });

    // Show end-roll rewarded ad before payout completion
    await _loadAndShowEndAd();

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final campaignId = widget.campaign['id'] as String;

      // 1. Save review feedback in Supabase
      await Supabase.instance.client.from('user_completed_reviews').insert({
        'user_id': user.id,
        'campaign_id': campaignId,
        'rating_stars': _ratingStars,
        'feedback_quality': _ratingStars,
        'feedback_actors': _ratingActors,
        'general_feedback': _feedbackController.text.trim(),
        'earned_amount': widget.rewardAmount,
      });

      // 2. Increment reviews_completed count on campaign
      final currentCompleted = widget.campaign['reviews_completed'] as int? ?? 0;
      final target = widget.campaign['target_reviews'] as int? ?? 0;
      final newCompleted = currentCompleted + 1;

      await Supabase.instance.client
          .from('video_campaigns')
          .update({
            'reviews_completed': newCompleted,
            'status': newCompleted >= target ? 'completed' : widget.campaign['status'],
          })
          .eq('id', campaignId);

      // 3. Reward user using standard MicroJobService
      await MicroJobService.rewardUser('video_review_$campaignId', widget.rewardAmount);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Review Submitted! +\$${widget.rewardAmount.toStringAsFixed(2)} credited.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit review: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingReview = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _feedbackController.dispose();
    _startAd?.dispose();
    _endAd?.dispose();
    _youtubeController?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isPlayingAd) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'Ad Playing...',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.pinkAccent),
              SizedBox(height: 16),
              Text(
                'Please wait for the ad to complete...',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          _watchComplete ? 'Submit Video Review' : 'Watch Video Hook',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Video Webview Box
            Expanded(
              flex: 4,
              child: _youtubeController != null
                  ? YoutubePlayer(
                      controller: _youtubeController!,
                    )
                  : Stack(
                      children: [
                        if (_webViewController != null)
                          WebViewWidget(controller: _webViewController!),
                        if (!_isVideoLoaded)
                          const Center(
                            child: CircularProgressIndicator(color: Colors.pinkAccent),
                          ),
                      ],
                    ),
            ),

            // Info & Countdown Bar
            Container(
              color: Colors.grey.shade900,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.rate_review, color: Colors.pinkAccent),
                      SizedBox(width: 8),
                      Text('Review Mission', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (!_watchComplete)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.pinkAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.timer, color: Colors.pinkAccent, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Watch: ${(_secondsRemaining ~/ 60)}:${(_secondsRemaining % 60).toString().padLeft(2, '0')}',
                            style: const TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    )
                  else
                    const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                        SizedBox(width: 6),
                        Text('Watch Complete', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                ],
              ),
            ),

            // Review submission section
            Expanded(
              flex: 5,
              child: Container(
                color: const Color(0xFF0F0F0F),
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Submit Ad Review Critique',
                        style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      _buildStarRatingRow('Rate Video Quality & Structure', _ratingStars, (val) {
                        setState(() => _ratingStars = val);
                      }),
                      const SizedBox(height: 12),
                      _buildStarRatingRow('Rate Actor/Presenter Delivery', _ratingActors, (val) {
                        setState(() => _ratingActors = val);
                      }),
                      const SizedBox(height: 16),
                      const Text(
                        'Write constructive review feedback:',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _feedbackController,
                        maxLines: 3,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'What parts did well? How can the advertiser improve the hook?',
                          hintStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: Colors.grey.shade900,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _watchComplete ? theme.colorScheme.primary : Colors.grey.shade800,
                          foregroundColor: _watchComplete ? theme.colorScheme.onPrimary : Colors.white30,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: (_isSavingReview || !_watchComplete) ? null : _submitReview,
                        child: _isSavingReview
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(
                                _watchComplete ? 'Submit Review & Claim Payout' : 'Watch video to unlock payout',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadAndShowStartAd() async {
    final completer = Completer<void>();
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
          _startAdCompleted = true;
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );

    await completer.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        if (!completer.isCompleted) completer.complete();
      },
    );
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
          _endAdCompleted = true;
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );

    await completer.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        if (!completer.isCompleted) completer.complete();
      },
    );
  }



  Widget _buildStarRatingRow(String label, int currentRating, Function(int) onRatingChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 6),
        Row(
          children: List.generate(5, (index) {
            final starIndex = index + 1;
            return IconButton(
              icon: Icon(
                starIndex <= currentRating ? Icons.star_rate_rounded : Icons.star_border_rounded,
                color: Colors.amberAccent,
                size: 28,
              ),
              onPressed: () => onRatingChanged(starIndex),
            );
          }),
        ),
      ],
    );
  }
}
