import 'dart:async';
import 'dart:math' as math;



import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:lucide_icons/lucide_icons.dart';
import '../utils/share_utils.dart';

import '../models/post.dart';
import '../screens/comment_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/edit_post_screen.dart';
import '../screens/episode_editor_screen.dart';
import '../services/appwrite_service.dart';
import '../services/storage_service.dart';
import '../services/avatar_cache.dart';
import '../screens/hashtag_feed_screen.dart';
import '../screens/boost_post_screen.dart';
import 'taggable_text.dart';
import 'verification_badge.dart';

class PostCard extends StatefulWidget {
  final Post post;
  final bool isGuest;
  final VoidCallback? onGuestAction;
  final List<String>? mediaUrls;
  final String? authorId;
  final VoidCallback? onOpenPost;
  final VoidCallback? onDeleted;
  final bool isDetail;
  final bool trackImpressions;
  final bool showViewsLabel;
  final int? videoDescriptionMaxLines;
  final VoidCallback? onVideoDescriptionTap;
  final bool showVideoMeta;
  final bool showReelBadge;
  final bool showReactions;
  final bool showVideoDescription;

  const PostCard({
    super.key,
    required this.post,
    this.isGuest = false,
    this.onGuestAction,
    this.mediaUrls,
    this.authorId,
    this.onOpenPost,
    this.onDeleted,
    this.isDetail = false,
    this.trackImpressions = true,
    this.showViewsLabel = false,
    this.showVideoMeta = true,
    this.videoDescriptionMaxLines,
    this.onVideoDescriptionTap,
    this.showReelBadge = false,
    this.showReactions = true,
    this.showVideoDescription = true,
  });

  /// Pre-warms the post liked cache from HomeScreen's prefetch.
  static void primePostLikedCache(String postId, bool isLiked) {
    _PostCardState._likeCache[postId] = isLiked;
  }

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  static const int _displayNameCharacterLimit = 13;
  static const Color _savedColor = Color(0xFFEAB308);
  // Cache signed URLs for avatar keys within a single run.
  static final Map<String, String?> _avatarSignedCacheByKey =
      <String, String?>{};
  static final Map<String, String?> _resolvedMediaUrlCache =
      <String, String?>{};
  // Cache display names so we can show the up-to-date
  // profile displayName instead of the stale username
  // snapshot stored on each post row.
  static final Map<String, String?> _displayNameByUserId = <String, String?>{};
  static final Map<String, String?> _displayNameByUsername =
      <String, String?>{};
  static final Map<String, bool> _isVerifiedByUserId = <String, bool>{};
  static final Map<String, bool> _isAdminByUserId = <String, bool>{};
  static final Map<String, bool> _likeCache = <String, bool>{};


  bool _isLiked = false;
  bool _isVerified = false;
  bool _isAdmin = false;
  int _likeCount = 0;
  int _commentCount = 0;
  int _repostCount = 0;
  int _impressionCount = 0;
  // ignore: unused_field
  int _shareCount = 0;

  bool _isSaved = false;
  int _currentMediaIndex = 0;
  bool _hasReposted = false;
  bool _followLoaded = false;
  String _displayName = '';

  String? _currentUserId;
  bool _isFollowing = false;
  final Map<String, String> _signedCache = {};
  PageController? _pageController;

  /// Batched impression writes — avoids one DB write per card per scroll frame.
  static final Map<String, int> _pendingImpressions = <String, int>{};
  static Timer? _impressionFlushTimer;

  static void _flushImpressions() {
    if (_pendingImpressions.isEmpty) return;
    final batch = Map<String, int>.from(_pendingImpressions);
    _pendingImpressions.clear();
    for (final entry in batch.entries) {
      unawaited(AppwriteService.incrementPostImpressions(entry.key, entry.value));
    }
  }

  static void _queueImpression(String postId) {
    _pendingImpressions[postId] = (_pendingImpressions[postId] ?? 0) + 1;
    _impressionFlushTimer?.cancel();
    _impressionFlushTimer = Timer(const Duration(seconds: 3), _flushImpressions);
  }


