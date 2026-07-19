import 'dart:async';

import 'package:appwrite/models.dart' as aw;
import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../models/app_notification.dart';
import '../models/post.dart';
import '../services/appwrite_service.dart';
import '../services/storage_service.dart';
import 'individual_chat_screen.dart';
import 'live_screen.dart';
import 'post_detail_screen.dart';
import 'profile_screen.dart';
import 'reel_detail_screen.dart';
import 'video_detail_screen.dart';

class NotificationLandingScreen extends StatefulWidget {
  final Map<String, dynamic> payload;

  const NotificationLandingScreen({
    super.key,
    required this.payload,
  });

  factory NotificationLandingScreen.fromNotification(
    AppNotification notification,
  ) {
    return NotificationLandingScreen(
      payload: <String, dynamic>{
        'notificationId': notification.id,
        'type': notification.type ?? 'post',
        'actionUrl': notification.actionUrl ?? '',
        'postId': notification.postId ?? '',
        'chatId': notification.chatId ?? '',
        'title': notification.title,
        'body': notification.body,
      },
    );
  }

  @override
  State<NotificationLandingScreen> createState() =>
      _NotificationLandingScreenState();
}

class _NotificationLandingScreenState extends State<NotificationLandingScreen> {
  bool _loading = true;
  String? _error;
  Widget? _resolvedTarget;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveTarget();
    });
  }

  Future<void> _resolveTarget() async {
    final payload = widget.payload;
    final notificationId = _stringValue(payload['notificationId']);
    if (notificationId.isNotEmpty) {
      unawaited(AppwriteService.markNotificationAsRead(notificationId));
    }
    final type = _stringValue(payload['type']).toLowerCase();
    final actionUrl = _stringValue(payload['actionUrl']);
    final postId = _extractPostId(payload, actionUrl);
    final chatId = _extractChatId(payload, actionUrl);
    final profileUserId = _extractProfileUserId(payload, actionUrl);

    if (type == 'live' || actionUrl.toLowerCase().contains('live')) {
      if (!mounted) return;
      setState(() {
        _resolvedTarget = const LiveScreen(isGuest: false);
        _loading = false;
      });
      return;
    }

    if (type == 'chat' || actionUrl.toLowerCase().contains('/chat/')) {
      await _openChatTarget(chatId);
      return;
    }

    if (type == 'follow' || actionUrl.toLowerCase().contains('/profile/')) {
      await _openProfileTarget(profileUserId);
      return;
    }

    if (postId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _error = 'This notification does not have a post to open.';
        _loading = false;
      });
      return;
    }

    try {
      final row = await AppwriteService.getRow(
          AppwriteService.postsCollectionId, postId);
      final mapped = await _mapRowToPost(row);
      if (!mounted) return;
      final postType = (mapped.$1.postType ?? '').toLowerCase();
      final isReel = postType.contains('reel');
      final isVideo = postType.contains('video') || isReel;
      final authorId = row.data['userId'] as String? ?? '';
      setState(() {
        _resolvedTarget = isReel
            ? ReelDetailScreen(post: mapped.$1, authorId: authorId)
            : isVideo
                ? VideoDetailScreen(
                    post: mapped.$1,
                    mediaUrls: mapped.$2,
                    authorId: authorId,
                  )
                : PostDetailScreen(
                    post: mapped.$1,
                    mediaUrls: mapped.$2,
                    authorId: authorId,
                  );
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not open this notification.';
        _loading = false;
      });
    }
  }

  Future<void> _openProfileTarget(String userId) async {
    if (userId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _error = 'This notification does not have a profile to open.';
        _loading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _resolvedTarget = ProfileScreen(userId: userId);
      _loading = false;
    });
  }

  Future<void> _openChatTarget(String chatId) async {
    if (chatId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _error = 'This notification does not have a chat to open.';
        _loading = false;
      });
      return;
    }

    try {
      final chatRow =
          await AppwriteService.getRow(AppwriteService.chatsCollectionId, chatId);
      final memberIds = _memberIdsFromRow(chatRow);
      final currentUser = await AppwriteService.getCurrentUser();
      final currentUserId = currentUser?.$id ?? '';
      final partnerId = memberIds.firstWhere(
        (id) => id != currentUserId,
        orElse: () => '',
      );
      if (partnerId.isEmpty) {
        throw StateError('Chat partner could not be resolved.');
      }
      final profile = await AppwriteService.getProfileByUserId(partnerId);
      final pdata = profile?.data ?? <String, dynamic>{};
      final partnerName =
          (pdata['displayName'] as String?)?.trim().isNotEmpty == true
              ? (pdata['displayName'] as String).trim()
              : ((pdata['username'] as String?)?.trim().isNotEmpty == true
                  ? (pdata['username'] as String).trim()
                  : 'Chat');
      final partnerAvatar = (pdata['avatarUrl'] as String?)?.trim() ?? '';

      if (!mounted) return;
      setState(() {
        _resolvedTarget = IndividualChatScreen(
          chat: Chat(
            id: chatId,
            partnerId: partnerId,
            partnerName: partnerName,
            partnerAvatar: partnerAvatar,
            lastMessage: (chatRow.data['lastMessage'] as String?) ?? '',
            timestamp: DateTime.tryParse(
                  chatRow.data['lastMessageAt'] as String? ?? '',
                ) ??
                DateTime.tryParse(chatRow.$createdAt) ??
                DateTime.now(),
            unreadCount: (chatRow.data['unreadCount'] as num?)?.toInt() ?? 0,
            isOnline: false,
          ),
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not open this chat notification.';
        _loading = false;
      });
    }
  }

  String _extractPostId(Map<String, dynamic> payload, String actionUrl) {
    final direct = _stringValue(payload['postId']);
    if (direct.isNotEmpty) return direct;
    final url = actionUrl.trim();
    final match = RegExp(r'/post/([^/?#]+)').firstMatch(url);
    if (match != null && match.group(1) != null) {
      return match.group(1)!.trim();
    }
    return '';
  }

  String _extractChatId(Map<String, dynamic> payload, String actionUrl) {
    final direct = _stringValue(payload['chatId']);
    if (direct.isNotEmpty) return direct;
    final url = actionUrl.trim();
    final match = RegExp(r'/chat/([^/?#]+)').firstMatch(url);
    if (match != null && match.group(1) != null) {
      return match.group(1)!.trim();
    }
    return '';
  }

  String _extractProfileUserId(Map<String, dynamic> payload, String actionUrl) {
    final direct = _stringValue(payload['profileUserId']);
    if (direct.isNotEmpty) return direct;
    final url = actionUrl.trim();
    final match = RegExp(r'/profile/([^/?#]+)').firstMatch(url);
    if (match != null && match.group(1) != null) {
      return match.group(1)!.trim();
    }
    return '';
  }

  String _stringValue(Object? value) => value?.toString().trim() ?? '';

  List<String> _memberIdsFromRow(aw.Row row) {
    final raw = (row.data['memberIds'] as String?) ?? '';
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  Future<(Post, List<String>)> _mapRowToPost(aw.Row row) async {
    final data = row.data;
    final List<String> rawMedia = data['mediaUrls'] is List
        ? (data['mediaUrls'] as List).map((e) => e.toString()).toList()
        : <String>[];
    final postType = data['postType'] as String?;
    final title = data['title'] as String?;
    final thumbnailUrl = data['thumbnailUrl'] as String?;
    final postTypeLower = (postType ?? '').toLowerCase();
    final bool isVideoPost =
        postTypeLower.contains('video') || postTypeLower.contains('reel');

    String? videoUrl;
    String? firstImage;
    List<String> mediaForUi;

    if (isVideoPost && rawMedia.isNotEmpty) {
      final first = rawMedia.first;
      videoUrl = (first.startsWith('http://') || first.startsWith('https://'))
          ? first
          : await StorageService.getVideoDisplayUrl(first);
      firstImage = thumbnailUrl?.isNotEmpty == true
          ? await StorageService.getImageDisplayUrl(thumbnailUrl!)
          : (rawMedia.length > 1
              ? await StorageService.getImageDisplayUrl(rawMedia[1])
              : null);
      mediaForUi = firstImage != null ? <String>[firstImage] : <String>[];
    } else {
      firstImage = thumbnailUrl?.isNotEmpty == true
          ? await StorageService.getImageDisplayUrl(thumbnailUrl!)
          : (rawMedia.isNotEmpty
              ? await StorageService.getImageDisplayUrl(rawMedia.first)
              : null);
      mediaForUi = <String>[];
      for (final media in rawMedia) {
        mediaForUi.add(await StorageService.getImageDisplayUrl(media));
      }
    }

    return (
      Post(
        id: row.$id,
        username: (data['displayName'] as String?)?.trim() ?? '',
        userAvatar: data['userAvatar'] as String? ?? '',
        content: data['content'] as String? ?? '',
        imageUrl: firstImage,
        videoUrl: videoUrl,
        postType: postType,
        title: title,
        thumbnailUrl: thumbnailUrl,
        timestamp: DateTime.tryParse(row.$createdAt) ??
            DateTime.tryParse((data['createdAt'] as String?) ?? '') ??
            DateTime.now(),
        likes: data['likes'] as int? ?? 0,
        comments: data['comments'] as int? ?? 0,
        reposts: data['reposts'] as int? ?? 0,
        impressions: data['impressions'] as int? ?? 0,
        views: data['views'] as int? ?? 0,
        textBgColor: data['textBgColor'] as int?,
      ),
      mediaForUi,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_resolvedTarget != null) {
      return _resolvedTarget!;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Notification')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.notifications, size: 48),
              const SizedBox(height: 16),
              Text(
                _error ?? 'Could not open this notification.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _resolveTarget,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

