import 'dart:async';


import 'package:xapzap/models/database_models.dart' as aw;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/post.dart';
import '../screens/hashtag_feed_screen.dart';
import '../screens/profile_screen.dart';
import '../services/backend_service.dart';
import '../services/storage_service.dart';
import '../widgets/taggable_text.dart';
import '../widgets/tv_focusable_action.dart';
import '../widgets/voice_note_player.dart';
import '../widgets/verification_badge.dart';

enum CommentScreenMode {
  preview,
  fullScreen,
}

Future<void> showCommentModal(
  BuildContext context, {
  required Post post,
  bool isGuest = false,
  VoidCallback? onGuestAction,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    barrierColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.6,
      child: CommentScreen(
        post: post,
        isGuest: isGuest,
        onGuestAction: onGuestAction,
        mode: CommentScreenMode.preview,
      ),
    ),
  );
}

class CommentScreen extends StatefulWidget {
  final Post post;
  final bool isGuest;
  final VoidCallback? onGuestAction;
  final CommentScreenMode mode;
  final aw.Row? parentComment;

  const CommentScreen({
    super.key,
    required this.post,
    this.isGuest = false,
    this.onGuestAction,
    this.mode = CommentScreenMode.fullScreen,
    this.parentComment,
  });

  @override
  State<CommentScreen> createState() => _CommentScreenState();
}

class _CommentScreenState extends State<CommentScreen> {
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  bool _loading = true;
  bool _isSubmitting = false;
  String? _currentUserId;
  String? _currentUserAvatarUrl;
  String? _replyToCommentId;
  RealtimeSubscription? _commentsSub;
  RealtimeSubscription? _commentLikesSub;

  final Set<String> _likedCommentIds = <String>{};
  final Map<String, List<aw.Row>> _repliesByParent = <String, List<aw.Row>>{};
  final List<aw.Row> _rootComments = <aw.Row>[];
  static final Map<String, bool> _commenterVerifiedCache = {};
  static final Map<String, bool> _commenterAdminCache = {};

