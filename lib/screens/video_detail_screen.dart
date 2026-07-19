import 'dart:async';

import 'package:appwrite/appwrite.dart' show RealtimeSubscription;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_helper.dart';
import '../models/post.dart';
import '../screens/comment_screen.dart';
import '../widgets/taggable_text.dart';
import '../services/appwrite_service.dart';
import '../services/native_ad_preload_service.dart';
import '../services/post_view_retry_queue.dart';
import '../services/global_video_manager.dart';
import '../services/video_detail_ads_controller.dart';
import '../services/video_detail_playback_controller.dart';
import '../widgets/tv_focusable_action.dart';
import '../widgets/video_detail_comments_bar.dart';
import '../widgets/video_detail_meta_section.dart';
import '../widgets/watch_video_card.dart';
import '../widgets/series_episode_tray.dart';
import '../services/feed_cache.dart';
import '../main.dart';

class VideoDetailScreen extends StatefulWidget {
  final Post post;
  final List<String>? mediaUrls;
  final String? authorId;
  final bool isGuest;
  final VoidCallback? onGuestAction;
  final Duration? initialPosition;
  final bool autoPlay;

  const VideoDetailScreen({
    super.key,
    required this.post,
    this.mediaUrls,
    this.authorId,
    this.isGuest = false,
    this.onGuestAction,
    this.initialPosition,
    this.autoPlay = true,
  });

  @override
  State<VideoDetailScreen> createState() => _VideoDetailScreenState();
}

