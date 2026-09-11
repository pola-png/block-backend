import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:video_player/video_player.dart';
import 'package:xapzap/services/backend_service.dart';
import 'package:xapzap/services/crypto_service.dart';

import '../models/status.dart';
import '../services/story_manager.dart';
import '../services/video_cache_service.dart';

class StatusViewerScreen extends StatefulWidget {
  final StatusUpdate status;

  const StatusViewerScreen({super.key, required this.status});

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen>
    with TickerProviderStateMixin {
  late final AnimationController _progressController;
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  final Set<String> _viewedStatusIds = <String>{};
  int _currentIndex = 0;
  bool _isPaused = false;
  bool _isPreparingMedia = false;
  bool _hasVideoError = false;
  bool _isReplyFocused = false;
  bool _isLongPressing = false;
  late StatusUpdate _currentStatus;
  late List<StatusMedia> _mediaItems;
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.status;
    _mediaItems = _buildMediaItems(_currentStatus);
    _progressController = AnimationController(
      duration: _mediaItems[_currentIndex].duration,
      vsync: this,
    )..addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
    _registerStoryView(_currentStatus);
    _replyFocusNode.addListener(_handleReplyFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmStoryMedia(_mediaItems);
      _prepareCurrentMedia();
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _closeViewer();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTapDown: (details) => _handleTap(details, context),
          onLongPressStart: (_) => _handleLongPressStart(),
          onLongPressEnd: (_) => _handleLongPressEnd(),
          onVerticalDragEnd: (details) {
            if (_isReplyFocused) return;
            if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
              // Swipe down gesture to close
              _closeViewer();
            }
          },
          onHorizontalDragEnd: (details) {
            if (_isReplyFocused) return;
            if (details.primaryVelocity != null) {
              if (details.primaryVelocity! < -300) {
                // Swipe left -> Next user status
                _advanceToNextStatus();
              } else if (details.primaryVelocity! > 300) {
                // Swipe right -> Previous user status
                _goToPreviousStatus();
              }
            }
          },
          child: Stack(
            children: [
              _buildContent(),
              AnimatedOpacity(
                opacity: _isLongPressing ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                child: IgnorePointer(
                  ignoring: _isLongPressing,
                  child: Stack(
                    children: [
                      _buildHeaderOverlay(),
                      _buildCaptionOverlay(),
                      _buildEngagementOverlay(),
                      _buildReplyArea(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCaptionOverlay() {
    if (_currentStatus.caption.isEmpty) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: 16,
      right: 16,
      bottom: 136,
      child: Text(
        _currentStatus.caption,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          shadows: [
            Shadow(
              color: Colors.black54,
              offset: Offset(0, 1),
              blurRadius: 4,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final media = _mediaItems[_currentIndex];
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (media.type == MediaType.image)
            CachedNetworkImage(
              imageUrl: media.url,
              fit: BoxFit.cover,
              progressIndicatorBuilder: (context, _, __) {
                return Center(
                  child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                );
              },
              errorWidget: (context, _, __) {
                return Container(
                  color: Colors.grey[800],
                  child: const Center(
                    child: Icon(
                      LucideIcons.imageOff,
                      color: Colors.white,
                      size: 50,
                    ),
                  ),
                );
              },
            )
          else if (_hasVideoError)
            Container(
              color: Colors.black,
              child: const Center(
                child: Icon(
                  LucideIcons.videoOff,
                  color: Colors.white70,
                  size: 64,
                ),
              ),
            )
          else if (_videoController == null ||
              !_videoController!.value.isInitialized ||
              _isPreparingMedia)
            Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          else
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: _videoController!.value.size.width,
                height: _videoController!.value.size.height,
                child: VideoPlayer(_videoController!),
              ),
            ),
          if (media.type == MediaType.video)
            Positioned(
              bottom: 90,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Video',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderOverlay() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          16,
          topPadding > 0 ? topPadding + 8 : 20,
          16,
          16,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          children: [
            Row(
              children: List.generate(_mediaItems.length, (index) {
                return Expanded(
                  child: Container(
                    height: 3,
                    margin: EdgeInsets.only(
                      right: index < _mediaItems.length - 1 ? 4 : 0,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: index < _currentIndex
                            ? 1.0
                            : index == _currentIndex
                                ? _progressController.value
                                : 0.0,
                        backgroundColor: Colors.white.withOpacity(0.35),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF29ABE2),
                    image: DecorationImage(
                      image: NetworkImage(_currentStatus.userAvatar),
                      fit: BoxFit.cover,
                      onError: (exception, stackTrace) {},
                    ),
                  ),
                  child: const Icon(
                    LucideIcons.user,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentStatus.username,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _formatTimestamp(_currentStatus.timestamp),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _closeViewer,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: const Icon(
                      LucideIcons.x,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEngagementOverlay() {
    return Positioned(
      left: 16,
      bottom: 84,
      child: Row(
        children: [
          _buildStatChip(
            icon: LucideIcons.heart,
            value: _currentStatus.likes,
          ),
          const SizedBox(width: 10),
          _buildStatChip(
            icon: LucideIcons.eye,
            value: _currentStatus.views,
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required int value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyArea() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          bottomPadding > 0 ? bottomPadding + 8 : 16,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _replyController,
                focusNode: _replyFocusNode,
                style: const TextStyle(color: Colors.white),
                onTap: _pauseProgressForReply,
                decoration: InputDecoration(
                  hintText: 'Reply...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: Colors.white),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendReply,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF29ABE2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.send,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleTap(TapDownDetails details, BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final tapPosition = details.globalPosition.dx;
    final tapPositionY = details.globalPosition.dy;

    if (tapPositionY >= screenHeight - 120 || _isReplyFocused) {
      return;
    }

    if (tapPosition > screenWidth / 2) {
      _nextMedia();
    } else {
      _previousMedia();
    }
  }

  void _startProgress() {
    _progressController
      ..reset()
      ..forward().then((_) {
        if (!_isPaused && mounted) {
          _nextMedia();
        }
      });
  }

  void _handleLongPressStart() {
    setState(() => _isLongPressing = true);
    _pauseProgress();
  }

  void _handleLongPressEnd() {
    setState(() => _isLongPressing = false);
    _resumeProgress();
  }

  void _pauseProgress() {
    setState(() => _isPaused = true);
    _progressController.stop();
    if (_videoController?.value.isInitialized == true) {
      _videoController?.pause();
    }
  }

  void _resumeProgress() {
    setState(() => _isPaused = false);
    if (_mediaItems[_currentIndex].type == MediaType.video &&
        _videoController?.value.isInitialized == true) {
      _videoController?.play();
    }
    _progressController.forward();
  }

  void _pauseProgressForReply() {
    if (_isReplyFocused) return;
    _isReplyFocused = true;
    _pauseProgress();
  }

  void _handleReplyFocusChanged() {
    final hasFocus = _replyFocusNode.hasFocus;
    if (hasFocus) {
      _pauseProgressForReply();
      return;
    }
    if (!_isReplyFocused) return;
    _isReplyFocused = false;
    if (mounted) {
      _resumeProgress();
    }
  }

  Future<void> _prepareCurrentMedia() async {
    if (!mounted) return;
    final media = _mediaItems[_currentIndex];
    _progressController.stop();
    _hasVideoError = false;
    _isPreparingMedia = true;
    setState(() {});

    if (media.type == MediaType.image) {
      await _disposeVideoController();
      await _precacheStoryImage(media.url);
      _progressController.duration = media.duration;
      _isPreparingMedia = false;
      if (!_isPaused && mounted) {
        setState(() {});
        _startProgress();
      }
      return;
    }

    await _disposeVideoController();
    final cachedFile = await VideoCacheService.getCachedFileIfAvailable(
      media.url,
    );
    if (cachedFile == null) {
      VideoCacheService.warm(media.url);
    }
    final controller = cachedFile != null
        ? VideoPlayerController.file(cachedFile)
        : VideoPlayerController.networkUrl(Uri.parse(media.url));
    _videoController = controller;
    controller.addListener(_handleVideoTick);
    try {
      await controller.initialize();
      if (!mounted || _videoController != controller) {
        await controller.dispose();
        return;
      }
      final rawDuration = controller.value.duration;
      _progressController.duration =
          rawDuration > Duration.zero ? rawDuration : media.duration;
      _isPreparingMedia = false;
      setState(() {});
      if (!_isPaused) {
        await controller.play();
        _startProgress();
      }
    } catch (_) {
      if (_videoController == controller) {
        _hasVideoError = true;
        _isPreparingMedia = false;
        _progressController.duration = media.duration;
        setState(() {});
        if (!_isPaused) {
          _startProgress();
        }
      }
    }
  }

  void _handleVideoTick() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.hasError) {
      setState(() {
        _hasVideoError = true;
      });
      return;
    }
    final duration = controller.value.duration;
    final position = controller.value.position;
    if (duration > Duration.zero && position >= duration) {
      _nextMedia();
    }
  }

  Future<void> _disposeVideoController() async {
    final controller = _videoController;
    _videoController = null;
    if (controller == null) return;
    controller.removeListener(_handleVideoTick);
    await controller.dispose();
  }

  void _nextMedia() {
    if (_currentIndex < _mediaItems.length - 1) {
      setState(() => _currentIndex++);
      unawaited(_prepareCurrentMedia());
    } else {
      _advanceToNextStatus();
    }
  }

  void _previousMedia() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      unawaited(_prepareCurrentMedia());
    } else {
      _goToPreviousStatus(startAtLast: true);
    }
  }

  void _goToPreviousStatus({bool startAtLast = false}) {
    final list = StoryManager.stories.value;
    final idx = list.indexWhere((s) => s.id == _currentStatus.id);

    // Find the previous user status that has active stories
    int prevIdx = idx - 1;
    while (prevIdx >= 0) {
      final candidate = list[prevIdx];
      final hasActive = candidate.id != 'me' ||
          candidate.mediaUrls.isNotEmpty ||
          candidate.isUploading;
      if (hasActive) {
        break;
      }
      prevIdx--;
    }

    if (prevIdx >= 0) {
      final prev = list[prevIdx];
      final prevMedia = _buildMediaItems(prev);
      setState(() {
        _currentStatus = prev;
        _mediaItems = prevMedia;
        _currentIndex = startAtLast ? prevMedia.length - 1 : 0;
      });
      unawaited(_registerStoryView(prev));
      _warmStoryMedia(_mediaItems);
      unawaited(_prepareCurrentMedia());
    } else {
      // At the first user's first story, restart it
      _currentIndex = 0;
      unawaited(_prepareCurrentMedia());
    }
  }

  void _sendReply() async {
    if (_replyController.text.trim().isNotEmpty) {
      try {
        final currentUser = await BackendService.getCurrentUser();
        if (currentUser == null) return;

        final chatId = await BackendService.getChatId(
          currentUser.$id,
          widget.status.id,
        );

        final enc = await CryptoService.encryptMessage(
          chatId: chatId,
          partnerUserId: widget.status.id,
          plaintext: _replyController.text.trim(),
        );
        if (enc == null) {
          throw StateError('Secure messaging is not ready on this device.');
        }

        await BackendService.createDocument(
          BackendService.messagesCollectionId,
          {
            'chatId': chatId,
            'senderId': currentUser.$id,
            'ciphertext': enc['ciphertext'],
            'nonce': enc['nonce'],
            'mac': enc['mac'],
            'e2eeVersion': CryptoService.currentE2eeVersion,
            'mediaUrl': '',
            'thumbnailUrl': '',
            'mediaType': 'text',
            'timestamp': DateTime.now().toIso8601String(),
            'isRead': false,
            'isEdited': false,
            'readBy': currentUser.$id,
          },
        );

        _replyController.clear();
        _replyFocusNode.unfocus();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reply sent!'),
            duration: Duration(seconds: 1),
          ),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send reply. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  List<StatusMedia> _buildMediaItems(StatusUpdate status) {
    final urls = status.mediaUrls;
    final items = urls.map((url) {
      final isVideo = _looksLikeVideoUrl(url);
      return StatusMedia(
        id: url,
        url: url,
        type: isVideo ? MediaType.video : MediaType.image,
        duration:
            isVideo ? const Duration(seconds: 20) : const Duration(seconds: 20),
      );
    }).toList();
    if (items.isNotEmpty) return items;
    final fallbackUrl = status.userAvatar.isNotEmpty
        ? status.userAvatar
        : 'https://via.placeholder.com/400x600';
    return [
      StatusMedia(
        id: status.id,
        url: fallbackUrl,
        type: MediaType.image,
        duration: const Duration(seconds: 20),
      ),
    ];
  }

  bool _looksLikeVideoUrl(String url) {
    final normalized = url.toLowerCase();
    final uri = Uri.tryParse(url);
    final candidate = uri?.queryParameters['filename']?.toLowerCase() ??
        uri?.queryParameters['path']?.toLowerCase() ??
        normalized;
    return candidate.endsWith('.mp4') ||
        candidate.endsWith('.mov') ||
        candidate.endsWith('.webm') ||
        candidate.endsWith('.mkv') ||
        candidate.endsWith('.m4v') ||
        candidate.endsWith('.m3u8');
  }

  Future<void> _registerStoryView(StatusUpdate status) async {
    if (_viewedStatusIds.contains(status.id)) return;
    _viewedStatusIds.add(status.id);
    setState(() {
      status.views += 1;
    });
    await BackendService.incrementStatusViews(status.id, 1);
  }

  void _advanceToNextStatus() {
    final list = StoryManager.stories.value;
    final idx = list.indexWhere((s) => s.id == _currentStatus.id);

    // Find the next user status that has active stories
    int nextIdx = idx + 1;
    while (nextIdx < list.length) {
      final candidate = list[nextIdx];
      final hasActive = candidate.id != 'me' ||
          candidate.mediaUrls.isNotEmpty ||
          candidate.isUploading;
      if (hasActive) {
        break;
      }
      nextIdx++;
    }

    if (nextIdx < list.length) {
      final next = list[nextIdx];
      StoryManager.markViewed(next.id);
      setState(() {
        _currentStatus = next;
        _mediaItems = _buildMediaItems(next);
        _currentIndex = 0;
      });
      unawaited(_registerStoryView(next));
      _warmStoryMedia(_mediaItems);
      unawaited(_prepareCurrentMedia());
    } else {
      _closeViewer();
    }
  }

  void _warmStoryMedia(List<StatusMedia> items) {
    for (final item in items) {
      if (item.type == MediaType.video) {
        VideoCacheService.warm(item.url);
        continue;
      }
      unawaited(_precacheStoryImage(item.url));
    }
  }

  Future<void> _precacheStoryImage(String url) async {
    if (!mounted || url.trim().isEmpty) return;
    try {
      await precacheImage(CachedNetworkImageProvider(url), context);
    } catch (_) {}
  }

  void _closeViewer() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _progressController.dispose();
    _replyController.dispose();
    _replyFocusNode.dispose();
    unawaited(_disposeVideoController());
    super.dispose();
  }
}