  @override
  void initState() {
    super.initState();
    _isLiked = _likeCache[widget.post.id] ?? widget.post.isLiked;
    _likeCount = widget.post.likes;
    _commentCount = widget.post.comments;
    _repostCount = widget.post.reposts;
    _impressionCount = widget.post.impressions;

    final me = AppwriteService.getCurrentUserSync();
    if (me != null) {
      _currentUserId = me.$id;
      final cachedLiked = AppwriteService.isPostLikedBySync(widget.post.id);
      final cachedSaved = AppwriteService.isPostSavedBySync(widget.post.id);
      final cachedReposted = AppwriteService.isPostRepostedBySync(widget.post.id);
      if (cachedLiked != null) {
        _isLiked = cachedLiked;
        _likeCache[widget.post.id] = _isLiked;
      }
      if (cachedSaved != null) _isSaved = cachedSaved;
      if (cachedReposted != null) _hasReposted = cachedReposted;

      if (widget.authorId != null && widget.authorId != me.$id) {
        final cachedFollowing =
            AppwriteService.isFollowingSync(me.$id, widget.authorId!);
        if (cachedFollowing != null) {
          _isFollowing = cachedFollowing;
          _followLoaded = true;
        } else {
          _isFollowing = false;
          _followLoaded = true;
        }
      } else {
        _followLoaded = true;
      }
    } else {
      _followLoaded = true;
    }

    _syncUserMeta();
    _initUserAndFollow();
    _prefetchInitialMedia();
    // Batch impression writes — all visible cards flush together after 3s idle.
    if (widget.trackImpressions) {
      _impressionCount += 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _queueImpression(widget.post.id);
      });
    }
  }


  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authorId != widget.authorId ||
        oldWidget.post.username != widget.post.username ||
        oldWidget.post.userAvatar != widget.post.userAvatar) {
      _syncUserMeta();
    }
    if (oldWidget.post.id != widget.post.id) {
      // New post entirely: sync fresh state.
      _isLiked = _likeCache[widget.post.id] ?? widget.post.isLiked;
      _likeCount = widget.post.likes;
      _commentCount = widget.post.comments;
      _repostCount = widget.post.reposts;
      _impressionCount = widget.post.impressions;
      _isSaved = widget.post.isSaved;
      _hasReposted = widget.post.isReposted;
    } else {
      // Same post instance refreshed; do not wipe a like that was already set locally.
      if (!_isLiked && widget.post.isLiked) {
        _isLiked = true;
      }
      // Keep counts in sync when server values increase.
      if (widget.post.likes > _likeCount) _likeCount = widget.post.likes;
      if (widget.post.comments > _commentCount) {
        _commentCount = widget.post.comments;
      }
      if (widget.post.reposts > _repostCount) {
        _repostCount = widget.post.reposts;
      }
      if (widget.post.impressions > _impressionCount) {
        _impressionCount = widget.post.impressions;
      }
      if (!_isSaved && widget.post.isSaved) _isSaved = true;
      if (!_hasReposted && widget.post.isReposted) _hasReposted = true;
    }
  }

  String? _avatarUrl;

  int _contentMaxLines() {
    final postType = (widget.post.postType ?? '').toLowerCase();
    final contentLength = widget.post.content.length;
    if (postType.contains('video') ||
        postType.contains('reel') ||
        postType.contains('short')) {
      return 2;
    }
    if (contentLength >= 1000) {
      return 5;
    }
    if (contentLength >= 400) {
      return 3;
    }
    return 2;
  }

  void _syncUserMeta() {
    final userId = widget.authorId;
    final handle = widget.post.username.replaceAll('@', '').trim().toLowerCase();

    _displayName = _truncateDisplayName(widget.post.username);
    _isVerified = false;
    _isAdmin = false;

    final rawAvatar = widget.post.userAvatar;
    if (rawAvatar.isNotEmpty) {
      if (rawAvatar.startsWith('http://') || rawAvatar.startsWith('https://')) {
        _avatarUrl = rawAvatar;
      } else {
        _avatarUrl = _avatarSignedCacheByKey[rawAvatar] ?? _resolvedMediaUrlCache[rawAvatar];
        if (_avatarUrl == null) {
          _resolveSigned(rawAvatar).then((resolved) {
            if (resolved != null) {
              _avatarSignedCacheByKey[rawAvatar] = resolved;
              if (mounted) {
                setState(() {
                  _avatarUrl = resolved;
                });
              }
            }
          });
        }
      }
    } else {
      _avatarUrl = null;
    }

    if (userId != null && userId.isNotEmpty) {
      if (_isVerifiedByUserId.containsKey(userId)) {
        _isVerified = _isVerifiedByUserId[userId]!;
      }
      if (_isAdminByUserId.containsKey(userId)) {
        _isAdmin = _isAdminByUserId[userId]!;
      }
      final cachedDN = _displayNameByUserId[userId];
      if (cachedDN != null && cachedDN.isNotEmpty) {
        _displayName = _truncateDisplayName(cachedDN);
      }

      final cachedAvatar = AvatarCache.getForUserId(userId);
      if (cachedAvatar != null) {
        _avatarUrl = cachedAvatar;
      }

      final cachedProfile = AppwriteService.getCachedProfileByUserId(userId);
      if (cachedProfile != null) {
        final dn = (cachedProfile.data['displayName'] as String?)?.trim();
        if (dn != null && dn.isNotEmpty) {
          _displayName = _truncateDisplayName(dn);
        }
        _isVerified = cachedProfile.data['isVerified'] == true ||
            cachedProfile.data['verified'] == true;
        _isAdmin = cachedProfile.data['isAdmin'] == true;
        final avatar = (cachedProfile.data['avatarUrl'] as String?)?.trim();
        if (avatar != null && avatar.isNotEmpty) {
          if (avatar.startsWith('http://') || avatar.startsWith('https://')) {
            _avatarUrl = avatar;
          } else {
            _avatarUrl = _avatarSignedCacheByKey[avatar] ?? _resolvedMediaUrlCache[avatar];
            if (_avatarUrl == null) {
              _resolveSigned(avatar).then((resolved) {
                if (resolved != null) {
                  _avatarSignedCacheByKey[avatar] = resolved;
                  if (mounted) {
                    setState(() {
                      _avatarUrl = resolved;
                    });
                  }
                }
              });
            }
          }
        }
      }
    } else if (handle.isNotEmpty) {
      final cachedDN = _displayNameByUsername[handle];
      if (cachedDN != null && cachedDN.isNotEmpty) {
        _displayName = _truncateDisplayName(cachedDN);
      }
      final cachedAvatar = AvatarCache.getForUsername(handle);
      if (cachedAvatar != null) {
        _avatarUrl = cachedAvatar;
      }
    }
  }

  Future<void> _initUserAndFollow() async {
    // Resolved synchronously in initState(). No async queries or late setState calls.
  }



  void _prefetchInitialMedia() {
    final urls = widget.mediaUrls ??
        (widget.post.imageUrl != null ? [widget.post.imageUrl!] : <String>[]);
    if (urls.isNotEmpty) {
      _resolveSigned(urls.first).then((u) {
        if (u != null) _precache(u);
      });
      if (urls.length > 1) {
        _resolveSigned(urls[1]).then((u) {
          if (u != null) _precache(u);
        });
      }
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final postTypeLower = (widget.post.postType ?? '').toLowerCase();
    final isReelPost =
        postTypeLower.contains('reel') || postTypeLower.contains('short');
    final isVideoPost = postTypeLower.contains('video') || isReelPost;
    // Faint dark gap between posts, adapt to theme.
    final gapColor = isDark ? Colors.black : Colors.black.withOpacity(0.03);

    final card = Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (widget.post.content.isNotEmpty && !isVideoPost)
            _buildTextContent(),
          // For video/reel posts, only show the media/placeholder in feed cards,
          // not inside detail screens where the dedicated player is used.
          if ((widget.mediaUrls?.isNotEmpty ?? false) ||
              widget.post.imageUrl != null ||
              (isVideoPost && !widget.isDetail))
            _buildMediaContent(),
          if (isVideoPost && !isReelPost && widget.showVideoMeta)
            _buildVideoMeta(),
          if (widget.showReactions) _buildActions(),
        ],
      ),
    );

    if (widget.isDetail) {
      // In detail view, render the card without outer gap so comments can sit flush below.
      return card;
    }

    return Container(
      color: gapColor,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: card,
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final displayName = _displayName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.post.sourceUsername != null &&
              widget.post.sourceUsername!.isNotEmpty &&
              widget.post.sourceUsername != widget.post.username)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${widget.post.sourceUsername} reposted',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          Row(
            children: [
              GestureDetector(onTap: _openAuthorProfile, child: _buildAvatar()),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _openAuthorProfile,
                  behavior: HitTestBehavior.translucent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: theme.brightness == Brightness.dark
                                  ? Colors.white
                                  : Colors.black,
                            ),
                          ),
                          if (_isVerified || _isAdmin)
                            VerificationBadge(
                              size: 16,
                              isPremium: _isAdmin,
                            ),
                          if (widget.showViewsLabel)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.eye,
                                  size: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _formatCompactCount(widget.post.views),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          Text(
                            _formatTimestamp(widget.post.timestamp),
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (!widget.isGuest &&
                  widget.authorId != null &&
                  _currentUserId != null &&
                  widget.authorId != _currentUserId &&
                  _followLoaded &&
                  !_isFollowing)
                ElevatedButton(
                  onPressed: _toggleFollow,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    backgroundColor: _isFollowing
                        ? Colors.blue.shade50
                        : const Color(0xFF3B82F6),
                    foregroundColor:
                        _isFollowing ? const Color(0xFF1D4ED8) : Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: Text(
                    _isFollowing ? 'Following' : 'Follow',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              IconButton(
                icon: Icon(
                  Icons.more_vert,
                  color: theme.iconTheme.color,
                ),
                onPressed: () => _showReportMenu(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final avatarUrl = _avatarUrl;
    if (avatarUrl == null || avatarUrl.isEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: Colors.grey[200],
        child: const Icon(Icons.person, color: Colors.grey),
      );
    }
    return CircleAvatar(
      radius: 20,
      backgroundColor: Colors.grey[200],
      backgroundImage: NetworkImage(avatarUrl),
    );
  }



  void _openAuthorProfile() async {
    if (widget.isGuest) {
      widget.onGuestAction?.call();
      return;
    }

    // Prefer explicit authorId (userId from posts table).
    String? userId = widget.authorId;

    // Fallback: resolve by @username via profiles table.
    if ((userId == null || userId.isEmpty) && widget.post.username.isNotEmpty) {
      final handle = widget.post.username.replaceAll('@', '').trim();
      if (handle.isNotEmpty) {
        final prof = await AppwriteService.getProfileByUsername(handle);
        if (prof != null) {
          userId = prof.data['userId'] as String? ?? prof.$id;
        }
      }
    }

    // If we still don't have a userId, do nothing.
    if (userId == null || userId.isEmpty) {
      return;
    }

    // Check against the live logged-in user so we always
    // recognize our own profile correctly.
    final me = await AppwriteService.getCurrentUser();
    final isMe = me != null && userId == me.$id;

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            isMe ? const ProfileScreen() : ProfileScreen(userId: userId),
      ),
    );
  }

  Future<void> _openEditPost() async {
    if (widget.isGuest) return;
    Map<String, dynamic> meta = const <String, dynamic>{'isEpisode': false};
    try {
      meta = await AppwriteService.fetchEpisodeMetadata(widget.post.id);
    } catch (_) {}
    if (!mounted) return;
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => meta['isEpisode'] == true
            ? EpisodeEditorScreen(post: widget.post)
            : EditPostScreen(post: widget.post),
      ),
    );
    if (updated == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Post updated')));
    }
  }

  Widget _buildTextContent() {
    final theme = Theme.of(context);
    final hasMedia =
        widget.post.imageUrl != null || widget.post.videoUrl != null;
    final bgColor = !hasMedia && widget.post.textBgColor != null
        ? Color(widget.post.textBgColor!)
        : null;
    final textAlign = bgColor != null ? TextAlign.center : TextAlign.start;
    final contentLength = widget.post.content.trim().length;
    final baseStyle = bgColor != null
        ? TextStyle(
            fontSize: contentLength < 50
                ? 30
                : contentLength < 100
                    ? 24
                    : 20,
            fontWeight: FontWeight.w800,
            height: 1.25,
          )
        : const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            height: 1.85,
          );
    final bool bgIsLight = bgColor?.computeLuminance() != null &&
        (bgColor!.computeLuminance() > 0.55);
    final textStyle = baseStyle.copyWith(
      color: bgColor != null
          ? (bgIsLight ? Colors.black : Colors.white)
          : theme.colorScheme.onSurface,
      fontWeight: bgColor != null ? FontWeight.w700 : baseStyle.fontWeight,
    );

    final content = TaggableExpandableText(
      text: widget.post.content,
      style: textStyle,
      textAlign: textAlign,
      maxLines: _contentMaxLines(),
      expandLabel: 'more',
      collapseLabel: 'Show less',
      onMentionTap: _handleMentionTap,
      onHashtagTap: _handleHashtagTap,
    );

    if (bgColor == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: content,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: AspectRatio(
            aspectRatio: 1 / 1.2,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [content],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaContent() {
    final urls = (widget.mediaUrls != null && widget.mediaUrls!.isNotEmpty)
        ? widget.mediaUrls!
        : (widget.post.imageUrl != null ? [widget.post.imageUrl!] : <String>[]);
    final postTypeLower = (widget.post.postType ?? '').toLowerCase();
    final isReelPost =
        postTypeLower.contains('reel') || postTypeLower.contains('short');
    final isVideoPost = postTypeLower.contains('video') || isReelPost;
    final aspectRatio = _pickAspectRatio(postTypeLower, isVideoPost);
    const mediaMargin = EdgeInsets.symmetric(horizontal: 16);
    final borderRadius = BorderRadius.circular(16);

    // For video/reel posts with no thumbnail/image, show a video placeholder so
    // users can see it's a video and tap to open details.
    if (urls.isEmpty && isVideoPost && !widget.isDetail) {
      final theme = Theme.of(context);
      final placeholder = Container(
        margin: mediaMargin,
        child: ClipRRect(
          borderRadius: borderRadius,
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Container(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
              child: Center(
                child: Icon(
                  Icons.play_circle_fill,
                  size: widget.isDetail ? 72 : 56,
                  color: theme.colorScheme.onSurface.withOpacity(0.85),
                ),
              ),
            ),
          ),
        ),
      );
      if (widget.onOpenPost == null) return placeholder;
      return InkWell(onTap: widget.onOpenPost, child: placeholder);
    }

    if (urls.isEmpty) return const SizedBox.shrink();

    if (urls.length == 1) {
      // Base cover image
      Widget cover = _signedImage(
        urls.first,
        fit: isVideoPost && !isReelPost ? BoxFit.contain : BoxFit.cover,
        alignment:
            isVideoPost && isReelPost ? Alignment.center : Alignment.topCenter,
        backgroundColor: isVideoPost ? Colors.black : const Color(0xFFF3F4F6),
      );

      // Overlay a centered play icon for videos/reels in feed so users
      // can clearly see it's playable.
      if (isVideoPost && !widget.isDetail) {
        cover = Stack(
          fit: StackFit.expand,
          children: [
            cover,
            if (widget.showReelBadge)
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Reels',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  shape: BoxShape.circle,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.play_arrow, size: 40, color: Colors.white),
                ),
              ),
            ),
            if (isReelPost && (widget.post.title?.trim().isNotEmpty ?? false))
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.52),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TaggableExpandableText(
                    text: widget.post.title!.trim(),
                    maxLines: 2,
                    expandLabel: 'more',
                    collapseLabel: 'Show less',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        );
      }

      final image = Container(
        margin: mediaMargin,
        child: ClipRRect(
          borderRadius: borderRadius,
          child: AspectRatio(aspectRatio: aspectRatio, child: cover),
        ),
      );
      final onTap = _mediaTapHandler(
        urls: urls,
        isVideoPost: isVideoPost,
        isReelPost: isReelPost,
      );
      if (onTap == null) return image;
      return InkWell(onTap: onTap, child: image);
    }
    _pageController ??= PageController();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: mediaMargin,
          child: ClipRRect(
            borderRadius: borderRadius,
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    itemCount: urls.length,
                    onPageChanged: (index) {
                      setState(() => _currentMediaIndex = index);
                      final next = index + 1;
                      if (next < urls.length) {
                        _resolveSigned(urls[next]).then((u) {
                          if (u != null) _precache(u);
                        });
                      }
                    },
                    itemBuilder: (context, index) {
                      final image = _signedImage(
                        urls[index],
                        fit: isVideoPost && !isReelPost
                            ? BoxFit.contain
                            : BoxFit.cover,
                        alignment: isVideoPost && isReelPost
                            ? Alignment.center
                            : Alignment.topCenter,
                        backgroundColor: isVideoPost
                            ? Colors.black
                            : const Color(0xFFF3F4F6),
                      );
                      final onTap = _mediaTapHandler(
                        urls: urls,
                        isVideoPost: isVideoPost,
                        isReelPost: isReelPost,
                      );
                      if (onTap == null) return image;
                      return GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: onTap,
                        child: image,
                      );
                    },
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(urls.length, (index) {
                        final isActive = index == _currentMediaIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          width: isActive ? 24 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: isActive
                                ? Colors.white
                                : Colors.white.withOpacity(0.6),
                          ),
                        );
                      }),
                    ),
                  ),
                  if (widget.showReelBadge)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Reels',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _pickAspectRatio(String postTypeLower, bool isVideoPost) {
    if (isVideoPost && postTypeLower.contains('reel')) {
      return 0.84;
    }
    if (isVideoPost) {
      return 16 / 9;
    }
    return 1 / 1.2;
  }

  VoidCallback? _mediaTapHandler({
    required List<String> urls,
    required bool isVideoPost,
    required bool isReelPost,
  }) {
    if (isVideoPost) {
      return widget.onOpenPost;
    }
    if (urls.isEmpty) {
      return widget.onOpenPost;
    }
    return () => _openImageViewer(urls, initialIndex: _currentMediaIndex);
  }

  Future<void> _openImageViewer(
    List<String> urls, {
    int initialIndex = 0,
  }) async {
    final pageController = PageController(initialPage: initialIndex);
    final startIndex = initialIndex < urls.length ? initialIndex : 0;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Image viewer',
      barrierColor: Colors.black,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        var currentIndex = startIndex;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Scaffold(
              backgroundColor: Colors.black,
              body: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${currentIndex + 1} / ${urls.length}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: pageController,
                        itemCount: urls.length,
                        onPageChanged: (index) {
                          setDialogState(() => currentIndex = index);
                          if (mounted) {
                            setState(() => _currentMediaIndex = index);
                          }
                        },
                        itemBuilder: (context, index) {
                          return InteractiveViewer(
                            minScale: 1,
                            maxScale: 4,
                            child: Center(
                              child: FutureBuilder<String?>(
                                future: _resolveSigned(urls[index]),
                                builder: (context, snap) {
                                  final imgUrl = snap.data;
                                  if (imgUrl == null) {
                                    return Center(
                                      child: CircularProgressIndicator(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                    );
                                  }
                                  if (imgUrl.isEmpty ||
                                      imgUrl.contains('b-cdn.net')) {
                                    return Container(
                                      color: Colors.grey[200],
                                      child: const Center(
                                        child: Icon(
                                          LucideIcons.imageOff,
                                          size: 40,
                                          color: Color(0xFF9CA3AF),
                                        ),
                                      ),
                                    );
                                  }
                                  return CachedNetworkImage(
                                    imageUrl: imgUrl,
                                    fit: BoxFit.contain,
                                    placeholder: (c, s) => Center(
                                      child: CircularProgressIndicator(
                                        color:
                                            Theme.of(c).colorScheme.primary,
                                      ),
                                    ),
                                    errorWidget: (c, s, e) => const Icon(
                                      LucideIcons.imageOff,
                                      size: 40,
                                      color: Color(0xFF9CA3AF),
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    pageController.dispose();
  }

  Widget _signedImage(
    String url, {
    BoxFit fit = BoxFit.cover,
    Alignment alignment = Alignment.center,
    Color backgroundColor = const Color(0xFFF3F4F6),
  }) {
    // Bunny CDN pull zone is suspended, and empty URLs should fail-fast
    // to avoid slow failures and console noise. Fall back to placeholder.
    if (url.isEmpty || url.contains('b-cdn.net')) {
      return Container(
        color: backgroundColor,
        child: const Center(
          child: Icon(
            LucideIcons.imageOff,
            size: 40,
            color: Color(0xFF9CA3AF),
          ),
        ),
      );
    }

    final cached = _signedCache[url] ?? _resolvedMediaUrlCache[url];
    if (cached != null && cached.isNotEmpty) {
      return _buildResolvedImage(
        cached,
        fit: fit,
        alignment: alignment,
        backgroundColor: backgroundColor,
      );
    }

    // Appwrite Storage URLs do not need signing and can be resolved synchronously!
    if (url.contains('cloud.appwrite.io')) {
      _signedCache[url] = url;
      _resolvedMediaUrlCache[url] = url;
      return _buildResolvedImage(
        url,
        fit: fit,
        alignment: alignment,
        backgroundColor: backgroundColor,
      );
    }

    // Trigger background signed URL resolution, and call setState when done.
    _resolveSigned(url).then((resolved) {
      if (resolved != null && resolved.isNotEmpty && mounted) {
        setState(() {});
      }
    });

    return Container(color: backgroundColor);
  }

  Widget _buildResolvedImage(
    String imgUrl, {
    required BoxFit fit,
    required Alignment alignment,
    required Color backgroundColor,
  }) {
    return CachedNetworkImage(
      imageUrl: imgUrl,
      width: double.infinity,
      fit: fit,
      alignment: alignment,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      placeholder: (c, s) => Container(color: backgroundColor),
      errorWidget: (c, s, e) => Container(
        color: backgroundColor,
        child: const Center(
          child: Icon(
            LucideIcons.imageOff,
            size: 40,
            color: Color(0xFF9CA3AF),
          ),
        ),
      ),
    );
  }

  Future<String?> _resolveSigned(String url) async {
    if (_signedCache.containsKey(url)) return _signedCache[url]!;
    if (_resolvedMediaUrlCache.containsKey(url)) {
      final cached = _resolvedMediaUrlCache[url];
      if (cached != null) {
        _signedCache[url] = cached;
      }
      return cached;
    }

    // If this is an Appwrite Storage URL, return it as-is (no Wasabi signing).
    if (url.contains('cloud.appwrite.io')) {
      _signedCache[url] = url;
      _resolvedMediaUrlCache[url] = url;
      return url;
    }

    // Legacy Wasabi media: support both raw keys and full signed URLs.
    String key = url;
    if (url.contains('://')) {
      try {
        final uri = Uri.parse(url);
        // S3/Wasabi path-style URL: /bucket/key...
        if (uri.host.contains('wasabisys.com') &&
            uri.pathSegments.length >= 2) {
          key = uri.pathSegments.skip(1).join('/');
        }
      } catch (_) {
        key = url;
      }
    }

    final signed = await StorageService.getSignedUrl(key);
    _signedCache[url] = signed;
    _resolvedMediaUrlCache[url] = signed;
    return signed;
  }

  Widget _buildVideoMeta() {
    final theme = Theme.of(context);
    final postTypeLower = (widget.post.postType ?? '').toLowerCase();
    final isReelPost =
        postTypeLower.contains('reel') || postTypeLower.contains('short');
    final title = widget.post.title?.trim();
    final content = widget.post.content.trim();
    if ((title == null || title.isEmpty) && content.isEmpty) {
      return const SizedBox.shrink();
    }
    const baseStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.w500);

    if (!widget.isDetail) {
      final feedText = (title != null && title.isNotEmpty)
          ? title
          : (isReelPost ? content : null);
      if (feedText == null || feedText.isEmpty) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpenPost,
          child: TaggableExpandableText(
            text: feedText,
            maxLines: 2,
            expandLabel: 'more',
            collapseLabel: 'Show less',
            style: baseStyle.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null && title.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onOpenPost,
              child: TaggableExpandableText(
                text: title,
                maxLines: 2,
                expandLabel: 'more',
                collapseLabel: 'Show less',
                style: baseStyle.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          if (content.isNotEmpty && widget.showVideoDescription) ...[
            const SizedBox(height: 4),
            if (widget.videoDescriptionMaxLines != null &&
                widget.onVideoDescriptionTap != null)
              _buildVideoDescriptionPreview(
                content,
                theme,
                widget.videoDescriptionMaxLines!,
                widget.onVideoDescriptionTap!,
              )
            else
              _ExpandableText(
                text: content,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                ).copyWith(color: theme.colorScheme.onSurface),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoDescriptionPreview(
    String description,
    ThemeData theme,
    int maxLines,
    VoidCallback onTap,
  ) {
    final baseStyle = TextStyle(
      fontSize: 15,
      height: 1.4,
      color: theme.colorScheme.onSurface,
    );
    const maxChars = 120;
    var snippet = description.trim();
    var truncated = false;
    if (snippet.length > maxChars) {
      snippet = snippet.substring(0, maxChars);
      truncated = true;
    }
    return GestureDetector(
      onTap: onTap,
      child: RichText(
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: baseStyle,
          children: buildTaggableSpans(
            context,
            truncated ? '$snippet...' : snippet,
            baseStyle,
            _handleMentionTap,
            _handleHashtagTap,
          ),
        ),
      ),
    );
  }

  void _precache(String url) {
    if (mounted) {
      precacheImage(CachedNetworkImageProvider(url), context);
    }
  }

  Widget _buildActions() {
    final theme = Theme.of(context);
    final iconDefault =
        theme.iconTheme.color ?? theme.colorScheme.onSurfaceVariant;
    final countColor = theme.colorScheme.onSurfaceVariant;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildIconOnlyAction(
            LucideIcons.bookmark,
            _isSaved ? _savedColor : iconDefault,
            _toggleSave,
          ),
          _buildShareAction(),
          _buildActionButton(
            LucideIcons.repeat2,
            _repostCount,
            _hasReposted ? const Color(0xFF1DA1F2) : iconDefault,
            _repostPost,
            countColor,
          ),
          _buildActionButton(
            LucideIcons.barChart2,
            widget.showViewsLabel ? widget.post.views : _impressionCount,
            iconDefault,
            () {},
            countColor,
          ),
          _buildActionButton(
            LucideIcons.messageCircle,
            _commentCount,
            iconDefault,
            _openComments,
            countColor,
          ),
          _buildLikeAction(),
        ],
      ),
    );
  }

  Widget _buildIconOnlyAction(
    IconData icon,
    Color? color,
    VoidCallback onPressed,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    int? count,
    Color? color,
    VoidCallback onPressed, [
    Color? countColor,
    String? label,
  ]) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: Icon(icon, color: color, size: 24),
          ),
          if (count != null)
            Row(
              children: [
                _AnimatedCount(value: count, color: countColor),
                if (label != null) ...[
                  const SizedBox(width: 1),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: countColor ?? Colors.grey,
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildShareAction() {
    final theme = Theme.of(context);
    final iconDefault =
        theme.iconTheme.color ?? theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _shareCount++;
          });
          AppwriteService.incrementPostShares(widget.post.id, 1);
          _sharePost();
        },
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.rotationY(math.pi),
          child: Icon(Icons.reply, color: iconDefault, size: 24),
        ),
      ),
    );
  }

  Widget _buildLikeAction() {
    final theme = Theme.of(context);
    final activeColor = const Color(0xFFFF2D55); // vibrant pink/red
    final inactiveColor =
        theme.iconTheme.color ?? theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleLike,
            child: Icon(
              _isLiked ? Icons.favorite : Icons.favorite_border,
              color: _isLiked ? activeColor : inactiveColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 0),
          _AnimatedCount(
            value: _likeCount,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFollow() async {
    if (widget.isGuest || widget.authorId == null || _currentUserId == null) {
      return;
    }
    final targetFollow = !_isFollowing;
    setState(() => _isFollowing = targetFollow);
    try {
      if (targetFollow) {
        await AppwriteService.followUser(widget.authorId!);
      } else {
        await AppwriteService.unfollowUser(widget.authorId!);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isFollowing = !targetFollow);
      }
    }
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
      _likeCache[widget.post.id] = _isLiked;
    });
    try {
      if (targetLike) {
        await AppwriteService.likePost(widget.post.id);
      } else {
        await AppwriteService.unlikePost(widget.post.id);
      }
    } catch (_) {
      // Revert UI if the backend update fails.
      if (!mounted) return;
      setState(() {
        _isLiked = !targetLike;
        _likeCount = previousCount;
        _likeCache[widget.post.id] = _isLiked;
      });
    }
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
      await AppwriteService.repostPost(widget.post.id);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(targetRepost ? 'Post reposted' : 'Repost removed'),
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
        await AppwriteService.savePost(widget.post.id);
      } else {
        await AppwriteService.unsavePost(widget.post.id);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaved = !targetSave);
      }
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

  void _sharePost() {
    ShareUtils.sharePost(
      postId: widget.post.id,
      username: widget.post.username,
      content: widget.post.content,
    );
  }

  Future<void> _handleMentionTap(String username) async {
    final handle = username.replaceAll('@', '').trim();
    if (handle.isEmpty) return;
    final prof = await AppwriteService.getProfileByUsername(handle);
    if (!mounted) return;
    if (prof == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('User @$handle not found')));
      return;
    }
    final data = prof.data;
    final userId = data['userId'] as String? ?? prof.$id;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => ProfileScreen(userId: userId)),
    );
  }

  void _handleHashtagTap(String tag) {
    final clean = tag.replaceAll('#', '').trim();
    if (clean.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => HashtagFeedScreen(tag: clean)),
    );
  }

  void _showReportMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (bcontext) {
        final theme = Theme.of(bcontext);
        final isOwner = _currentUserId != null &&
            widget.authorId != null &&
            widget.authorId == _currentUserId;
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
                if (isOwner)
                  _buildMenuTile(
                    context: bcontext,
                    icon: LucideIcons.edit3,
                    label: 'Edit post',
                    onTap: () async {
                      Navigator.of(bcontext).pop();
                      await _openEditPost();
                    },
                  ),
                if (isOwner)
                  _buildMenuTile(
                    context: bcontext,
                    icon: LucideIcons.zap,
                    label: 'Promote with ads',
                    onTap: () async {
                      Navigator.of(bcontext).pop();
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BoostPostScreen(post: widget.post),
                        ),
                      );
                    },
                  ),
                if (isOwner && widget.post.sourcePostId == null)
                  _buildMenuTile(
                    context: bcontext,
                    icon: LucideIcons.trash2,
                    label: 'Delete post',
                    destructive: true,
                    onTap: () async {
                      Navigator.of(bcontext).pop();
                      final messenger = ScaffoldMessenger.of(context);
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete post'),
                          content: const Text(
                            'Are you sure you want to delete this post?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text(
                                'Delete',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                      try {
                        await AppwriteService.deletePost(widget.post.id);
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Post deleted')),
                        );
                        widget.onDeleted?.call();
                      } catch (_) {
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(
                              content: Text('Failed to delete post')),
                        );
                      }
                    },
                  ),
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
                  label: 'Report post',
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
        title: const Text('Report Post'),
        content: const Text('Are you sure you want to report this post?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dcontext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(dcontext);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              try {
                await AppwriteService.reportPost(
                  widget.post.id,
                  'Inappropriate content',
                );
                if (!mounted) return;
                navigator.pop();
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('Post reported.')),
                );
              } catch (e) {
                if (!mounted) return;
                navigator.pop();
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('Failed to report post.')),
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
            content: Text('This post does not have a blockable author.')),
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
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              try {
                await AppwriteService.blockUser(targetUserId);
                if (!mounted) return;
                navigator.pop();
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('User blocked.')),
                );
              } catch (e) {
                if (!mounted) return;
                navigator.pop();
                scaffoldMessenger.showSnackBar(
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

  String _truncateDisplayName(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= _displayNameCharacterLimit) {
      return trimmed;
    }
    return '${trimmed.substring(0, _displayNameCharacterLimit)}...';
  }
}

