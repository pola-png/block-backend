import 'dart:async';

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/post.dart';
import '../screens/comment_screen.dart';
import '../screens/profile_screen.dart';
import '../services/backend_service.dart';
import '../services/native_ad_preload_service.dart';
import '../services/storage_service.dart';
import '../utils/share_utils.dart';
import '../services/post_view_retry_queue.dart';
import '../services/reel_ads_controller.dart';
import '../services/reel_playback_controller.dart';
import '../widgets/reel_author_footer.dart';
import '../widgets/reel_reaction_rail.dart';
import '../main.dart';

class ReelPlayer extends StatefulWidget {
  final Post post;
  final bool isGuest;
  final VoidCallback? onGuestAction;
  final String? authorId;
  final bool enableAds;
  final bool isActive;
  final bool isDetailSurface;
  final String? initialResolvedVideoUrl;
  final String? initialAuthorName;
  final String? initialAuthorAvatarUrl;
  final Post? nextEpisode;
  final Future<void> Function()? onPlayNextEpisode;
  final Widget? bottomOverlay;
  final double bottomInset;

  const ReelPlayer({
    super.key,
    required this.post,
    this.isGuest = false,
    this.onGuestAction,
    this.authorId,
    this.enableAds = true,
    this.isActive = true,
    this.isDetailSurface = false,
    this.initialResolvedVideoUrl,
    this.initialAuthorName,
    this.initialAuthorAvatarUrl,
    this.nextEpisode,
    this.onPlayNextEpisode,
    this.bottomOverlay,
    this.bottomInset = 0,
  });

  @override
  State<ReelPlayer> createState() => _ReelPlayerState();
}

