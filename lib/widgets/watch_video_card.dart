import 'package:flutter/material.dart';
import '../models/post.dart';
import '../utils/format_utils.dart';
import '../services/appwrite_service.dart';
import '../services/global_video_manager.dart';
import '../services/storage_service.dart';
import '../screens/profile_screen.dart';
import '../screens/reel_detail_screen.dart';
import '../screens/video_detail_screen.dart';

class WatchVideoCard extends StatefulWidget {
  final Post post;
  final List<String>? mediaUrls;
  final bool isGuest;
  final VoidCallback? onGuestAction;
  final String? authorId;
  final bool enableAds;

  const WatchVideoCard({
    super.key,
    required this.post,
    this.mediaUrls,
    this.isGuest = false,
    this.onGuestAction,
    this.authorId,
    this.enableAds = true,
  });

  @override
  State<WatchVideoCard> createState() => _WatchVideoCardState();
}

class _WatchVideoCardState extends State<WatchVideoCard> {
  static const int _displayNameCharacterLimit = 13;
  String _displayName = '';
  String? _resolvedAvatarUrl;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    if (widget.post.userAvatar.isNotEmpty) {
      _resolvedAvatarUrl = _resolveAvatarUrlSync(widget.post.userAvatar);
    }
    _loadAuthorProfile();
    _loadCurrentUser();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final thumb = (widget.mediaUrls != null && widget.mediaUrls!.isNotEmpty)
        ? widget.mediaUrls!.first
        : widget.post.thumbnailUrl;
    final displayName =
        _displayName.isNotEmpty ? _truncateDisplayName(_displayName) : '';
    final views = widget.post.views;
    final gapColor = isDark ? Colors.black : Colors.black.withOpacity(0.03);