class _AnimatedCount extends StatelessWidget {
  final int value;
  final Color? color;

  const _AnimatedCount({required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatCompactCount(value),
      style: TextStyle(color: color ?? Colors.grey[700], fontSize: 14),
    );
  }
}

String _formatCompactCount(int value) {
  final absValue = value.abs();
  if (absValue >= 1000000000) {
    final formatted = (value / 1000000000).toStringAsFixed(
      absValue >= 10000000000 ? 0 : 1,
    );
    return '${_trimTrailingZero(formatted)}b';
  }
  if (absValue >= 1000000) {
    final formatted = (value / 1000000).toStringAsFixed(
      absValue >= 10000000 ? 0 : 1,
    );
    return '${_trimTrailingZero(formatted)}m';
  }
  if (absValue >= 1000) {
    final formatted = (value / 1000).toStringAsFixed(
      absValue >= 10000 ? 0 : 1,
    );
    return '${_trimTrailingZero(formatted)}k';
  }
  return value.toString();
}

String _trimTrailingZero(String value) {
  return value.endsWith('.0') ? value.substring(0, value.length - 2) : value;
}

class _ExpandableText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _ExpandableText({required this.text, required this.style});

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final span = TextSpan(text: widget.text, style: widget.style);
        final tp = TextPainter(
          text: span,
          maxLines: 3,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflow = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: widget.style,
              maxLines: _expanded ? null : 3,
              overflow:
                  _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            if (overflow)
              GestureDetector(
                onTap: () {
                  setState(() => _expanded = !_expanded);
                },
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _expanded ? 'See less' : 'See more',
                    style: TextStyle(
                      color: const Color(0xFF1DA1F2),
                      fontSize: (widget.style.fontSize ?? 16) * 0.85,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

String _formatTimestamp(DateTime timestamp) {
  // Always measure from local time and clamp negative differences to zero,
  // so the counter never counts backwards when clocks/timezones differ.
  final now = DateTime.now();
  Duration diff = now.difference(timestamp.toLocal());

  if (diff.isNegative) {
    diff = Duration.zero;
  }

  if (diff.inSeconds < 60) {
    final s = diff.inSeconds;
    return '${s}s';
  }
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return '${m}m';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return '${h}h';
  }
  if (diff.inDays < 30) {
    final d = diff.inDays;
    return '${d}d';
  }

  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final day = timestamp.day;
  final month = months[timestamp.month - 1];

  if (timestamp.year == now.year) {
    // Same year, older than ~1 month: "5 Nov"
    return '$day $month';
  } else {
    // Different year: "5 Nov 2025"
    final year = timestamp.year;
    return '$day $month $year';
  }
}
