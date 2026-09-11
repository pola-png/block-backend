import 'dart:io';
import 'dart:async';


import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/status.dart';
import '../services/story_manager.dart';
import 'status_viewer_screen.dart';
import 'story_publish_screen.dart';
import '../models/app_notification.dart';
import '../services/backend_service.dart';
import '../services/navigation_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    StoryManager.init();
    StoryManager.loadFromServer();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Updates'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Status'),
              Tab(text: 'Notifications'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildStatusTab(),
            _NotificationsList(isDark: isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTab() {
    return ValueListenableBuilder<List<StatusUpdate>>(
      valueListenable: StoryManager.stories,
      builder: (context, statuses, _) {
        final others = statuses.where((s) => s.id != 'me').toList();
        final unviewed = others.where((s) => !s.isViewed).toList();
        final viewed = others.where((s) => s.isViewed).toList();
        final myStatus = statuses.firstWhere(
          (s) => s.id == 'me',
          orElse: () => statuses.isNotEmpty
              ? statuses.first
              : StoryManager.stories.value.first,
        );
        return RefreshIndicator(
          onRefresh: () => StoryManager.loadFromServer(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              ListTile(
                onTap: _showStoryOptions,
                leading: Stack(
                  children: [
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: myStatus.isUploading
                          ? Stack(
                              alignment: Alignment.center,
                              children: [
                                const SizedBox(
                                  width: 52,
                                  height: 52,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF1DA1F2),
                                    ),
                                    backgroundColor: Colors.black12,
                                  ),
                                ),
                                CircleAvatar(
                                  radius: 22,
                                  backgroundColor: Colors.grey.shade300,
                                  backgroundImage:
                                      _buildMyStatusImage(myStatus),
                                  child: _buildMyStatusImage(myStatus) == null
                                      ? const Icon(Icons.person,
                                          color: Colors.white)
                                      : null,
                                ),
                              ],
                            )
                          : CircleAvatar(
                              radius: 26,
                              backgroundColor: Colors.grey.shade300,
                              backgroundImage: _buildMyStatusImage(myStatus),
                              child: _buildMyStatusImage(myStatus) == null
                                  ? const Icon(Icons.person,
                                      color: Colors.white)
                                  : null,
                            ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF00A884),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.add,
                            size: 12, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                title: const Text('My status',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  myStatus.isUploading
                      ? 'Uploading story...'
                      : 'Tap to add status update',
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Recent updates',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280)),
                ),
              ),
              if (unviewed.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child:
                          Text('No new stories from people you follow yet.')),
                ),
              ...unviewed.map(_buildStatusTile),
              if (viewed.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Viewed updates',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6B7280)),
                  ),
                ),
              ...viewed.map((status) => _buildStatusTile(status, viewed: true)),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showStoryOptions() async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose photo'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickStory(ImageSource.gallery, video: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library),
                title: const Text('Choose video'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickStory(ImageSource.gallery, video: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take photo'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickStory(ImageSource.camera, video: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('Record video'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickStory(ImageSource.camera, video: true);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickStory(ImageSource source, {required bool video}) async {
    try {
      final file = video
          ? await _picker.pickVideo(
              source: source, maxDuration: const Duration(seconds: 30))
          : await _picker.pickImage(source: source);
      if (file == null || !mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StoryPublishScreen(media: file)),
      );
    } catch (_) {}
  }

  void _openStatus(StatusUpdate status) {
    status.isViewed = true;
    StoryManager.markViewed(status.id);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StatusViewerScreen(status: status)),
    );
  }

  Widget _buildStatusTile(StatusUpdate status, {bool viewed = false}) {
    return ListTile(
      onTap: () => _openStatus(status),
      leading: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: viewed ? Colors.black : const Color(0xFF29ABE2),
            width: 2,
          ),
        ),
        child: CircleAvatar(
          radius: 24,
          backgroundColor: Colors.grey.shade200,
          child: ClipOval(
            child: SizedBox(
              width: 48,
              height: 48,
              child: _StatusTileThumbnail(status: status),
            ),
          ),
        ),
      ),
      title: Text(status.username,
          style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(_formatTimestamp(status.timestamp)),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inDays > 0) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
    }
    return 'Just now';
  }

  ImageProvider<Object>? _buildMyStatusImage(StatusUpdate status) {
    final previewPath = status.isUploading && status.mediaUrls.isNotEmpty
        ? status.mediaUrls.first
        : '';
    if (previewPath.isNotEmpty &&
        !previewPath.startsWith('http://') &&
        !previewPath.startsWith('https://')) {
      return FileImage(File(previewPath));
    }
    if (status.userAvatar.isNotEmpty) {
      return NetworkImage(status.userAvatar);
    }
    return null;
  }
}