    return Container(
      color: gapColor,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: _openDetail,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor, width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildThumbnailArea(theme, thumb),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: _openAuthorProfile,
                      child: _buildAvatar(theme),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: _openAuthorProfile,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (displayName.isNotEmpty)
                              Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            SizedBox(height: displayName.isNotEmpty ? 4 : 0),
                            Row(
                              children: [
                                Icon(
                                  Icons.visibility_outlined,
                                  size: 16,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  formatCompactCount(views),
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _formatTimestamp(widget.post.timestamp),
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.more_vert,
                        color: theme.iconTheme.color,
                      ),
                      onPressed: _showReportMenu,
                    ),
                  ],
                ),
              ),
              if (widget.post.title?.trim().isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text(
                    widget.post.title!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadAuthorProfile() async {
    final authorId = widget.authorId?.trim();
    if (authorId == null || authorId.isEmpty) {
      final fallbackAvatar = _resolveAvatarUrlSync(widget.post.userAvatar);
      if (!mounted) return;
      setState(() {
        _displayName = '';
        _resolvedAvatarUrl = fallbackAvatar;
      });
      return;
    }

    final cached = AppwriteService.getCachedProfileByUserId(authorId);
    if (cached != null) {
      final displayName = (cached.data['displayName'] as String?)?.trim();
      final avatar = _resolveAvatarUrlSync(
        ((cached.data['avatarUrl'] as String?)?.trim().isNotEmpty == true)
            ? (cached.data['avatarUrl'] as String)
            : widget.post.userAvatar,
      );
      _displayName = displayName?.isNotEmpty == true ? displayName! : '';
      _resolvedAvatarUrl = avatar;
      return;
    }

    try {
      final profile = await AppwriteService.getProfileByUserId(authorId);
      final displayName = (profile?.data['displayName'] as String?)?.trim();
      final avatar = _resolveAvatarUrlSync(
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
      final fallbackAvatar = _resolveAvatarUrlSync(widget.post.userAvatar);
      if (!mounted) return;
      setState(() {
        _displayName = '';
        _resolvedAvatarUrl = fallbackAvatar;
      });
    }
  }

  Future<void> _loadCurrentUser() async {
    final user = await AppwriteService.getCurrentUser();
    if (!mounted) return;
    setState(() {
      _currentUserId = user?.$id;
    });
  }

  String? _resolveAvatarUrlSync(String? rawAvatar) {
    final avatar = rawAvatar?.trim();
    if (avatar == null || avatar.isEmpty) {
      return null;
    }
    if (avatar.startsWith('http')) {
      return avatar;
    }
    try {
      return StorageService.getImageDisplayUrlSync(avatar);
    } catch (_) {
      return null;
    }
  }

  Widget _buildAvatar(ThemeData theme) {
    final avatar = _resolvedAvatarUrl?.trim();
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      child: ClipOval(
        child: avatar == null || avatar.isEmpty
            ? Icon(
                Icons.person,
                size: 22,
                color: theme.colorScheme.onSurfaceVariant,
              )
            : Image.network(
                avatar,
                fit: BoxFit.cover,
                width: 40,
                height: 40,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.person,
                  size: 22,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }

  Widget _buildThumbnailArea(ThemeData theme, String? thumb) {
    final aspect = 16 / 9;
    final image = thumb != null && thumb.isNotEmpty
        ? Image.network(
            thumb,
            fit: BoxFit.cover,
            width: double.infinity,
          )
        : Container(
            color: theme.colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: const Icon(Icons.play_circle_fill, size: 56),
          );
    return AspectRatio(
      aspectRatio: aspect,
      child: Stack(
        fit: StackFit.expand,
        children: [
          image,
          Container(color: Colors.black.withOpacity(0.08)),
          Center(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(14),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 42),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDetail() async {
    final postType = (widget.post.postType ?? '').toLowerCase();
    final isReel = postType.contains('reel') || postType.contains('short');
    if (!isReel) {
      await GlobalVideoManager.releaseActive();
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => isReel
            ? ReelDetailScreen(
                post: widget.post,
                authorId: widget.authorId,
                isGuest: widget.isGuest,
                onGuestAction: widget.onGuestAction,
                initialResolvedVideoUrl: widget.post.previewVideoUrl ??
                    widget.post.videoUrl ??
                    widget.post.hlsVideoUrl,
                initialAuthorName: widget.post.username,
                initialAuthorAvatarUrl: widget.post.userAvatar,
              )
            : VideoDetailScreen(
                post: widget.post,
                mediaUrls: widget.mediaUrls,
                authorId: widget.authorId,
                isGuest: widget.isGuest,
                onGuestAction: widget.onGuestAction,
                autoPlay: true,
              ),
      ),
    );
  }

  void _openAuthorProfile() {
    final authorId = widget.authorId?.trim();
    if (authorId == null || authorId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: authorId),
      ),
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
                if (widget.authorId != null &&
                    widget.authorId != _currentUserId)
                  _buildMenuTile(
                    context: bcontext,
                    icon: Icons.block_outlined,
                    label: 'Block user',
                    destructive: true,
                    onTap: () {
                      Navigator.of(bcontext).pop();
                      _showBlockConfirmation();
                    },
                  ),
                _buildMenuTile(
                  context: bcontext,
                  icon: Icons.flag_outlined,
                  label: 'Report video',
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
        title: const Text('Report Video'),
        content: const Text('Are you sure you want to report this video?'),
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
                await AppwriteService.reportPost(
                  widget.post.id,
                  'Inappropriate content',
                );
                if (!mounted) return;
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Video reported.')),
                );
              } catch (_) {
                if (!mounted) return;
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Failed to report video.')),
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
          content: Text('This video does not have a blockable author.'),
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
                await AppwriteService.blockUser(targetUserId);
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



  String _truncateDisplayName(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= _displayNameCharacterLimit) {
      return trimmed;
    }
    return '${trimmed.substring(0, _displayNameCharacterLimit)}...';
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    if (difference.inMinutes < 1) return 'now';
    if (difference.inHours < 1) return '${difference.inMinutes}m';
    if (difference.inDays < 1) return '${difference.inHours}h';
    if (difference.inDays < 7) return '${difference.inDays}d';
    if (difference.inDays < 30) return '${(difference.inDays / 7).floor()}w';
    if (difference.inDays < 365) {
      return '${(difference.inDays / 30).floor()}mo';
    }
    return '${(difference.inDays / 365).floor()}y';
  }
}