class _VideoDetailScreenState extends State<VideoDetailScreen>
    with WidgetsBindingObserver, RouteAware {
  bool _isFullscreen = false;
  Post? _livePost;
  RealtimeSubscription? _postSub;
  late final VideoDetailAdsController _adsController;
  VideoDetailPlaybackController? _playbackController;
  Map<String, dynamic>? _episodeMeta;
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmittingComment = false;
  bool _isCommentsModalOpen = false;
  NativeAd? _videoAd;
  NativeAd? _bottomAd;
  bool _isBottomAdLoaded = false;
  bool _adActiveInPlayer = false;
  int _adCountdown = 5;
  Timer? _adCountdownTimer;
  static const MethodChannel _adsChannel = MethodChannel('xapzap/ads');
  bool _lastIsPlaying = false;
  bool get _adsEnabled =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  String get _creatorId {
    final direct = widget.authorId?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final source = widget.post.sourceUserId?.trim();
    if (source != null && source.isNotEmpty) return source;
    return '';
  }

  bool _adLoadingInPlayer = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_adsEnabled) {
      _adLoadingInPlayer = true;
    }
    // Allow this screen to rotate into landscape for a better video experience.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _livePost = widget.post;
    _adsController = VideoDetailAdsController(
      postId: widget.post.id,
      adsEnabled: _adsEnabled,
      creatorIdProvider: () => _creatorId,
      startPlayback: () =>
          _playbackController?.startPlayback() ?? Future.value(),
      pausePlayback: () =>
          _playbackController?.pausePlayback() ?? Future.value(),
    )..addListener(_handleAdsChanged);
    final videoUrl = widget.post.preferredVideoUrl;
    if (videoUrl != null && videoUrl.isNotEmpty) {
      _playbackController = VideoDetailPlaybackController(
        rawVideoUrl: videoUrl,
        initialPosition: widget.initialPosition,
        autoPlay: widget.autoPlay,
        adsEnabled: () => _adsEnabled,
        rewardedReady: () => _adsController.rewardedReady,
        showRewarded: ({bool resumePlayback = true}) =>
            _adsController.showRewarded(resumePlayback: resumePlayback),
        loadRewarded: _adsController.loadRewarded,
        loadInlineNative: () {},
        onViewCounted: () => PostViewRetryQueue.record(widget.post.id, 1),
      )..addListener(_handlePlaybackChanged);
      unawaited(_preparePlaybackController());
    }
    _subscribePostRealtime();
    _loadEpisodeMeta();
    _loadVideoAd();
  }

  void _loadVideoAd() {
    if (!_adsEnabled) return;

    _videoAd = NativeAd(
      adUnitId: AdHelper.nativeForFeedSlot(999),
      factoryId: 'cardNative',
      request: const AdRequest(),
      nativeAdOptions: NativeAdOptions(
        videoOptions: VideoOptions(
          startMuted: false,
        ),
      ),
      customOptions: const <String, Object>{
        'adId': 'video_details_ad',
      },
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() {
            _adLoadingInPlayer = false;
            _adActiveInPlayer = true;
            _adCountdown = 5;
          });
          _playbackController?.controller?.pause();
          _startAdCountdown();
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) {
            setState(() {
              _adLoadingInPlayer = false;
              _videoAd = null;
              _adActiveInPlayer = false;
            });
            unawaited(_playbackController?.attemptAutoplay() ?? Future.value());
            _loadBottomAd();
          }
        },
      ),
    );
    _videoAd!.load();
  }

  void _loadBottomAd() {
    if (!_adsEnabled) return;
    _isBottomAdLoaded = false;
    _bottomAd = NativeAd(
      adUnitId: AdHelper.nativeForFeedSlot(999),
      factoryId: 'cardNative',
      request: const AdRequest(),
      nativeAdOptions: NativeAdOptions(
        videoOptions: VideoOptions(
          startMuted: true, // Muted by default
        ),
      ),
      customOptions: const <String, Object>{
        'adId': 'video_details_bottom_ad',
      },
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() {
            _isBottomAdLoaded = true;
          });
          // Delay slightly to let the native AdWidget mount before sending pause command
          Future.delayed(const Duration(milliseconds: 600), () {
            if (!mounted) return;
            _adsChannel.invokeMethod('pauseAdVideo', {'adId': 'video_details_bottom_ad'});
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) {
            setState(() {
              _bottomAd = null;
              _isBottomAdLoaded = false;
            });
          }
        },
      ),
    );
    _bottomAd!.load();
  }

  void _startAdCountdown() {
    _adCountdownTimer?.cancel();
    _adCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_adCountdown > 0) {
        setState(() {
          _adCountdown--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _skipAd() {
    _adCountdownTimer?.cancel();
    if (_videoAd != null) {
      _adsChannel.invokeMethod('pauseAdVideo', {'adId': 'video_details_ad'});
    }
    setState(() {
      _adActiveInPlayer = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _videoAd?.dispose();
      _videoAd = null;
      _loadBottomAd();
    });
    _playbackController?.playWithGate();
  }

  Future<void> _loadEpisodeMeta() async {
    try {
      final meta = await AppwriteService.fetchEpisodeMetadata(widget.post.id);
      if (!mounted) return;
      setState(() {
        _episodeMeta = meta['isEpisode'] == true ? meta : null;
      });
    } catch (_) {}
  }

  Future<void> _preparePlaybackController() async {
    await GlobalVideoManager.releaseActive();
    NativeAdPreloadService.releaseAll();
    final playback = _playbackController;
    if (playback == null) return;
    await playback.initialize();
    if (!mounted) return;
    if (_adLoadingInPlayer || _adActiveInPlayer) {
      playback.controller?.pause();
      return;
    }
    if (widget.autoPlay) {
      playback.queueAutoplayAfterFirstFrame();
    }
    if (!_adLoadingInPlayer && !_adActiveInPlayer) {
      await playback.attemptAutoplay();
    }
  }

  void _handleAdsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handlePlaybackChanged() {
    if (!mounted) return;
    setState(() {});

    final isPlaying = _playbackController?.isPlaying ?? false;
    if (isPlaying != _lastIsPlaying) {
      _lastIsPlaying = isPlaying;
      _adsChannel.invokeMethod('pauseAdVideo', {'adId': 'video_details_bottom_ad'});
    }
  }

  void _subscribePostRealtime() {
    try {
      final channel =
          'databases.${AppwriteService.databaseId}.collections.${AppwriteService.postsCollectionId}.documents';
      _postSub = AppwriteService.realtime.subscribe([channel]);
      _postSub?.stream.listen((event) {
        if (!mounted || event.events.isEmpty) return;
        final payload = event.payload;
        final payloadId =
            payload[r'$id']?.toString() ?? payload['id']?.toString();
        if (payloadId != widget.post.id) return;
        if (event.events.any((e) => e.contains('.delete'))) {
          return;
        }
        setState(() {
          _livePost = _applyPostPayload(_livePost ?? widget.post, payload);
        });
      });
    } catch (_) {}
  }

  Post _applyPostPayload(Post base, Map<String, dynamic> data) {
    int readInt(String key, int fallback) {
      final raw = data[key];
      if (raw is int) return raw;
      return int.tryParse('$raw') ?? fallback;
    }

    String? readString(String key) {
      final raw = data[key];
      if (raw == null) return null;
      final value = raw.toString().trim();
      return value.isEmpty ? null : value;
    }

    return Post(
      id: base.id,
      username: readString('username') ?? base.username,
      userAvatar: readString('userAvatar') ?? base.userAvatar,
      content: readString('content') ?? base.content,
      imageUrl: readString('imageUrl') ?? base.imageUrl,
      videoUrl: readString('videoUrl') ?? base.videoUrl,
      previewVideoUrl: readString('previewVideoUrl') ?? base.previewVideoUrl,
      hlsVideoUrl: readString('hlsVideoUrl') ?? base.hlsVideoUrl,
      postType: readString('postType') ?? base.postType,
      title: readString('title') ?? base.title,
      thumbnailUrl: readString('thumbnailUrl') ?? base.thumbnailUrl,
      timestamp: base.timestamp,
      likes: readInt('likes', base.likes),
      comments: readInt('comments', base.comments),
      reposts: readInt('reposts', base.reposts),
      impressions: readInt('impressions', base.impressions),
      views: readInt('views', base.views),
      isLiked: base.isLiked,
      isReposted: base.isReposted,
      isSaved: base.isSaved,
      sourcePostId: base.sourcePostId,
      sourceUserId: base.sourceUserId,
      sourceUsername: base.sourceUsername,
      textBgColor: base.textBgColor,
      isBoosted: base.isBoosted,
      activeBoostId: base.activeBoostId,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _adCountdownTimer?.cancel();
    _videoAd?.dispose();
    _bottomAd?.dispose();
    _commentController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _postSub?.close();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    final playback = _playbackController;
    if (playback != null) {
      playback.removeListener(_handlePlaybackChanged);
      playback.dispose();
    }
    _adsController
      ..removeListener(_handleAdsChanged)
      ..dispose();
    NativeAdPreloadService.releaseAll();
    super.dispose();
  }

  @override
  void didPushNext() {
    // Pause in place so the video stays on the current frame when a
    // profile or another route is opened on top of this screen.
    unawaited(_playbackController?.pausePlayback() ?? Future.value());
    NativeAdPreloadService.releaseAll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_playbackController?.pausePlayback() ?? Future.value());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final post = _livePost ?? widget.post;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final showOnlyVideo = _isFullscreen || (isLandscape && !kIsWeb);
    final onSurface = theme.colorScheme.onSurface;
    final surface = theme.colorScheme.surface;

    return WillPopScope(
      onWillPop: () async => !_adsController.blockBackNavigation,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: showOnlyVideo
            ? null
            : AppBar(
                backgroundColor: surface,
                elevation: 0,
                iconTheme: IconThemeData(color: onSurface),
                title: Text(
                  post.title?.isNotEmpty == true ? post.title! : 'Video',
                  style: TextStyle(color: onSurface),
                ),
              ),
        body: showOnlyVideo
            ? Center(child: _buildVideoPlayer(theme))
            : LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktopWide = kIsWeb && constraints.maxWidth > 1100;
                  if (isDesktopWide) {
                    return Column(
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  children: [
                                    _buildVideoPlayer(theme),
                                    Expanded(child: _buildMetaSection(theme)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: constraints.maxWidth * 0.32,
                                child: _buildSuggestionsSidebar(theme),
                              ),
                            ],
                          ),
                        ),
                        _buildBottomAdWidget(theme),
                        _buildCommentsEntry(),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            _buildVideoPlayer(theme),
                            Expanded(child: _buildMetaSection(theme)),
                          ],
                        ),
                      ),
                      _buildBottomAdWidget(theme),
                      _buildCommentsEntry(),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _buildMetaSection(ThemeData theme) {
    final post = _livePost ?? widget.post;

    Widget? bottomAdWidget;
    if (_bottomAd != null && _isBottomAdLoaded) {
      final videoAspect = _getVideoAspectRatio();
      bottomAdWidget = AspectRatio(
        aspectRatio: videoAspect / 1.2,
        child: AdWidget(ad: _bottomAd!),
      );
    }

    return VideoDetailMetaSection(
      post: post,
      authorId: widget.authorId,
      isGuest: widget.isGuest,
      onGuestAction: widget.onGuestAction,
      onOpenDescription: _openDescriptionSheet,
      adWidget: bottomAdWidget,
      bottomSection: _episodeMeta != null
          ? SeriesEpisodeTray(
              currentPostId: post.id,
              ownerUserId: ((_episodeMeta!['userId'] as String?) ?? '').trim(),
              seriesTitle:
                  ((_episodeMeta!['seriesTitle'] as String?) ?? '').trim(),
              contentType:
                  ((_episodeMeta!['episodeContentType'] as String?) ?? 'video')
                      .trim()
                      .toLowerCase(),
            )
          : null,
    );
  }

  Widget _buildBottomAdWidget(ThemeData theme) {
    return const SizedBox.shrink();
  }

  double _getVideoAspectRatio() {
    final controller = _playbackController?.controller;
    if (controller != null && controller.value.isInitialized) {
      final ratio = controller.value.aspectRatio;
      return ratio > 0 ? ratio : 16 / 9;
    }
    return 16 / 9;
  }

  double get _adContainerAspectRatio {
    final videoAspect = _getVideoAspectRatio();
    // Match the video resolution ratio, slightly adjusted (divided by 1.2 to increase height by 20%) to fit ad components perfectly.
    return videoAspect / 1.2;
  }

  Widget _buildVideoPlayer(ThemeData theme) {
    if (_adActiveInPlayer && _videoAd != null) {
      final screenHeight = MediaQuery.of(context).size.height;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.5,
        ),
        child: AspectRatio(
          aspectRatio: _adContainerAspectRatio,
          child: Container(
            color: Colors.black,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AdWidget(ad: _videoAd!),
                ),
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: GestureDetector(
                    onTap: _adCountdown == 0 ? _skipAd : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                      child: Text(
                        _adCountdown > 0 ? 'Skip in $_adCountdown...' : 'Skip Ad',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final playback = _playbackController;
    final controller = playback?.controller;
    if (playback != null && controller == null) {
      if (playback.hasError) {
        return SizedBox(
          height: 240,
          child: Center(
            child: Text(
              'Video not available',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
      return Container(
        height: 240,
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
        child: Center(
          child: CircularProgressIndicator(
            color: theme.colorScheme.primary,
          ),
        ),
      );
    }

    if (controller == null) {
      return SizedBox(
        height: 240,
        child: Center(
          child: Text(
            'Video not available',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return FutureBuilder<void>(
      future: playback?.initFuture,
      builder: (context, snapshot) {
        if (!controller.value.isInitialized) {
          if (widget.autoPlay &&
              !(playback?.autoplayQueued ?? false) &&
              !_adLoadingInPlayer &&
              !_adActiveInPlayer) {
            playback?.queueAutoplayAfterFirstFrame();
          }
          return Container(
            height: 240,
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
            child: Center(
              child: CircularProgressIndicator(
                color: theme.colorScheme.primary,
              ),
            ),
          );
        }
        if (widget.autoPlay &&
            !(playback?.autoplayQueued ?? false) &&
            !(playback?.autoplayAttempted ?? false) &&
            !_adLoadingInPlayer &&
            !_adActiveInPlayer) {
          playback?.queueAutoplayAfterFirstFrame();
        }
        final aspect = controller.value.aspectRatio == 0
            ? 16 / 9
            : controller.value.aspectRatio;
        return Stack(
          alignment: Alignment.center,
          children: [
            TvFocusableAction(
              onPressed: () {
                playback?.toggleControlsVisibility();
              },
              child: AspectRatio(
                aspectRatio: aspect,
                child: VideoPlayer(controller),
              ),
            ),
            // Top icons: fullscreen (left) and speaker (right), auto-hidden.
            Positioned(
              top: 12,
              left: 12,
              child: AnimatedOpacity(
                opacity: playback?.showControls == true ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !(playback?.showControls ?? false),
                  child: _buildControlButton(
                    icon: _isFullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    onTap: () {
                      setState(() => _isFullscreen = !_isFullscreen);
                      if (_isFullscreen) {
                        SystemChrome.setEnabledSystemUIMode(
                            SystemUiMode.immersiveSticky);
                      } else {
                        SystemChrome.setEnabledSystemUIMode(
                            SystemUiMode.edgeToEdge);
                      }
                      playback?.scheduleHideControls();
                    },
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: AnimatedOpacity(
                opacity: playback?.showControls == true ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !(playback?.showControls ?? false),
                  child: _buildControlButton(
                    icon: playback?.isMuted == true
                        ? Icons.volume_off
                        : Icons.volume_up,
                    onTap: () {
                      if (playback == null) return;
                      playback.setMuted(!playback.isMuted);
                    },
                  ),
                ),
              ),
            ),
            // Center controls: back / play-pause / forward, auto-hidden in the middle.
            AnimatedOpacity(
              opacity: playback?.showControls == true ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !(playback?.showControls ?? false),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildControlButton(
                        icon: Icons.replay_10,
                        onTap: () {
                          playback?.seekRelative(const Duration(seconds: -10));
                          playback?.scheduleHideControls();
                        },
                      ),
                      const SizedBox(width: 40),
                      _buildControlButton(
                        icon: playback?.playbackCompleted == true &&
                                !(playback?.isPlaying ?? false)
                            ? Icons.replay_circle_filled
                            : ((playback?.isPlaying ?? false)
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_fill),
                        onTap: () async => playback?.togglePrimaryAction(),
                      ),
                      const SizedBox(width: 40),
                      _buildControlButton(
                        icon: Icons.forward_10,
                        onTap: () {
                          playback?.seekRelative(const Duration(seconds: 10));
                          playback?.scheduleHideControls();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Bottom duration + progress, auto-hidden and pinned to the bottom of the video.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedOpacity(
                opacity: playback?.showControls == true ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !(playback?.showControls ?? false),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 16, bottom: 6),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            _formatDuration(
                              controller.value.position,
                              controller.value.duration,
                            ),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                      VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                        padding: const EdgeInsets.only(bottom: 4),
                        colors: const VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white54,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_adsController.showRewardedOverlay)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.7),
                  child: Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final screenH = MediaQuery.of(context).size.height;
                        final maxH = constraints.maxHeight.isFinite
                            ? constraints.maxHeight
                            : screenH;
                        final usableH = (maxH - 48).clamp(120.0, maxH);
                        final adHeight = (usableH * 0.6).clamp(120.0, usableH);
                        return Material(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    height: adHeight,
                                    width: double.infinity,
                                    child: const Center(
                                      child: Text(
                                        'Loading ads...',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Loading ads... video will resume',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  const SizedBox(height: 8),
                                  if (!_adsController.showRewardedOverlay)
                                    ElevatedButton(
                                      onPressed: null,
                                      child: const Text('Continue'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _openDescriptionSheet() {
    final theme = Theme.of(context);
    final description = (_livePost ?? widget.post).content.trim();
    if (description.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Description',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: theme.colorScheme.onSurface,
                        ),
                        children: buildTaggableSpans(
                          context,
                          description,
                          TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: theme.colorScheme.onSurface,
                          ),
                          null,
                          null,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlButton(
      {required IconData icon, required VoidCallback onTap}) {
    return TvFocusableAction(
      onPressed: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.all(6.0),
          child: Icon(icon, color: Colors.white, size: 35),
        ),
      ),
    );
  }

  Widget _buildSuggestionsSidebar(ThemeData theme) {
    final candidates = FeedCache.forYouPosts
        .where((p) =>
            p.id != widget.post.id &&
            p.videoUrl != null &&
            p.videoUrl!.isNotEmpty)
        .toList();
    if (candidates.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
      itemCount: candidates.length,
      itemBuilder: (context, index) {
        final post = candidates[index];
        final media = FeedCache.mediaByPostId[post.id];
        final authorId = FeedCache.authorByPostId[post.id];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: WatchVideoCard(
            post: post,
            mediaUrls: media,
            isGuest: widget.isGuest,
            onGuestAction: widget.onGuestAction,
            authorId: authorId,
            // Avoid extra ads inside sidebar suggestions.
            enableAds: false,
          ),
        );
      },
    );
  }

  Widget _buildCommentsEntry() {
    if (_isCommentsModalOpen) {
      return const SizedBox.shrink();
    }
    final post = _livePost ?? widget.post;
    return VideoDetailCommentsBar(
      commentCount: post.comments,
      controller: _commentController,
      isSubmitting: _isSubmittingComment,
      onSubmitted: _submitComment,
      onCommentIconTap: _openCommentsModal,
    );
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _isSubmittingComment) return;
    if (widget.isGuest) {
      widget.onGuestAction?.call();
      return;
    }

    setState(() => _isSubmittingComment = true);
    try {
      await AppwriteService.createComment(widget.post.id, text);
      unawaited(AppwriteService.incrementPostComments(widget.post.id, 1));

      if (!mounted) return;
      final currentPost = _livePost ?? widget.post;
      setState(() {
        _livePost = Post(
          id: currentPost.id,
          username: currentPost.username,
          userAvatar: currentPost.userAvatar,
          content: currentPost.content,
          imageUrl: currentPost.imageUrl,
          videoUrl: currentPost.videoUrl,
          previewVideoUrl: currentPost.previewVideoUrl,
          hlsVideoUrl: currentPost.hlsVideoUrl,
          postType: currentPost.postType,
          title: currentPost.title,
          thumbnailUrl: currentPost.thumbnailUrl,
          timestamp: currentPost.timestamp,
          likes: currentPost.likes,
          comments: currentPost.comments + 1,
          reposts: currentPost.reposts,
          impressions: currentPost.impressions,
          views: currentPost.views,
          isLiked: currentPost.isLiked,
          isReposted: currentPost.isReposted,
          isSaved: currentPost.isSaved,
          sourcePostId: currentPost.sourcePostId,
          sourceUserId: currentPost.sourceUserId,
          sourceUsername: currentPost.sourceUsername,
          textBgColor: currentPost.textBgColor,
          isBoosted: currentPost.isBoosted,
          activeBoostId: currentPost.activeBoostId,
        );
        _commentController.clear();
        _isSubmittingComment = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comment posted.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmittingComment = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to post comment. Please try again.')),
      );
    }
  }

  void _openCommentsModal() async {
    setState(() {
      _isCommentsModalOpen = true;
    });

    FocusScope.of(context).unfocus();

    await showCommentModal(
      context,
      post: _livePost ?? widget.post,
      isGuest: widget.isGuest,
      onGuestAction: widget.onGuestAction,
    );

    if (mounted) {
      setState(() {
        _isCommentsModalOpen = false;
      });
    }
  }

  String _formatDuration(Duration position, Duration total) =>
      _playbackController?.formatDuration(position, total) ?? '';
}