class _NotificationsList extends StatefulWidget {
  final bool isDark;

  const _NotificationsList({required this.isDark});

  @override
  State<_NotificationsList> createState() => _NotificationsListState();
}

class _NotificationsListState extends State<_NotificationsList> {
  List<AppNotification> _notifications = const [];
  bool _loading = true;
  RealtimeSubscription? _notificationsSub;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _notificationsSub?.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final user = await BackendService.getCurrentUser();
    if (!mounted) return;
    if (user == null) {
      setState(() {
        _notifications = const [];
        _loading = false;
      });
      return;
    }
    final items = await BackendService.fetchNotifications(user.$id);
    if (!mounted) return;
    setState(() {
      _notifications = items;
      _loading = false;
    });
  }

  void _subscribeRealtime() {
    try {
      final channel =
          'databases.${BackendService.databaseId}.collections.${BackendService.notificationsCollectionId}.documents';
      _notificationsSub = BackendService.realtime.subscribe([channel]);
      _notificationsSub?.stream.listen((event) {
        if (!mounted || event.events.isEmpty) return;
        if (event.events.any((e) =>
            e.contains('.create') ||
            e.contains('.update') ||
            e.contains('.delete'))) {
          unawaited(_load());
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final subtitleColor =
        widget.isDark ? const Color(0xFF8696A0) : const Color(0xFF6B7280);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_notifications.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text('No notifications yet')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _buildNotificationsHeader(),
          const Divider(height: 0),
          for (var index = 0; index < _notifications.length; index++) ...[
            Builder(
              builder: (context) {
                final notification = _notifications[index];
                final icon = _iconForNotification(notification.type);
                return ListTile(
                  onTap: () async {
                    await BackendService.markNotificationAsRead(
                      notification.id,
                    );
                    if (!mounted) return;
                    setState(() {
                      _notifications = _notifications
                          .map(
                            (item) => item.id == notification.id
                                ? AppNotification(
                                    id: item.id,
                                    title: item.title,
                                    body: item.body,
                                    timestamp: item.timestamp,
                                    read: true,
                                    actorName: item.actorName,
                                    actorAvatar: item.actorAvatar,
                                    type: item.type,
                                    actionUrl: item.actionUrl,
                                    postId: item.postId,
                                    chatId: item.chatId,
                                  )
                                : item,
                          )
                          .toList(growable: false);
                    });
                    unawaited(
                      openNotificationLandingFromNotification(notification),
                    );
                  },
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundImage: notification.actorAvatar != null &&
                            notification.actorAvatar!.isNotEmpty
                        ? NetworkImage(notification.actorAvatar!)
                        : null,
                    child: (notification.actorAvatar == null ||
                            notification.actorAvatar!.isEmpty)
                        ? Icon(icon)
                        : null,
                  ),
                  title: Row(
                    children: [
                      Expanded(child: Text(notification.title)),
                      if (!notification.read) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF29ABE2),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    notification.body.isNotEmpty
                        ? '${notification.body}\n${_formatTimestamp(notification.timestamp)}'
                        : _formatTimestamp(notification.timestamp),
                    style: TextStyle(color: subtitleColor),
                  ),
                  isThreeLine: notification.body.isNotEmpty,
                );
              },
            ),
            if (index != _notifications.length - 1)
              Divider(
                height: 0,
                indent: 72,
                color: widget.isDark
                    ? const Color(0xFF202C33)
                    : const Color(0xFFE5E7EB),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildNotificationsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Notifications',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton.icon(
            onPressed: _notifications.isEmpty
                ? null
                : () async {
                    final user = await BackendService.getCurrentUser();
                    if (user == null) return;
                    await BackendService.markAllNotificationsAsRead(user.$id);
                    if (!mounted) return;
                    await _load();
                  },
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: const Text('Mark all as read'),
          ),
        ],
      ),
    );
  }

  IconData _iconForNotification(String? type) {
    switch ((type ?? '').toLowerCase()) {
      case 'chat':
      case 'message':
        return Icons.chat_bubble_outline_rounded;
      case 'follow':
        return Icons.person_add_alt_1_rounded;
      case 'like':
      case 'post_like':
      case 'comment_like':
        return Icons.favorite_outline_rounded;
      case 'comment':
      case 'reply':
      case 'comment_reply':
        return Icons.mode_comment_outlined;
      case 'post':
      case 'post_create':
        return Icons.post_add_rounded;
      case 'repost':
        return Icons.repeat_rounded;
      case 'save':
        return Icons.bookmark_outline_rounded;
      case 'live':
        return Icons.live_tv_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    }
    return 'Just now';
  }
}

