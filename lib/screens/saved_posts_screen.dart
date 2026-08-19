import 'package:flutter/material.dart';
import 'package:xapzap/models/database_models.dart' as aw;

import '../models/post.dart';
import '../services/backend_service.dart';
import '../services/storage_service.dart';
import '../widgets/post_card.dart';
import 'post_detail_screen.dart';
import 'reel_detail_screen.dart';
import 'video_detail_screen.dart';

class SavedPostsScreen extends StatefulWidget {
  const SavedPostsScreen({super.key});

  @override
  State<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends State<SavedPostsScreen> {
  bool _loading = true;
  List<Post> _posts = <Post>[];
  final Map<String, List<String>> _mediaByPostId = <String, List<String>>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = await BackendService.getCurrentUser();
      if (user == null) {
        if (!mounted) return;
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/signin', (route) => false);
        return;
      }
      final rows =
          await BackendService.fetchSavedPosts(userId: user.$id, limit: 50);
      final posts = <Post>[];
      _mediaByPostId.clear();
      for (final row in rows.rows) {
        final mapped = await _mapRowToPost(row);
        posts.add(mapped.$1);
        _mediaByPostId[row.$id] = mapped.$2;
      }
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<(Post, List<String>)> _mapRowToPost(aw.Row row) async {
    final data = row.data;
    final rawMedia = data['mediaUrls'] is List
        ? (data['mediaUrls'] as List).map((e) => e.toString()).toList()
        : <String>[];
    final postType = (data['postType'] as String?)?.toLowerCase() ?? '';
    final isVideo = postType.contains('video') || postType.contains('reel');

    String? videoUrl;
    String? imageUrl;
    final mediaForUi = <String>[];

    if (isVideo && rawMedia.isNotEmpty) {
      final first = rawMedia.first;
      videoUrl = (first.startsWith('http://') || first.startsWith('https://'))
          ? first
          : await StorageService.getVideoDisplayUrl(first);
      final thumbnail = (data['thumbnailUrl'] as String?) ?? '';
      imageUrl = thumbnail.isNotEmpty
          ? await StorageService.getImageDisplayUrl(thumbnail)
          : null;
      if (imageUrl != null) mediaForUi.add(imageUrl);
    } else {
      for (final media in rawMedia) {
        mediaForUi.add(await StorageService.getImageDisplayUrl(media));
      }
      imageUrl = mediaForUi.isNotEmpty ? mediaForUi.first : null;
    }

    return (
      Post(
        id: row.$id,
        username: data['username'] as String? ?? '',
        userAvatar: data['userAvatar'] as String? ?? '',
        content: data['content'] as String? ?? '',
        textBgColor: data['textBgColor'] as int?,
        timestamp: DateTime.tryParse(row.$createdAt) ?? DateTime.now(),
        likes: data['likes'] as int? ?? 0,
        comments: data['comments'] as int? ?? 0,
        reposts: data['reposts'] as int? ?? 0,
        impressions: data['impressions'] as int? ?? 0,
        views: data['views'] as int? ?? 0,
        imageUrl: imageUrl,
        videoUrl: videoUrl,
        postType: data['postType'] as String?,
        title: data['title'] as String?,
        thumbnailUrl: data['thumbnailUrl'] as String?,
      ),
      mediaForUi,
    );
  }

  bool _isVideo(Post post) {
    final type = post.postType?.toLowerCase() ?? '';
    return type.contains('video') || type.contains('reel');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Posts'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _posts.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(
                            height: 300,
                            child: Center(child: Text('No saved posts yet'))),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _posts.length,
                      itemBuilder: (context, index) {
                        final post = _posts[index];
                        final isVideo = _isVideo(post);
                        final isReel = (post.postType ?? '')
                            .toLowerCase()
                            .contains('reel');
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: PostCard(
                            post: post,
                            isGuest: false,
                            onGuestAction: null,
                            mediaUrls: _mediaByPostId[post.id],
                            trackImpressions: !isVideo,
                            showReelBadge: isReel,
                            onOpenPost: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) {
                                    if (isReel &&
                                        isVideo &&
                                        post.videoUrl != null &&
                                        post.videoUrl!.isNotEmpty) {
                                      return ReelDetailScreen(
                                        post: post,
                                        isGuest: false,
                                        onGuestAction: null,
                                      );
                                    }
                                    if (isVideo &&
                                        post.videoUrl != null &&
                                        post.videoUrl!.isNotEmpty) {
                                      return VideoDetailScreen(
                                        post: post,
                                        mediaUrls: _mediaByPostId[post.id],
                                        isGuest: false,
                                        onGuestAction: null,
                                      );
                                    }
                                    return PostDetailScreen(
                                      post: post,
                                      mediaUrls: _mediaByPostId[post.id],
                                      isGuest: false,
                                      onGuestAction: null,
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

