import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'global_video_manager.dart';
import 'storage_service.dart';
import 'video_cache_service.dart';

class VideoDetailPlaybackController extends ChangeNotifier {
  static const Duration _viewThreshold = Duration(seconds: 1);
  static const Duration _controlsHideDelay = Duration(seconds: 3);
  static const Duration _videoEndBuffer = Duration(milliseconds: 500);
  static const Duration _tickThrottle = Duration(milliseconds: 250);

  final String rawVideoUrl;
  final Duration? initialPosition;
  final bool autoPlay;
  final bool Function() adsEnabled;
  final bool Function() rewardedReady;
  final Future<void> Function({bool resumePlayback}) showRewarded;
  final void Function() loadRewarded;
  final void Function() loadInlineNative;
  final Future<void> Function() onViewCounted;

  VideoDetailPlaybackController({
    required this.rawVideoUrl,
    required this.initialPosition,
    required this.autoPlay,
    required this.adsEnabled,
    required this.rewardedReady,
    required this.showRewarded,
    required this.loadRewarded,
    required this.loadInlineNative,
    required this.onViewCounted,
  });

  VideoPlayerController? _controller;
  Future<void>? _initFuture;
  String? _resolvedVideoUrl;
  bool _usingCachedFile = false;
  bool _isPlaying = false;
  bool _isMuted = false;
  bool _showControls = true;
  bool _countedView = false;
  bool _playbackCompleted = false;
  bool _initialPlayGateHandled = false;
  bool _autoplayAttempted = false;
  bool _autoplayQueued = false;
  bool _rewardedShownThisCycle = false;
  bool _hasError = false;
  DateTime? _lastTick;
  Timer? _hideControlsTimer;

  VideoPlayerController? get controller => _controller;
  Future<void>? get initFuture => _initFuture;
  bool get isPlaying => _isPlaying;
  bool get isMuted => _isMuted;
  bool get showControls => _showControls;
  bool get playbackCompleted => _playbackCompleted;
  bool get autoplayAttempted => _autoplayAttempted;
  bool get autoplayQueued => _autoplayQueued;
  bool get hasError => _hasError;

  Future<void> initialize() async {
    await GlobalVideoManager.claim(
      this,
      releaseOthers: releaseSurface,
    );
    if (_controller != null && _controller!.value.isInitialized) return;
    if (_initFuture != null) {
      await _initFuture;
      return;
    }
    _initFuture = _initializeInternal();
    try {
      await _initFuture;
    } finally {
      _initFuture = null;
    }
  }

  Future<void> _initializeInternal() async {
    try {
      final resolved =
          rawVideoUrl.startsWith('http://') || rawVideoUrl.startsWith('https://')
              ? rawVideoUrl
              : await StorageService.getVideoDisplayUrl(rawVideoUrl);
      _resolvedVideoUrl = resolved;
      final File? cachedFile =
          await VideoCacheService.getCachedFileIfAvailable(resolved);
      final controller = cachedFile != null
          ? VideoPlayerController.file(cachedFile)
          : VideoPlayerController.networkUrl(
              Uri.parse(resolved),
              httpHeaders: const {'Cache-Control': 'max-age=86400'},
            );
      await controller.initialize();
      controller.addListener(_onVideoTick);
      if (initialPosition != null) {
        await controller.seekTo(initialPosition!);
      }
      _controller = controller;
      _usingCachedFile = cachedFile != null;
      if (cachedFile == null) {
        unawaited(_cacheVideoForReplay(resolved));
      }
      _hasError = false;
      notifyListeners();
    } catch (e) {
      _hasError = true;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _cacheVideoForReplay(String resolvedUrl) async {
    await VideoCacheService.cacheVideo(resolvedUrl);
  }

  Future<void> _promoteCachedControllerForReplay() async {
    if (_usingCachedFile || _resolvedVideoUrl == null) return;
    final resolvedUrl = _resolvedVideoUrl!;
    File? cachedFile =
        await VideoCacheService.getCachedFileIfAvailable(resolvedUrl);
    cachedFile ??= await VideoCacheService.cacheVideo(resolvedUrl);
    if (cachedFile == null) return;

    final previous = _controller;
    final replacement = VideoPlayerController.file(cachedFile);
    await replacement.initialize();
    replacement.addListener(_onVideoTick);
    _controller = replacement;
    _usingCachedFile = true;

    if (previous != null) {
      previous.removeListener(_onVideoTick);
      await previous.dispose();
    }
    notifyListeners();
  }

  Future<void> pausePlayback() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isPlaying) {
      await _controller!.pause();
    }
    _isPlaying = false;
    _showControls = true;
    _hideControlsTimer?.cancel();
    notifyListeners();
  }

