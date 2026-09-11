import 'package:xapzap/models/database_models.dart' as aw;

import '../models/post.dart';
import '../services/backend_service.dart';
import '../services/storage_service.dart';
import '../services/feed_cache.dart';
import '../services/avatar_cache.dart';

/// Preloads the home feed in the background so that
/// the HomeScreen can render instantly using FeedCache.
class FeedPrefetcher {
  static bool _started = false;
  static int _sessionSeed = 0;

  static Future<void> preloadHomeFeeds() async {
    if (_started) return;
    _started = true;

    try {
      final user = await BackendService.getCurrentUser();
      _sessionSeed = DateTime.now().millisecondsSinceEpoch;
      final followingIds = user != null
          ? await BackendService.getFollowingUserIds(user.$id)
          : <String>[];

      await Future.wait([
        _preloadForYou(userId: user?.$id),
        if (followingIds.isNotEmpty) _preloadFollowing(followingIds),
      ]);
    } catch (_) {
      // Best-effort only; HomeScreen will still load feeds normally.
    }
  }

  static Future<void> _preloadForYou({String? userId}) async {
    if (FeedCache.hasForYou) return;

    final feedPage = userId == null
        ? await BackendService.fetchPostsPage(
            limit: 40,
            applyFeedRanking: true,
            sessionSeed: _sessionSeed,
          )
        : await BackendService.fetchForYouFeedPage(
            userId: userId,
            limit: 40,
            sessionSeed: _sessionSeed,
          );
    final List<aw.Row> docs = feedPage.rows;
    if (docs.isEmpty) return;

    if (userId != null && userId.isNotEmpty) {
      try {
        await BackendService.prefetchUserReactionsAndFollows(
          userId: userId,
          postIds: docs.map((d) => d.$id).toList(),
          authorIds: docs
              .map((d) => d.data['userId'] as String? ?? '')
              .toList(),
        );
      } catch (_) {}
    }
    final posts = <Post>[];
    final mediaByPostId = <String, List<String>>{};
    final authorByPostId = <String, String>{};

    for (final d in docs) {
      final data = d.data;
      final List<String> rawMedia = data['mediaUrls'] is List
          ? (data['mediaUrls'] as List).map((item) => item.toString()).toList()
          : <String>[];
      authorByPostId[d.$id] = data['userId'] as String? ?? '';
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
            ? (thumbnailUrl!.startsWith('http')
                ? await StorageService.getImageDisplayUrl(thumbnailUrl)
                : await StorageService.getImageDisplayUrl(thumbnailUrl))
            : (rawMedia.length > 1
                ? await StorageService.getImageDisplayUrl(rawMedia[1])
                : null);
        mediaForUi = firstImage != null ? <String>[firstImage] : <String>[];
      } else {
        firstImage = thumbnailUrl?.isNotEmpty == true
            ? (thumbnailUrl!.startsWith('http')
                ? await StorageService.getImageDisplayUrl(thumbnailUrl)
                : await StorageService.getImageDisplayUrl(thumbnailUrl))
            : (rawMedia.isNotEmpty
                ? await StorageService.getImageDisplayUrl(rawMedia.first)
                : null);
        mediaForUi = <String>[];
        for (final media in rawMedia) {
          mediaForUi.add(await StorageService.getImageDisplayUrl(media));
        }
      }

      mediaByPostId[d.$id] = mediaForUi;

      // Warm avatar cache so feed avatars are instant.
      final userId = data['userId'] as String? ?? '';
      String avatar = data['userAvatar'] as String? ?? '';
      if (userId.isNotEmpty && avatar.isNotEmpty) {
        if (!avatar.startsWith('http')) {
          try {
            avatar = await StorageService.getSignedUrl(avatar);
          } catch (_) {}
        }
        await AvatarCache.setForUserId(userId, avatar);
      }
      posts.add(
        Post(
          id: d.$id,
          username: data['username'] as String? ?? 'No Name',
          userAvatar: data['userAvatar'] as String? ?? '',
          content: data['content'] as String? ?? '',
          textBgColor: data['textBgColor'] as int?,
          timestamp: DateTime.tryParse(d.$createdAt) ??
              (data['createdAt'] != null
                  ? DateTime.tryParse(data['createdAt'] as String? ?? '') ??
                      DateTime.now()
                  : DateTime.now()),
          likes: data['likes'] as int? ?? 0,
          comments: data['comments'] as int? ?? 0,
          reposts: data['reposts'] as int? ?? 0,
          impressions: data['impressions'] as int? ?? 0,
          views: data['views'] as int? ?? 0,
          imageUrl: firstImage,
          videoUrl: videoUrl,
          postType: postType,
          title: title,
          thumbnailUrl: thumbnailUrl,
        ),
      );
    }