class _ReelPlayerState extends State<ReelPlayer>
    with WidgetsBindingObserver, RouteAware {
  bool _isLiked = false;
  bool _isSaved = false;
  String _displayName = '';
  String? _resolvedAvatarUrl;
  bool _hasReposted = false;
  int _likeCount = 0;
  int _commentCount = 0;
  int _repostCount = 0;
  int? _viewCount;
  int _shareCount = 0;
  String _postContent = '';
  RealtimeSubscription? _postSub;
  late final ReelAdsController _adsController;
  ReelPlaybackController? _playbackController;
  late final Widget _videoSurface;
  Timer? _nextEpisodeTimer;
  int _nextEpisodeCountdown = 0;
  bool _nextEpisodeDismissed = false;
  bool get _adsEnabled =>
      widget.enableAds && !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  String get _creatorId {
    final direct = widget.authorId?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final source = widget.post.sourceUserId?.trim();
    if (source != null && source.isNotEmpty) return source;
    return '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _likeCount = widget.post.likes;
    _commentCount = widget.post.comments;
    _repostCount = widget.post.reposts;
    _viewCount = null;
    _shareCount = 0;
    _postContent = widget.post.content;
    _displayName = widget.initialAuthorName?.trim().isNotEmpty == true
        ? widget.initialAuthorName!.trim()
        : widget.post.username;
    _resolvedAvatarUrl = _normalizeImmediateAvatar(
      widget.initialAuthorAvatarUrl ?? widget.post.userAvatar,
    );
    _adsController = ReelAdsController(
      postId: widget.post.id,
      creatorIdProvider: () => _creatorId,
      startPlayback: () =>
          _playbackController?.startPlayback() ?? Future.value(),
      pausePlayback: () =>
          _playbackController?.pausePlayback() ?? Future.value(),
      adsEnabled: _adsEnabled,
    );
    if (_adsEnabled) {
      _adsController.loadRewarded();
    }
    unawaited(_initUserState());
    _loadAuthorProfile();
    _subscribePostRealtime();
    final seededUrl = widget.initialResolvedVideoUrl?.trim();
    final url = (seededUrl != null && seededUrl.isNotEmpty)
        ? seededUrl
        : widget.post.previewVideoUrl ??
            widget.post.videoUrl ??
            widget.post.hlsVideoUrl;
    if (url != null && url.isNotEmpty) {
      _playbackController = ReelPlaybackController(
        rawVideoUrl: url,
        isActive: widget.isActive,
        adsEnabled: () => _adsEnabled,
        rewardedReady: () => _adsController.rewardedReady,
        showRewarded: ({bool resumePlayback = true}) =>
            _adsController.showRewarded(resumePlayback: resumePlayback),
        loadRewarded: _adsController.loadRewarded,
        onViewCounted: () async {
          await PostViewRetryQueue.record(widget.post.id, 1);
        },
      );
      _playbackController!.addListener(_handlePlaybackStateChanged);
      _videoSurface = _ReelVideoSurface(
        playbackController: _playbackController!,
        adsController: _adsController,
        isInitiallyActive: widget.isActive,
      );
      if (widget.isActive || widget.isDetailSurface) {
        unawaited(_preparePlaybackController());
      }
    } else {
      _videoSurface = const Center(
        child: Text('Video unavailable'),
      );
    }
  }

  void _handlePlaybackStateChanged() {
    final playback = _playbackController;
    if (playback == null) return;
    if (!playback.playbackCompleted ||
        widget.nextEpisode == null ||
        widget.onPlayNextEpisode == null) {
      _cancelNextEpisodeCountdown();
      return;
    }
    if (_nextEpisodeDismissed || _nextEpisodeTimer != null) {
      return;
    }
    _nextEpisodeCountdown = 4;
    _nextEpisodeTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_nextEpisodeCountdown <= 1) {
        timer.cancel();
        _nextEpisodeTimer = null;
        await widget.onPlayNextEpisode?.call();
        return;
      }
      setState(() {
        _nextEpisodeCountdown -= 1;
      });
    });
    if (mounted) {
      setState(() {});
    }
  }

  void _cancelNextEpisodeCountdown({bool resetDismissed = true}) {
    _nextEpisodeTimer?.cancel();
    _nextEpisodeTimer = null;
    if (mounted && _nextEpisodeCountdown != 0) {
      setState(() {
        _nextEpisodeCountdown = 0;
        if (resetDismissed) {
          _nextEpisodeDismissed = false;
        }
      });
      return;
    }
    _nextEpisodeCountdown = 0;
    if (resetDismissed) {
      _nextEpisodeDismissed = false;
    }
  }

  Future<void> _preparePlaybackController() async {
    if (widget.isDetailSurface) {
      NativeAdPreloadService.releaseAll();
    }
    final playback = _playbackController;
    if (playback == null) return;
    if (!widget.isActive && !widget.isDetailSurface) return;
    await playback.initialize();
    if (!mounted) return;
    await playback.attemptAutoplay();
  }

  String? _normalizeImmediateAvatar(String? rawAvatar) {
    final avatar = rawAvatar?.trim();
    if (avatar == null || avatar.isEmpty) return null;
    return StorageService.getImageDisplayUrlSync(avatar);
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
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _postSub?.close();
    final playback = _playbackController;
    if (playback != null) {
      playback.removeListener(_handlePlaybackStateChanged);
      playback.dispose();
    }
    _nextEpisodeTimer?.cancel();
    _adsController.dispose();
    NativeAdPreloadService.releaseAll();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ReelPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authorId != widget.authorId ||
        oldWidget.post.userAvatar != widget.post.userAvatar ||
        oldWidget.post.id != widget.post.id) {
      _loadAuthorProfile();
    }
    _playbackController?.setActive(widget.isActive);
    if (!oldWidget.isActive && widget.isActive) {
      unawaited(_preparePlaybackController());
    } else if (oldWidget.isActive && !widget.isActive) {
      unawaited(_playbackController?.pausePlayback() ?? Future.value());
    }
  }

  @override
  void didPushNext() {
    // Navigation on top of the reel should pause immediately and keep the
    // current frame instead of tearing the controller down.
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

  Future<void> _initUserState() async {
    final user = await BackendService.getCurrentUser();
    if (!mounted) return;
    if (user == null) {
      setState(() {
        _isSaved = false;
        _isLiked = false;
      });
      return;
    }
    bool isLiked = false;
    bool isSaved = false;
    try {
      isLiked = await BackendService.isPostLikedBy(user.$id, widget.post.id);
      isSaved = await BackendService.isPostSavedBy(user.$id, widget.post.id);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isLiked = isLiked;
      _isSaved = isSaved;
    });
  }

  Future<void> _loadAuthorProfile() async {
    final authorId = widget.authorId?.trim();
    if (authorId == null || authorId.isEmpty) {
      final fallbackAvatar = await _resolveAvatarUrl(widget.post.userAvatar);
      if (!mounted) return;
      setState(() {
        _displayName = '';
        _resolvedAvatarUrl = fallbackAvatar;
      });
      return;
    }
    try {
      final profile = await BackendService.getProfileByUserId(authorId);
      final displayName = (profile?.data['displayName'] as String?)?.trim();
      final avatar = await _resolveAvatarUrl(
        ((profile?.data['avatarUrl'] as String?)?.trim().isNotEmpty == true)
            ? (profile!.data['avatarUrl'] as String)
            : widget.post.userAvatar,
      );
      if (!mounted) return;
      setState(() {
        _displayName = displayName?.isNotEmpty == true ? displayName! : '';
        _resolvedAvatarUrl = avatar;
      });
    } catch (_) {
      final fallbackAvatar = await _resolveAvatarUrl(widget.post.userAvatar);
      if (!mounted) return;
      setState(() {
        _displayName = '';
        _resolvedAvatarUrl = fallbackAvatar;
      });
    }
  }

  void _subscribePostRealtime() {
    try {
      final channel =
          'databases.${BackendService.databaseId}.collections.${BackendService.postsCollectionId}.documents';
      _postSub = BackendService.realtime.subscribe([channel]);
      _postSub?.stream.listen((event) {
        if (!mounted || event.events.isEmpty) return;
        final payload = event.payload;
        final payloadId =
            payload[r'$id']?.toString() ?? payload['id']?.toString();
        if (payloadId != widget.post.id) return;
        if (event.events.any((e) => e.contains('.delete'))) return;
        setState(() {
          _likeCount = _readInt(payload, 'likes', _likeCount);
          _commentCount = _readInt(payload, 'comments', _commentCount);
          _repostCount = _readInt(payload, 'reposts', _repostCount);
          _viewCount = _readInt(payload, 'views', _viewCount ?? 0);
          final content = payload['content']?.toString().trim();
          if (content != null && content.isNotEmpty) _postContent = content;
        });
      });
    } catch (_) {}
  }

  int _readInt(Map<String, dynamic> data, String key, int fallback) {
    final raw = data[key];
    if (raw is int) return raw;
    return int.tryParse('$raw') ?? fallback;
  }

  Future<String?> _resolveAvatarUrl(String? rawAvatar) async {
    final avatar = rawAvatar?.trim();
    if (avatar == null || avatar.isEmpty) {
      return null;
    }
    if (avatar.startsWith('http')) {
      return avatar;
    }
    try {
      return await StorageService.getImageDisplayUrl(avatar);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openAuthorProfile() async {
    final authorId = widget.authorId?.trim();
    if (authorId == null || authorId.isEmpty) {
      return;
    }
    final navigator = Navigator.of(context);
    await _playbackController?.pausePlayback();
    if (!mounted) return;
    navigator.push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: authorId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nextEpisode = widget.nextEpisode;
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: Stack(
        children: [
          Positioned.fill(child: _videoSurface),
          Positioned(
            top: 16,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: IconButton(
                onPressed: _showReportMenu,
                icon: const Icon(Icons.more_vert, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withOpacity(0.25),
                ),
              ),
            ),
          ),
          // Right side vertical reactions (like Watch reaction section, but stacked)
          ReelReactionRail(
            isLiked: _isLiked,
            isSaved: _isSaved,
            hasReposted: _hasReposted,
            likeCount: _likeCount,
            commentCount: _commentCount,
            repostCount: _repostCount,
            shareCount: _shareCount,
            onLike: _toggleLike,
            onSave: _toggleSave,
            onComment: _openComments,
            onRepost: _repostPost,
            onShare: _sharePost,
            bottomInset: widget.bottomInset,
          ),
          ReelAuthorFooter(
            displayName: _displayName,
            avatarUrl: _resolvedAvatarUrl,
            postContent: _postContent,
            viewCount: _viewCount,
            onOpenAuthorProfile: _openAuthorProfile,
            bottomInset: widget.bottomInset,
          ),
          if (nextEpisode != null &&
              _playbackController?.playbackCompleted == true &&
              !_nextEpisodeDismissed)
            Positioned(
              left: 16,
              right: 16,
              bottom: 120,
              child: SafeArea(
                top: false,
                child: _UpNextEpisodeCard(
                  post: nextEpisode,
                  countdown: _nextEpisodeCountdown,
                  onPlayNow: () async {
                    _cancelNextEpisodeCountdown(resetDismissed: false);
                    await widget.onPlayNextEpisode?.call();
                  },
                  onDismiss: () {
                    _cancelNextEpisodeCountdown(resetDismissed: false);
                    setState(() {
                      _nextEpisodeDismissed = true;
                    });
                  },
                ),
              ),
            ),
          if (widget.bottomOverlay != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: widget.bottomOverlay!,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleLike() async {
    if (widget.isGuest) {
      widget.onGuestAction?.call();
      return;
    }
    final targetLike = !_isLiked;
    final previousCount = _likeCount;
    setState(() {
      _isLiked = targetLike;
      _likeCount += targetLike ? 1 : -1;
      if (_likeCount < 0) _likeCount = 0;
    });
    try {
      if (targetLike) {
        await BackendService.likePost(widget.post.id);
      } else {
        await BackendService.unlikePost(widget.post.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLiked = !targetLike;
        _likeCount = previousCount;
      });
    }
  }

  void _openComments() {
    if (widget.isGuest) {
      widget.onGuestAction?.call();
      return;
    }
    showCommentModal(
      context,
      post: widget.post,
      isGuest: widget.isGuest,
      onGuestAction: widget.onGuestAction,
    );
  }

  Future<void> _repostPost() async {
    if (widget.isGuest) {
      widget.onGuestAction?.call();
      return;
    }
    final targetRepost = !_hasReposted;
    final previousCount = _repostCount;
    setState(() {
      _hasReposted = targetRepost;
      _repostCount += targetRepost ? 1 : -1;
      if (_repostCount < 0) _repostCount = 0;
    });
    try {
      await BackendService.repostPost(widget.post.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(targetRepost ? 'Reel reposted' : 'Repost removed'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasReposted = !_hasReposted;
        _repostCount = previousCount;
      });
    }
  }

  Future<void> _toggleSave() async {
    if (widget.isGuest) {
      widget.onGuestAction?.call();
      return;
    }
    final targetSave = !_isSaved;
    setState(() => _isSaved = targetSave);
    try {
      if (targetSave) {
        await BackendService.savePost(widget.post.id);
      } else {
        await BackendService.unsavePost(widget.post.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaved = !targetSave);
    }
  }

  void _sharePost() {
    setState(() => _shareCount++);
    BackendService.incrementPostShares(widget.post.id, 1);
    ShareUtils.sharePost(
      postId: widget.post.id,
      username: widget.post.username,
      content: widget.post.content,
    );
  }

  void _showReportMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bcontext) {
        final theme = Theme.of(bcontext);
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 10),
                _buildMenuTile(
                  context: bcontext,
                  icon: LucideIcons.userX,
                  label: 'Block user',
                  destructive: true,
                  onTap: () {
                    Navigator.of(bcontext).pop();
                    _showBlockConfirmation();
                  },
                ),
                _buildMenuTile(
                  context: bcontext,
                  icon: LucideIcons.flag,
                  label: 'Report reel',
                  destructive: true,
                  onTap: () {
                    Navigator.of(bcontext).pop();
                    _showReportConfirmation();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenuTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final theme = Theme.of(context);
    final color = destructive ? Colors.red : theme.colorScheme.onSurface;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onTap: onTap,
    );
  }

  void _showReportConfirmation() {
    showDialog(
      context: context,
      builder: (dcontext) => AlertDialog(
        title: const Text('Report Reel'),
        content: const Text('Are you sure you want to report this reel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dcontext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(dcontext);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await BackendService.reportPost(
                  widget.post.id,
                  'Inappropriate content',
                );
                if (!mounted) return;
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Reel reported.')),
                );
              } catch (_) {
                if (!mounted) return;
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Failed to report reel.')),
                );
              }
            },
            child: const Text('Report', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showBlockConfirmation() {
    final targetUserId = widget.authorId?.trim();
    if (targetUserId == null || targetUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This reel does not have a blockable author.'),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (dcontext) => AlertDialog(
        title: const Text('Block user'),
        content: const Text('Do you want to block this user?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dcontext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(dcontext);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await BackendService.blockUser(targetUserId);
                if (!mounted) return;
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('User blocked.')),
                );
              } catch (e) {
                if (!mounted) return;
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Failed to block user. Please try again.'),
                  ),
                );
              }
            },
            child: const Text('Block', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _UpNextEpisodeCard extends StatelessWidget {
  const _UpNextEpisodeCard({
    required this.post,
    required this.countdown,
    required this.onPlayNow,
    required this.onDismiss,
  });

  final Post post;
  final int countdown;
  final Future<void> Function() onPlayNow;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = (post.title?.trim().isNotEmpty == true)
        ? post.title!.trim()
        : post.content.trim().isNotEmpty
            ? post.content.trim()
            : 'Next episode';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.78),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 72,
              height: 96,
              child: post.thumbnailUrl != null && post.thumbnailUrl!.isNotEmpty
                  ? Image.network(post.thumbnailUrl!, fit: BoxFit.cover)
                  : Container(
                      color: Colors.white.withOpacity(0.08),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Up next',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  countdown > 0 ? 'Playing in ${countdown}s' : 'Ready to play',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.72),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              FilledButton(
                onPressed: onPlayNow,
                child: const Text('Play'),
              ),
              TextButton(
                onPressed: onDismiss,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReelVideoSurface extends StatefulWidget {
  final ReelPlaybackController playbackController;
  final ReelAdsController adsController;
  final bool isInitiallyActive;

  const _ReelVideoSurface({
    required this.playbackController,
    required this.adsController,
    required this.isInitiallyActive,
  });

  @override
  State<_ReelVideoSurface> createState() => _ReelVideoSurfaceState();
}

class _ReelVideoSurfaceState extends State<_ReelVideoSurface>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => false;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.playbackController,
        widget.adsController,
      ]),
      builder: (context, _) {
        final playback = widget.playbackController;
        final controller = playback.controller;
        if (controller == null) {
          if (playback.isActive) {
            playback.queueInitializeAfterFirstFrame();
          }
          return Center(
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          );
        }
        return FutureBuilder<void>(
          future: playback.initFuture,
          builder: (context, snap) {
            if (!controller.value.isInitialized) {
              return Center(
                child: CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary,
                ),
              );
            }
            if (!playback.autoplayAttempted && widget.isInitiallyActive) {
              playback.queueAutoplayAfterFirstFrame();
            }
            final size = controller.value.size;
            final aspect = controller.value.aspectRatio == 0
                ? (size.width > 0 && size.height > 0
                    ? size.width / size.height
                    : 9 / 16)
                : controller.value.aspectRatio;
            return RepaintBoundary(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => playback.togglePrimaryAction(),
                child: SizedBox.expand(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: size.width,
                          height: size.height,
                          child: AspectRatio(
                            aspectRatio: aspect,
                            child: VideoPlayer(controller),
                          ),
                        ),
                      ),
                      AnimatedOpacity(
                        opacity: playback.showControls ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: IgnorePointer(
                          ignoring: true,
                          child: Center(
                            child: Icon(
                              playback.playbackCompleted && !playback.isPlaying
                                  ? Icons.replay_circle_filled
                                  : (playback.isPlaying
                                      ? Icons.pause_circle_filled
                                      : Icons.play_circle_fill),
                              size: 48,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        bottom: 8,
                        child: Text(
                          playback.formatDuration(
                            controller.value.position,
                            controller.value.duration,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      if (widget.adsController.showRewardedOverlay)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withOpacity(0.7),
                            child: Center(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final screenH =
                                      MediaQuery.of(context).size.height;
                                  final maxH = constraints.maxHeight.isFinite
                                      ? constraints.maxHeight
                                      : screenH;
                                  final usableH =
                                      (maxH - 48).clamp(120.0, maxH);
                                  final adHeight =
                                      (usableH * 0.6).clamp(120.0, usableH);
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
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            const Text(
                                              'Loading ads... video will resume',
                                              style: TextStyle(
                                                  color: Colors.white),
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
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