  void queueAutoplayAfterFirstFrame() {
    if (_autoplayQueued || _autoplayAttempted || !autoPlay) return;
    _autoplayQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_autoplayAttempted) return;
      unawaited(attemptAutoplay());
    });
  }

  Future<void> attemptAutoplay() async {
    if (!autoPlay || _autoplayAttempted) return;
    if (_controller == null || !_controller!.value.isInitialized) return;
    _autoplayAttempted = true;
    await playWithGate();
  }

  Future<void> playWithGate() async {
    if (_controller == null) return;
    if (_initialPlayGateHandled) {
      await startPlayback();
      return;
    }
    _initialPlayGateHandled = true;
    _rewardedShownThisCycle = false;
    await startPlayback();
    if (adsEnabled()) {
      loadRewarded();
    }
    loadInlineNative();
  }

  Future<void> startPlayback() async {
    if (_controller == null) return;
    if (_playbackCompleted ||
        (_controller!.value.position >=
                _controller!.value.duration - _videoEndBuffer &&
            _controller!.value.duration > Duration.zero)) {
      await _promoteCachedControllerForReplay();
      await _controller!.seekTo(Duration.zero);
    }
    await _controller!.play();
    _isPlaying = true;
    _playbackCompleted = false;
    scheduleHideControls();
    notifyListeners();
  }

  Future<void> handleReplayTap() async {
    if (_controller == null) return;
    restartPlaybackCycle();
    await _promoteCachedControllerForReplay();
    await _controller!.seekTo(Duration.zero);
    await _controller!.play();
    _isPlaying = true;
    _playbackCompleted = false;
    scheduleHideControls();
    notifyListeners();
  }

  void restartPlaybackCycle() {
    _countedView = false;
    _playbackCompleted = false;
    _showControls = true;
    notifyListeners();
  }

  Future<void> togglePrimaryAction() async {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      await _controller!.pause();
      _isPlaying = false;
      _showControls = true;
      _hideControlsTimer?.cancel();
      notifyListeners();
      return;
    }
    if (_playbackCompleted) {
      await handleReplayTap();
      return;
    }
    await playWithGate();
  }

  void toggleControlsVisibility() {
    _showControls = !_showControls;
    if (_showControls) {
      scheduleHideControls();
    } else {
      _hideControlsTimer?.cancel();
    }
    notifyListeners();
  }

  void setMuted(bool muted) {
    if (_controller == null) return;
    _isMuted = muted;
    _controller!.setVolume(_isMuted ? 0.0 : 1.0);
    scheduleHideControls();
    notifyListeners();
  }

  void seekRelative(Duration offset) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final current = _controller!.value.position;
    final target = current + offset;
    final total = _controller!.value.duration;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > total ? total : target);
    _controller!.seekTo(clamped);
  }

  void scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (_isPlaying) {
      _showControls = true;
      notifyListeners();
      _hideControlsTimer = Timer(_controlsHideDelay, () {
        if (_isPlaying) {
          _showControls = false;
          notifyListeners();
        }
      });
      return;
    }
    _showControls = true;
    notifyListeners();
  }

  String formatDuration(Duration position, Duration total) {
    String two(int n) => n.toString().padLeft(2, '0');
    final posMinutes = two(position.inMinutes.remainder(60));
    final posSeconds = two(position.inSeconds.remainder(60));
    final totMinutes = two(total.inMinutes.remainder(60));
    final totSeconds = two(total.inSeconds.remainder(60));
    return '$posMinutes:$posSeconds / $totMinutes:$totSeconds';
  }

  Future<void> releaseSurface() async {
    final controller = _controller;
    if (controller == null) return;
    GlobalVideoManager.clear(this);
    _hideControlsTimer?.cancel();
    controller.removeListener(_onVideoTick);
    _controller = null;
    _isPlaying = false;
    _showControls = true;
    _autoplayAttempted = false;
    _autoplayQueued = false;
    _lastTick = null;
    await controller.dispose();
    notifyListeners();
  }

  void _onVideoTick() {
    if (_controller == null) {
      return;
    }
    final controller = _controller!;
    if (!controller.value.isInitialized ||
        controller.value.duration <= Duration.zero) {
      return;
    }
    if (_playbackCompleted && !controller.value.isPlaying) {
      return;
    }

    final position = controller.value.position;
    final duration = controller.value.duration;

    if (position >= duration - _videoEndBuffer) {
      if (!_playbackCompleted) {
        _playbackCompleted = true;
        _isPlaying = false;
        _showControls = true;
        controller.pause();
        _hideControlsTimer?.cancel();
        notifyListeners();
        if (adsEnabled() && !_rewardedShownThisCycle) {
          _rewardedShownThisCycle = true;
          unawaited(showRewarded(resumePlayback: true));
        }
      }
      return;
    }

    final now = DateTime.now();
    if (_lastTick != null && now.difference(_lastTick!) < _tickThrottle) {
      return;
    }
    _lastTick = now;

    // Emit regular UI updates so the progress timestamp and scrubber stay in sync.
    notifyListeners();

    if (!_countedView &&
        controller.value.isPlaying &&
        position >= _viewThreshold) {
      _countedView = true;
      unawaited(onViewCounted());
    }
  }

  @override
  void dispose() {
    GlobalVideoManager.clear(this);
    _hideControlsTimer?.cancel();
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    super.dispose();
  }
}