    FeedCache.forYouPosts = posts;
    FeedCache.mediaByPostId = mediaByPostId;
    FeedCache.authorByPostId = authorByPostId;
    FeedCache.forYouCursor = feedPage.nextCursor;
  }

  static Future<void> _preloadFollowing(List<String> followingIds) async {
    if (FeedCache.hasFollowing) return;

    final feedPage = await BackendService.fetchPostsByUserIdsPage(
      followingIds,
      limit: 40,
      sessionSeed: _sessionSeed,
    );
    final List<aw.Row> docs = feedPage.rows;
    if (docs.isEmpty) return;

    final posts = <Post>[];
    final mediaByPostId = FeedCache.mediaByPostId;
    final authorByPostId = FeedCache.authorByPostId;

    for (final d in docs) {
      final data = d.data;
      final List<String> rawMedia = data['mediaUrls'] is List
          ? (data['mediaUrls'] as List).map((item) => item.toString()).toList()
          : <String>[];
      authorByPostId[d.$id] = data['userId'] as String? ?? '';
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
            ? (thumbnailUrl!.startsWith('http')
                ? await StorageService.getImageDisplayUrl(thumbnailUrl)
                : await StorageService.getImageDisplayUrl(thumbnailUrl))
            : (rawMedia.length > 1
                ? await StorageService.getImageDisplayUrl(rawMedia[1])
                : null);
        mediaForUi = firstImage != null ? <String>[firstImage] : <String>[];
      } else {
        firstImage = thumbnailUrl?.isNotEmpty == true
            ? (thumbnailUrl!.startsWith('http')
                ? await StorageService.getImageDisplayUrl(thumbnailUrl)
                : await StorageService.getImageDisplayUrl(thumbnailUrl))
            : (rawMedia.isNotEmpty
                ? await StorageService.getImageDisplayUrl(rawMedia.first)
                : null);
        mediaForUi = <String>[];
        for (final media in rawMedia) {
          mediaForUi.add(await StorageService.getImageDisplayUrl(media));
        }
      }

      mediaByPostId[d.$id] = mediaForUi;

      // Warm avatar cache for following feed as well.
      final userId = data['userId'] as String? ?? '';
      String avatar = data['userAvatar'] as String? ?? '';
      if (userId.isNotEmpty && avatar.isNotEmpty) {
        if (!avatar.startsWith('http')) {
          try {
            avatar = await StorageService.getSignedUrl(avatar);
          } catch (_) {}
        }
        await AvatarCache.setForUserId(userId, avatar);
      }
      posts.add(
        Post(
          id: d.$id,
          username: data['username'] as String? ?? 'No Name',
          userAvatar: data['userAvatar'] as String? ?? '',
          content: data['content'] as String? ?? '',
          textBgColor: data['textBgColor'] as int?,
          timestamp: DateTime.tryParse(d.$createdAt) ??
              (data['createdAt'] != null
                  ? DateTime.tryParse(data['createdAt'] as String? ?? '') ??
                      DateTime.now()
                  : DateTime.now()),
          likes: data['likes'] as int? ?? 0,
          comments: data['comments'] as int? ?? 0,
          reposts: data['reposts'] as int? ?? 0,
          impressions: data['impressions'] as int? ?? 0,
          views: data['views'] as int? ?? 0,
          imageUrl: firstImage,
          videoUrl: videoUrl,
          postType: postType,
          title: title,
          thumbnailUrl: thumbnailUrl,
        ),
      );
    }

    FeedCache.followingPosts = posts;
    FeedCache.mediaByPostId = mediaByPostId;
    FeedCache.authorByPostId = authorByPostId;
    FeedCache.followingCursor = feedPage.nextCursor;
  }
}