class _StatusTileThumbnail extends StatelessWidget {
  const _StatusTileThumbnail({required this.status});

  final StatusUpdate status;

  @override
  Widget build(BuildContext context) {
    final media = status.mediaUrls.isNotEmpty ? status.mediaUrls.first : '';
    if (media.isNotEmpty) {
      if (_looksLikeVideoStory(media)) {
        return _StatusTileVideoThumbnail(videoUrl: media);
      }
      if (media.startsWith('http://') || media.startsWith('https://')) {
        return CachedNetworkImage(
          imageUrl: media,
          fit: BoxFit.cover,
          errorWidget: (context, _, __) => _buildFallbackAvatar(status),
        );
      }
      return Image.file(
        File(media),
        fit: BoxFit.cover,
        errorBuilder: (context, _, __) => _buildFallbackAvatar(status),
      );
    }
    return _buildFallbackAvatar(status);
  }

  Widget _buildFallbackAvatar(StatusUpdate status) {
    if (status.userAvatar.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: status.userAvatar,
        fit: BoxFit.cover,
        errorWidget: (context, _, __) => Container(
          color: Colors.grey.shade300,
          alignment: Alignment.center,
          child: const Icon(Icons.person, color: Colors.white),
        ),
      );
    }
    return Container(
      color: Colors.grey.shade300,
      alignment: Alignment.center,
      child: const Icon(Icons.person, color: Colors.white),
    );
  }
}

bool _looksLikeVideoStory(String url) {
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

class _StatusTileVideoThumbnail extends StatelessWidget {
  const _StatusTileVideoThumbnail({required this.videoUrl});

  final String videoUrl;
  static final Map<String, Future<String?>> _thumbnailFutures =
      <String, Future<String?>>{};

  Future<String?> _loadThumbnail() {
    return _thumbnailFutures.putIfAbsent(
      videoUrl,
      () => VideoThumbnail.thumbnailFile(
        video: videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxHeight: 120,
        quality: 70,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _loadThumbnail(),
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (path == null || path.isEmpty) {
          return Container(
            color: Colors.black87,
            alignment: Alignment.center,
            child: const Icon(
              Icons.play_arrow,
              color: Colors.white,
              size: 22,
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (context, _, __) => Container(
                color: Colors.black87,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        );
      },
    );
  }
}
