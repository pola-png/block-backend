import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'global_video_manager.dart';
import 'storage_service.dart';
import 'video_cache_service.dart';

class ReelPlaybackController extends ChangeNotifier {
  static const Duration _viewThreshold = Duration(seconds: 1);
  static const Duration _controlsHideDelay = Duration(seconds: 3);
  static const Duration _videoEndBuffer = Duration(milliseconds: 500);
  static const Duration _tickThrottle = Duration(milliseconds: 250);

  final String rawVideoUrl;
  final bool Function() adsEnabled;
  final bool Function() rewardedReady;
  final Future<void> Function({bool resumePlayback}) showRewarded;
  final void Function() loadRewarded;
  final Future<void> Function() onViewCounted;

  ReelPlaybackController({
    required this.rawVideoUrl,
    required bool isActive,
    required this.adsEnabled,
    required this.rewardedReady,
    required this.showRewarded,
    required this.loadRewarded,
    required this.onViewCounted,
  }) : _isActive = isActive;

  bool _isActive;
  VideoPlayerController? _controller;
  Future<void>? _initFuture;
  String? _resolvedVideoUrl;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _countedView = false;
  bool _playbackCompleted = false;
  bool _autoplayAttempted = false;
  bool _initialPlayGateHandled = false;
  bool _rewardedShownThisCycle = false;
  bool _holdAudioUntilFirstFrame = false;
  DateTime? _lastTick;
  Timer? _hideControlsTimer;

  VideoPlayerController? get controller => _controller;
  Future<void>? get initFuture => _initFuture;
  bool get isPlaying => _isPlaying;
  bool get showControls => _showControls;
  bool get playbackCompleted => _playbackCompleted;
  bool get autoplayAttempted => _autoplayAttempted;
  bool get isActive => _isActive;
  bool get hasController => _controller != null;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isInitializing => _initFuture != null && !isInitialized;

  void setActive(bool value) {
    if (_isActive == value) return;
    _isActive = value;
    notifyListeners();
  }

  Future<void> initialize() async {
    if (isInitialized) return;
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
    _resolvedVideoUrl ??=
        rawVideoUrl.startsWith('http://') || rawVideoUrl.startsWith('https://')
            ? rawVideoUrl
            : await StorageService.getVideoDisplayUrl(rawVideoUrl);
    final resolvedUrl = _resolvedVideoUrl!;
    final File? cachedFile =
        await VideoCacheService.getCachedFileIfAvailable(resolvedUrl);
    final controller = cachedFile != null
        ? VideoPlayerController.file(cachedFile)
        : VideoPlayerController.networkUrl(
            Uri.parse(resolvedUrl),
            httpHeaders: const {'Cache-Control': 'max-age=86400'},
          );
    controller.setLooping(false);
    await controller.initialize();
    controller.addListener(_onVideoTick);
    _controller = controller;
    _usingCachedFile = cachedFile != null;
    if (cachedFile == null) {
      unawaited(_cacheVideoForReplay(resolvedUrl));
    }
    notifyListeners();
  }

  bool _usingCachedFile = false;

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
    replacement.setLooping(false);
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

  void queueInitializeAfterFirstFrame() {
    if (_initFuture != null || isInitialized) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_initFuture != null || isInitialized) return;
      unawaited(initialize());
    });
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

  Future<void> attemptAutoplay() async {
    if (!_isActive || _autoplayAttempted) return;
    await initialize();
    if (_controller == null || !_controller!.value.isInitialized) return;
    _autoplayAttempted = true;
    await playWithGate();
  }

  void queueAutoplayAfterFirstFrame() {
    if (_autoplayAttempted || !_isActive) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_autoplayAttempted || !_isActive) return;
      unawaited(attemptAutoplay());
    });
  }

  Future<void> playWithGate() async {
    if (!_isActive) return;
    await initialize();
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
  }

  Future<void> startPlayback() async {
    if (!_isActive) return;
    await initialize();
    if (_controller == null) return;
    await GlobalVideoManager.claim(
      this,
      releaseOthers: releaseSurface,
    );
    final controller = _controller!;
    if (_playbackCompleted ||
        (controller.value.position >=
                controller.value.duration - _videoEndBuffer &&
            controller.value.duration > Duration.zero)) {
      await _promoteCachedControllerForReplay();
      await _controller!.seekTo(Duration.zero);
    }
    _holdAudioUntilFirstFrame = true;
    await controller.setVolume(0.0);
    await controller.play();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller != controller || !controller.value.isInitialized) return;
      if (!_holdAudioUntilFirstFrame) return;
      _holdAudioUntilFirstFrame = false;
      unawaited(controller.setVolume(1.0));
    });
    _isPlaying = true;
    _playbackCompleted = false;
    scheduleHideControls();
    notifyListeners();
  }

  Future<void> handleReplayTap() async {
    if (!_isActive) return;
    await initialize();
    if (_controller == null) return;
    await GlobalVideoManager.claim(
      this,
      releaseOthers: releaseSurface,
    );
    await _promoteCachedControllerForReplay();
    final controller = _controller!;
    restartPlaybackCycle();
    await controller.seekTo(Duration.zero);
    _holdAudioUntilFirstFrame = true;
    await controller.setVolume(0.0);
    await controller.play();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller != controller || !controller.value.isInitialized) return;
      if (!_holdAudioUntilFirstFrame) return;
      _holdAudioUntilFirstFrame = false;
      unawaited(controller.setVolume(1.0));
    });
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
    await initialize();
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

  void scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _showControls = true;
    notifyListeners();
    if (!_isPlaying) return;
    _hideControlsTimer = Timer(_controlsHideDelay, () {
      if (_isPlaying) {
        _showControls = false;
        notifyListeners();
      }
    });
  }

  Future<void> releaseSurface() async {
    final controller = _controller;
    if (controller == null) return;
    GlobalVideoManager.clear(this);
    _hideControlsTimer?.cancel();
    _holdAudioUntilFirstFrame = false;
    controller.removeListener(_onVideoTick);
    _controller = null;
    _isPlaying = false;
    _showControls = true;
    _autoplayAttempted = false;
    _lastTick = null;
    await controller.dispose();
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
        unawaited(controller.seekTo(Duration.zero));
        _hideControlsTimer?.cancel();
        notifyListeners();
        if (adsEnabled() && !_rewardedShownThisCycle && rewardedReady()) {
          _rewardedShownThisCycle = true;
          unawaited(showRewarded(resumePlayback: false));
        }
      }
      return;
    }

    final now = DateTime.now();
    if (_lastTick != null && now.difference(_lastTick!) < _tickThrottle) {
      return;
    }
    _lastTick = now;

    // Keep the UI progress readout and scrub state updating in real time.
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
    _holdAudioUntilFirstFrame = false;
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    super.dispose();
  }
}

