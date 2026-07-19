import 'dart:async';

import 'package:appwrite/models.dart' as aw;
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../services/appwrite_service.dart';
import '../services/storage_service.dart';
import '../widgets/post_card.dart';
import 'hashtag_feed_screen.dart';
import 'post_detail_screen.dart';
import 'profile_screen.dart';
import 'reel_detail_screen.dart';
import 'video_detail_screen.dart';
import '../widgets/verification_badge.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  String _activeTab = 'all';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(value.trim());
    });
    setState(() {});
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final List<Map<String, dynamic>> searchResults = [];
      final lowerQuery = query.toLowerCase();

      if (_activeTab == 'all' || _activeTab == 'posts') {
        try {
          final postsResult =
              await AppwriteService.searchPostsByTextAcrossPages(
            query,
            limit: 50,
          );
          for (final row in postsResult.rows) {
            final data = row.data;
            final haystack = [
              data['content'],
              data['title'],
              data['username'],
              data['displayName'],
              data['caption'],
              data['description'],
              data['seoTitle'],
              data['seoDescription'],
              data['seoCategory'],
            ].whereType<String>().join(' ').toLowerCase();
            if (!haystack.contains(lowerQuery)) continue;

            final mapped = await _mapRowToSearchPost(row);
            searchResults.add({
              'type': 'post',
              'post': mapped.$1,
              'mediaUrls': mapped.$2,
              'authorId': data['userId'] as String? ?? '',
            });
          }
        } catch (_) {}
      }

      if (_activeTab == 'all' || _activeTab == 'users') {
        try {
          final handle = query.startsWith('@') ? query.substring(1) : query;
          final profiles =
              await AppwriteService.searchProfiles(handle, limit: 10);
          final profileRows = <aw.Row>[
            ...profiles.rows,
          ];
          for (final row in profileRows) {
            final data = row.data;
            final username = (data['username'] as String? ?? '').trim();
            final displayName = (data['displayName'] as String? ?? '').trim();
            final bio = (data['bio'] as String? ?? '').trim();
            final searchHaystack = [
              username,
              displayName,
              bio,
            ].join(' ').toLowerCase();
            if (!searchHaystack.contains(lowerQuery)) continue;
            searchResults.add({
              'type': 'user',
              'id': data['userId'] as String? ?? row.$id,
              'displayName': displayName,
              'username': username,
              'bio': bio,
              'avatarUrl': (data['avatarUrl'] as String?) ?? '',
            });
          }
        } catch (_) {}
      }

      if (_activeTab == 'all' || _activeTab == 'hashtags') {
        try {
          final postsResult = await AppwriteService.fetchPosts(limit: 80);
          final Map<String, int> counts = {};
          final regex = RegExp(r'#([A-Za-z0-9_]+)');
          for (final row in postsResult.rows) {
            final content = (row.data['content'] as String?) ?? '';
            for (final match in regex.allMatches(content)) {
              final tag = '#${match.group(1)!}';
              if (!tag
                  .toLowerCase()
                  .contains(lowerQuery.replaceFirst('#', ''))) {
                continue;
              }
              counts[tag] = (counts[tag] ?? 0) + 1;
            }
          }
          final tags = counts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          for (final entry in tags.take(10)) {
            searchResults.add({
              'type': 'hashtag',
              'tag': entry.key,
              'count': entry.value,
            });
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _results = searchResults;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _isLoading = false;
      });
    }
  }

  Future<(Post, List<String>)> _mapRowToSearchPost(aw.Row row) async {
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


  void _openPost(Post post, List<String> mediaUrls, String? authorId) {
    final postType = (post.postType ?? '').toLowerCase();
    final isReel = postType.contains('reel');
    final isVideo = postType.contains('video') || isReel;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) {
          if (isReel) {
            return ReelDetailScreen(
              post: post,
              isGuest: false,
              onGuestAction: null,
              authorId: authorId,
            );
          }
          if (isVideo) {
            return VideoDetailScreen(
              post: post,
              mediaUrls: mediaUrls,
              authorId: authorId,
            );
          }
          return PostDetailScreen(
            post: post,
            mediaUrls: mediaUrls,
            authorId: authorId,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: colorScheme.surface,
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(
                          Icons.arrow_back,
                          color: colorScheme.onSurface,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(999),
                            border:
                                Border.all(color: colorScheme.outlineVariant),
                          ),
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            style: TextStyle(color: colorScheme.onSurface),
                            cursorColor: colorScheme.primary,
                            decoration: InputDecoration(
                              hintText: 'Search XapZap',
                              hintStyle: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              border: InputBorder.none,
                              prefixIcon: Icon(
                                Icons.search,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              suffixIcon: _searchController.text.isEmpty
                                  ? null
                                  : IconButton(
                                      onPressed: () {
                                        _searchController.clear();
                                        _performSearch('');
                                      },
                                      icon: Icon(
                                        Icons.close,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                            ),
                            onChanged: _onQueryChanged,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_searchController.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildTabChip('all', 'All'),
                      _buildTabChip('posts', 'Posts'),
                      _buildTabChip('users', 'Users'),
                      _buildTabChip('hashtags', 'Hashtags'),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildTabChip(String id, String label) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isActive = _activeTab == id;
    return GestureDetector(
      onTap: () {
        setState(() => _activeTab = id);
        _performSearch(_searchController.text.trim());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                isActive ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final query = _searchController.text.trim();
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }
    if (query.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.trending_up,
              size: 48,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Trending topics will appear here',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 15,
              ),
            ),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search,
              size: 48,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No results found for "$query"',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        switch (result['type']) {
          case 'post':
            final post = result['post'] as Post;
            final mediaUrls = result['mediaUrls'] as List<String>;
            final authorId = result['authorId'] as String?;
            return Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: PostCard(
                post: post,
                mediaUrls: mediaUrls,
                authorId: authorId,
                onOpenPost: () => _openPost(post, mediaUrls, authorId),
              ),
            );
          case 'user':
            return _buildUserRow(result);
          case 'hashtag':
            return _buildHashtagRow(result);
          default:
            return const SizedBox.shrink();
        }
      },
    );
  }

  Widget _buildUserRow(Map<String, dynamic> user) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bio = (user['bio'] as String? ?? '').trim();
    final displayName = (user['displayName'] as String?)?.trim() ?? '';
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProfileScreen(userId: user['id'] as String),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Builder(
              builder: (context) {
                final url = StorageService.getImageDisplayUrlSync(user['avatarUrl'] as String? ?? '');
                if (url.isNotEmpty) {
                  return CircleAvatar(
                    radius: 24,
                    backgroundImage: NetworkImage(url),
                  );
                }
                return CircleAvatar(
                  radius: 24,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.person,
                    color: colorScheme.onSurfaceVariant,
                  ),
                );
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user['isVerified'] == true ||
                          user['verified'] == true ||
                          user['isAdmin'] == true) ...[
                        const SizedBox(width: 6),
                        VerificationBadge(
                          size: 15,
                          isPremium: user['isAdmin'] == true,
                        ),
                      ],
                    ],
                  ),
                  if (bio.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      bio,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHashtagRow(Map<String, dynamic> hashtag) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tag = hashtag['tag'] as String? ?? '#tag';
    final count = hashtag['count'] as int? ?? 0;
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => HashtagFeedScreen(tag: tag.replaceFirst('#', '')),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.tag,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tag,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count posts',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.trending_up,
              color: colorScheme.onSurfaceVariant,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