  bool get _isPreview => widget.mode == CommentScreenMode.preview;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadComments();
    _subscribeComments();
  }

  @override
  void dispose() {
    _commentsSub?.close();
    _commentLikesSub?.close();
    _commentController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _subscribeComments() {
    final channel =
        'databases.${BackendService.databaseId}.collections.${BackendService.commentsCollectionId}.documents';
    _commentsSub?.close();
    _commentsSub = BackendService.realtime.subscribe([channel]);
    _commentsSub?.stream.listen((event) {
      final payload = event.payload;
      final data = payload['data'];
      if (data is! Map<String, dynamic>) return;
      final postId = (data['postId'] as String?)?.trim();
      if (postId != widget.post.id) return;
      unawaited(_loadComments());
    });

    final likesChannel =
        'databases.${BackendService.databaseId}.collections.${BackendService.commentLikesCollectionId}.documents';
    _commentLikesSub?.close();
    _commentLikesSub = BackendService.realtime.subscribe([likesChannel]);
    _commentLikesSub?.stream.listen((event) {
      final payload = event.payload;
      final data = payload['data'];
      if (data is! Map<String, dynamic>) return;
      final commentId = (data['commentId'] as String?)?.trim();
      if (commentId == null || commentId.isEmpty) return;
      if (_rootComments.any((row) => row.$id == commentId) ||
          _repliesByParent.values
              .expand((rows) => rows)
              .any((row) => row.$id == commentId)) {
        unawaited(_syncLikedCommentIds());
      }
    });
  }

  Future<void> _loadCurrentUser() async {
    final user = await BackendService.getCurrentUser();
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _currentUserId = null;
        _currentUserAvatarUrl = null;
      });
      return;
    }

    final prof = await BackendService.getProfileByUserId(user.$id);
    String? avatar = prof?.data['avatarUrl'] as String?;
    if (avatar != null && avatar.isNotEmpty && !avatar.startsWith('http')) {
      try {
        avatar = await StorageService.getSignedUrl(avatar);
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _currentUserId = user.$id;
      _currentUserAvatarUrl = avatar;
    });
    await _syncLikedCommentIds();
  }

  Future<void> _loadComments() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    try {
      final docs = await BackendService.fetchComments(widget.post.id);
      if (!mounted) return;

      _rootComments.clear();
      _repliesByParent.clear();

      for (final row in docs.rows) {
        final parentId = row.data['parentCommentId'] as String?;
        if (parentId == null || parentId.isEmpty) {
          _rootComments.add(row);
        } else {
          _repliesByParent.putIfAbsent(parentId, () => <aw.Row>[]).add(row);
        }
      }
      if (_currentUserId != null) {
        await _syncLikedCommentIds();
      }

      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _syncLikedCommentIds() async {
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) return;
    final commentIds = <String>[
      ..._rootComments.map((row) => row.$id),
      ..._repliesByParent.values.expand((rows) => rows.map((row) => row.$id)),
    ];
    final likedIds = await BackendService.fetchLikedCommentIds(
      userId,
      commentIds: commentIds,
    );
    if (!mounted) return;
    setState(() {
      _likedCommentIds
        ..clear()
        ..addAll(likedIds);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isPreview) {
      return _buildSheetContent(context);
    }
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.parentComment == null ? 'Comments' : 'Replies'),
        centerTitle: true,
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildSheetContent(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Comments',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _openFullScreen,
                    child: const Text('View all comments'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Column(
      children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildCommentList(context),
        ),
        AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: bottomInset),
          child: _buildInput(context),
        ),
      ],
    );
  }

  Widget _buildCommentList(BuildContext context) {
    final comments = _visibleComments();
    final parentComment = widget.parentComment;

    if (comments.isEmpty) {
      return Center(
        child: Text(
          parentComment == null ? 'No comments yet' : 'No replies yet',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 15,
          ),
        ),
      );
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      children: [
        if (parentComment != null) ...[
          _buildCommentItem(parentComment, isParentPreview: true),
          const SizedBox(height: 12),
        ],
        for (final doc in comments) ...[
          _buildCommentItem(doc),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  List<aw.Row> _visibleComments() {
    final parentComment = widget.parentComment;
    if (parentComment != null) {
      return List<aw.Row>.from(
          _repliesByParent[parentComment.$id] ?? const <aw.Row>[]);
    }

    if (_isPreview) {
      return _rootComments.take(3).toList();
    }
    return List<aw.Row>.from(_rootComments);
  }

  Widget _buildCommentItem(
    aw.Row doc, {
    bool isParentPreview = false,
  }) {
    final d = doc.data;
    final id = doc.$id;
    final avatarRaw = (d['userAvatar'] as String?) ?? '';
    final displayName = (d['displayName'] as String?)?.trim() ?? '';
    final userId = (d['userId'] as String?)?.trim() ?? '';
    bool isVerified = false;
    bool isAdmin = false;
    if (userId.isNotEmpty) {
      if (_commenterVerifiedCache.containsKey(userId)) {
        isVerified = _commenterVerifiedCache[userId]!;
        isAdmin = _commenterAdminCache[userId]!;
      } else {
        unawaited(() async {
          try {
            final prof = await BackendService.getProfileByUserId(userId);
            if (prof != null) {
              final v =
                  prof.data['isVerified'] == true || prof.data['verified'] == true;
              final a = prof.data['isAdmin'] == true;
              _commenterVerifiedCache[userId] = v;
              _commenterAdminCache[userId] = a;
              if (mounted) setState(() {});
            }
          } catch (_) {}
        }());
      }
    }
    final createdAt =
        d['createdAt'] ?? d['timestamp'] ?? DateTime.now().toIso8601String();
    DateTime timestamp;
    try {
      timestamp = DateTime.parse(createdAt.toString());
    } catch (_) {
      timestamp = DateTime.now();
    }
    final likesRaw = d['likes'];
    final repliesRaw = d['replies'];
    final likes = likesRaw is int ? likesRaw : int.tryParse('$likesRaw') ?? 0;
    final replies =
        repliesRaw is int ? repliesRaw : int.tryParse('$repliesRaw') ?? 0;
    final isLiked = _likedCommentIds.contains(id);
    final voiceUrl = (d['voiceUrl'] as String?)?.trim();
    final content = (d['content'] as String?)?.trim() ?? '';
    final theme = Theme.of(context);
    final bubbleColor = theme.brightness == Brightness.dark
        ? theme.colorScheme.primary.withOpacity(0.16)
        : const Color(0xFFF3F4F6);

    return TvFocusableAction(
      onLongPress: isParentPreview ? null : () => _onCommentLongPress(doc),
      onTvPressed: isParentPreview ? null : () => _onCommentLongPress(doc),
      borderRadius: BorderRadius.circular(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Builder(
            builder: (context) {
              final url = StorageService.getImageDisplayUrlSync(avatarRaw);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openCommentOwnerProfile(doc),
                child: url.isEmpty
                    ? CircleAvatar(
                        radius: 20,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.person,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : CircleAvatar(
                        radius: 20,
                        backgroundImage: NetworkImage(url),
                      ),
              );
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          TvFocusableAction(
                            onPressed: () => _openCommentOwnerProfile(doc),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: Color(0xFF1DA1F2),
                                  ),
                                ),
                                if (isVerified || isAdmin) ...[
                                  const SizedBox(width: 4),
                                  VerificationBadge(
                                    size: 13,
                                    isPremium: isAdmin,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatTimeAgo(timestamp),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (voiceUrl != null && voiceUrl.isNotEmpty)
                        VoiceNotePlayer(url: voiceUrl)
                      else
                        TaggableExpandableText(
                          text: content,
                          style: TextStyle(
                            fontSize: 15,
                            color: theme.colorScheme.onSurface,
                            height: 1.45,
                          ),
                          onMentionTap: _handleMentionTap,
                          onHashtagTap: _handleHashtagTap,
                        ),
                    ],
                  ),
                ),
                if (!isParentPreview) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      TvFocusableAction(
                        onPressed: () => _toggleLike(doc),
                        child: Text(
                          likes > 0 ? 'Like $likes' : 'Like',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isLiked
                                ? const Color(0xFF1DA1F2)
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      TvFocusableAction(
                        onPressed: () => _startReply(doc),
                        child: Text(
                          'Reply',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (replies > 0 && widget.parentComment == null)
                        TvFocusableAction(
                          onPressed: () => _openReplyThread(doc),
                          child: Text(
                            'View $replies ${replies == 1 ? 'reply' : 'replies'}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1DA1F2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    final theme = Theme.of(context);
    final inputFillColor = theme.brightness == Brightness.dark
        ? const Color(0xFF111827)
        : Colors.grey[100];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyToCommentId != null || widget.parentComment != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _replyToCommentId != null ||
                                widget.parentComment != null
                            ? 'Replying to a comment'
                            : '',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _replyToCommentId = null;
                          _commentController.clear();
                        });
                      },
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  backgroundImage: _currentUserAvatarUrl != null &&
                          _currentUserAvatarUrl!.isNotEmpty
                      ? NetworkImage(_currentUserAvatarUrl!)
                      : null,
                  child: (_currentUserAvatarUrl == null ||
                          _currentUserAvatarUrl!.isEmpty)
                      ? Icon(
                          Icons.person,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    focusNode: _inputFocusNode,
                    enabled: !_isSubmitting,
                    decoration: InputDecoration(
                      hintText: widget.parentComment != null ||
                              _replyToCommentId != null
                          ? 'Write a reply...'
                          : 'Add a comment...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: inputFillColor,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: _submitComment,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => _submitComment(_commentController.text),
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  child: Text(_isSubmitting ? 'Posting' : 'Post'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitComment(String text) async {
    final content = text.trim();
    if (content.isEmpty || _isSubmitting) return;
    if (widget.isGuest) {
      widget.onGuestAction?.call();
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final parentId = widget.parentComment?.$id ?? _replyToCommentId;
      final aw.Row doc;
      if (parentId != null && parentId.isNotEmpty) {
        doc = await BackendService.createReplyComment(
          widget.post.id,
          parentId,
          content,
        );
        unawaited(BackendService.incrementCommentReplies(parentId, 1));
      } else {
        doc = await BackendService.createComment(widget.post.id, content);
      }

      unawaited(BackendService.incrementPostComments(widget.post.id, 1));

      if (!mounted) return;
      setState(() {
        if (parentId != null && parentId.isNotEmpty) {
          _repliesByParent
              .putIfAbsent(parentId, () => <aw.Row>[])
              .insert(0, doc);
          if (widget.parentComment == null) {
            final parentIndex =
                _rootComments.indexWhere((row) => row.$id == parentId);
            if (parentIndex != -1) {
              final parentData = _rootComments[parentIndex].data;
              final rawReplies = parentData['replies'];
              final currentReplies = rawReplies is int
                  ? rawReplies
                  : int.tryParse('$rawReplies') ?? 0;
              parentData['replies'] = currentReplies + 1;
            }
          }
        } else {
          _rootComments.insert(0, doc);
        }
        _commentController.clear();
        _replyToCommentId = null;
        _isSubmitting = false;
      });

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_commentErrorMessage(e))),
      );
    }
  }

  void _startReply(aw.Row doc) {
    final displayName = (doc.data['displayName'] as String?)?.trim() ?? '';
    setState(() {
      _replyToCommentId = widget.parentComment?.$id ?? doc.$id;
      _commentController.text = displayName.isNotEmpty ? '@$displayName ' : '';
      _commentController.selection = TextSelection.fromPosition(
        TextPosition(offset: _commentController.text.length),
      );
    });
    _inputFocusNode.requestFocus();
  }

  void _openFullScreen() {
    final navigator = Navigator.of(context, rootNavigator: true);
    if (_isPreview) {
      Navigator.of(context).pop();
    }
    unawaited(
      navigator.push(
        MaterialPageRoute(
          builder: (_) => CommentScreen(
            post: widget.post,
            isGuest: widget.isGuest,
            onGuestAction: widget.onGuestAction,
            mode: CommentScreenMode.fullScreen,
          ),
        ),
      ),
    );
  }

  void _openReplyThread(aw.Row doc) {
    final navigator = Navigator.of(context, rootNavigator: true);
    if (_isPreview) {
      Navigator.of(context).pop();
    }
    unawaited(
      navigator.push(
        MaterialPageRoute(
          builder: (_) => CommentScreen(
            post: widget.post,
            isGuest: widget.isGuest,
            onGuestAction: widget.onGuestAction,
            mode: CommentScreenMode.fullScreen,
            parentComment: doc,
          ),
        ),
      ),
    );
  }

  Future<void> _toggleLike(aw.Row doc) async {
    if (widget.isGuest) {
      widget.onGuestAction?.call();
      return;
    }
    if (_currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to like comments.')),
      );
      return;
    }

    final commentId = doc.$id;
    final isLiked = _likedCommentIds.contains(commentId);

    try {
      if (isLiked) {
        await BackendService.unlikeComment(commentId);
      } else {
        await BackendService.likeComment(commentId);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update like: $e')),
      );
    }
  }

  String _commentErrorMessage(Object error) {
    if (kDebugMode) {
      return 'Failed to post comment: $error';
    }
    return 'Failed to post comment. Please try again.';
  }

  Future<void> _onCommentLongPress(aw.Row doc) async {
    final ownerId = doc.data['userId'] as String?;
    if (_currentUserId == null || ownerId != _currentUserId) {
      return;
    }

    final voiceUrl = (doc.data['voiceUrl'] as String?)?.trim();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (voiceUrl == null || voiceUrl.isEmpty)
              TvFocusableAction(
                onPressed: () => Navigator.of(ctx).pop('edit'),
                child: ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit comment'),
                  onTap: () => Navigator.of(ctx).pop('edit'),
                ),
              ),
            TvFocusableAction(
              onPressed: () => Navigator.of(ctx).pop('delete'),
              child: ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete comment'),
                onTap: () => Navigator.of(ctx).pop('delete'),
              ),
            ),
          ],
        ),
      ),
    );

    if (action == 'edit') {
      await _editComment(doc);
    } else if (action == 'delete') {
      await _deleteComment(doc);
    }
  }

  Future<void> _editComment(aw.Row doc) async {
    final controller =
        TextEditingController(text: (doc.data['content'] as String?) ?? '');
    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit comment'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newText == null || newText.isEmpty) return;

    try {
      final updated = await BackendService.updateRow(
        BackendService.commentsCollectionId,
        doc.$id,
        <String, dynamic>{'content': newText},
      );
      if (!mounted) return;
      setState(() {
        final parentId = doc.data['parentCommentId'] as String?;
        if (parentId != null && parentId.isNotEmpty) {
          final replies = _repliesByParent[parentId];
          final index = replies?.indexWhere((row) => row.$id == doc.$id) ?? -1;
          if (replies != null && index != -1) {
            replies[index] = updated;
          }
        } else {
          final index = _rootComments.indexWhere((row) => row.$id == doc.$id);
          if (index != -1) {
            _rootComments[index] = updated;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to update comment. Please try again.')),
      );
    }
  }

  Future<void> _deleteComment(aw.Row doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete comment?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final parentId = doc.data['parentCommentId'] as String?;
    try {
      await BackendService.deleteComment(doc.$id);
      unawaited(BackendService.incrementPostComments(widget.post.id, -1));
      if (parentId != null && parentId.isNotEmpty) {
        unawaited(BackendService.incrementCommentReplies(parentId, -1));
      }
      if (!mounted) return;
      setState(() {
        if (parentId != null && parentId.isNotEmpty) {
          _repliesByParent[parentId]?.removeWhere((row) => row.$id == doc.$id);
          final parentIndex =
              _rootComments.indexWhere((row) => row.$id == parentId);
          if (parentIndex != -1) {
            final parentData = _rootComments[parentIndex].data;
            final rawReplies = parentData['replies'];
            final currentReplies = rawReplies is int
                ? rawReplies
                : int.tryParse('$rawReplies') ?? 0;
            parentData['replies'] = (currentReplies - 1).clamp(0, 1 << 31);
          }
        } else {
          _rootComments.removeWhere((row) => row.$id == doc.$id);
          _repliesByParent.remove(doc.$id);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to delete comment. Please try again.')),
      );
    }
  }

  Future<void> _handleMentionTap(String usernameToken) async {
    final handle = usernameToken.replaceAll('@', '').trim();
    if (handle.isEmpty) return;
    final prof = await BackendService.getProfileByUsername(handle);
    if (!mounted) return;
    if (prof == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User @$handle not found')),
      );
      return;
    }
    final userId = prof.data['userId'] as String? ?? prof.$id;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)),
    );
  }

  void _handleHashtagTap(String tagToken) {
    final clean = tagToken.replaceAll('#', '').trim();
    if (clean.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HashtagFeedScreen(tag: clean)),
    );
  }

  Future<void> _openCommentOwnerProfile(aw.Row doc) async {
    final data = doc.data;
    String? userId = data['userId'] as String?;
    if (userId == null || userId.isEmpty) {
      final username = (data['username'] as String? ?? '').trim();
      if (username.isNotEmpty) {
        final prof = await BackendService.getProfileByUsername(username);
        if (prof != null) {
          userId = prof.data['userId'] as String? ?? prof.$id;
        }
      }
    }
    if (!mounted || userId == null || userId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)),
    );
  }


  String _formatTimeAgo(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) {
      return 'Just now';
    }
    return timeago.format(timestamp);
  }
}

