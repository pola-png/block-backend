import 'package:appwrite/models.dart' as models;
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../services/appwrite_service.dart';
import '../services/storage_service.dart';
import '../widgets/series_episode_tray.dart';
import '../widgets/reel_player.dart';

class ReelDetailScreen extends StatefulWidget {
  final Post post;
  final bool isGuest;
  final VoidCallback? onGuestAction;
  final String? authorId;
  final bool enableAds;
  final String? initialResolvedVideoUrl;
  final String? initialAuthorName;
  final String? initialAuthorAvatarUrl;

  const ReelDetailScreen({
    super.key,
    required this.post,
    this.isGuest = false,
    this.onGuestAction,
    this.authorId,
    this.enableAds = true,
    this.initialResolvedVideoUrl,
    this.initialAuthorName,
    this.initialAuthorAvatarUrl,
  });

  @override
  State<ReelDetailScreen> createState() => _ReelDetailScreenState();
}

class _ReelDetailScreenState extends State<ReelDetailScreen> {
  late Post _currentPost;
  String? _currentAuthorId;
  String? _currentAuthorName;
  String? _currentAuthorAvatarUrl;
  Post? _nextEpisode;
  String? _nextEpisodeAuthorId;
  Map<String, dynamic>? _episodeMeta;

  @override
  void initState() {
    super.initState();
    _currentPost = widget.post;
    _currentAuthorId = widget.authorId;
    _currentAuthorName = widget.initialAuthorName;
    _currentAuthorAvatarUrl = widget.initialAuthorAvatarUrl;
    _loadEpisodeMeta();
    _loadNextEpisode();
  }

  Future<void> _loadEpisodeMeta() async {
    try {
      final meta = await AppwriteService.fetchEpisodeMetadata(_currentPost.id);
      if (!mounted) return;
      setState(() {
        _episodeMeta = meta['isEpisode'] == true ? meta : null;
      });
    } catch (_) {}
  }

  Future<void> _loadNextEpisode() async {
    try {
      final meta = await AppwriteService.fetchEpisodeMetadata(_currentPost.id);
      if (meta['isEpisode'] != true) {
        if (!mounted) return;
        setState(() {
          _nextEpisode = null;
          _nextEpisodeAuthorId = null;
        });
        return;
      }
      final userId = (meta['userId'] as String?)?.trim() ?? '';
      final seriesTitle = (meta['seriesTitle'] as String?)?.trim() ?? '';
      final episodeNumber = meta['episodeNumber'] as int?;
      final contentType = ((meta['episodeContentType'] as String?) ?? 'reel')
          .trim()
          .toLowerCase();
      if (userId.isEmpty ||
          seriesTitle.isEmpty ||
          episodeNumber == null ||
          contentType.isEmpty) {
        if (!mounted) return;
        setState(() {
          _nextEpisode = null;
          _nextEpisodeAuthorId = null;
        });
        return;
      }

      final nextRow = await AppwriteService.fetchNextEpisodeRow(
        userId: userId,
        seriesTitle: seriesTitle,
        currentEpisodeNumber: episodeNumber,
        contentType: contentType,
      );
      if (nextRow == null) {
        if (!mounted) return;
        setState(() {
          _nextEpisode = null;
          _nextEpisodeAuthorId = null;
        });
        return;
      }
      final mapped = await _mapRowToPost(nextRow);
      if (!mounted) return;
      setState(() {
        _nextEpisode = mapped;
        _nextEpisodeAuthorId = (nextRow.data['userId'] as String?)?.trim();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _nextEpisode = null;
        _nextEpisodeAuthorId = null;
      });
    }
  }

  Future<Post> _mapRowToPost(models.Row row) async {
    final data = row.data;
    final List<String> rawMedia = data['mediaUrls'] is List
        ? (data['mediaUrls'] as List).map((item) => item.toString()).toList()
        : <String>[];
    final postType = (data['postType'] as String?)?.trim();
    final title = (data['episodeTitle'] as String?)?.trim().isNotEmpty == true
        ? (data['episodeTitle'] as String).trim()
        : (data['title'] as String?)?.trim();
    final rawThumb = (data['thumbnailUrl'] as String?)?.trim();
    final postTypeLower = (postType ?? '').toLowerCase();
    final isVideoPost =
        postTypeLower.contains('video') || postTypeLower.contains('reel');

    String? videoUrl;
    String? previewVideoUrl;
    String? hlsVideoUrl;
    String? thumbnailUrl;
    String? imageUrl;

    if (rawThumb != null && rawThumb.isNotEmpty) {
      thumbnailUrl = rawThumb.startsWith('http')
          ? rawThumb
          : await StorageService.getImageDisplayUrl(rawThumb);
    }

    if (isVideoPost && rawMedia.isNotEmpty) {
      final first = rawMedia.first;
      videoUrl = first.startsWith('http')
          ? first
          : await StorageService.getVideoDisplayUrl(first);
      previewVideoUrl = (data['previewVideoUrl'] as String?)?.trim();
      hlsVideoUrl = (data['hlsVideoUrl'] as String?)?.trim();
      imageUrl = thumbnailUrl;
    } else if (rawMedia.isNotEmpty) {
      imageUrl = rawMedia.first.startsWith('http')
          ? rawMedia.first
          : await StorageService.getImageDisplayUrl(rawMedia.first);
    }

    return Post(
      id: row.$id,
      username: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? (data['displayName'] as String).trim()
          : ((data['username'] as String?)?.trim() ?? ''),
      userAvatar: (data['userAvatar'] as String?) ?? '',
      content:
          (data['episodeDescription'] as String?)?.trim().isNotEmpty == true
              ? (data['episodeDescription'] as String).trim()
              : ((data['content'] as String?) ?? ''),
      imageUrl: imageUrl,
      videoUrl: videoUrl,
      previewVideoUrl:
          previewVideoUrl?.isNotEmpty == true ? previewVideoUrl : null,
      hlsVideoUrl: hlsVideoUrl?.isNotEmpty == true ? hlsVideoUrl : null,
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
      sourcePostId: data['sourcePostId'] as String?,
      sourceUserId: data['sourceUserId'] as String?,
      sourceUsername: data['sourceUsername'] as String?,
    );
  }

  Future<void> _playNextEpisode() async {
    final nextEpisode = _nextEpisode;
    if (nextEpisode == null) return;
    final nextAuthorId = _nextEpisodeAuthorId;
    setState(() {
      _currentPost = nextEpisode;
      _currentAuthorId = nextAuthorId;
      _currentAuthorName = nextEpisode.username;
      _currentAuthorAvatarUrl = nextEpisode.userAvatar;
      _nextEpisode = null;
      _nextEpisodeAuthorId = null;
    });
    await _loadEpisodeMeta();
    await _loadNextEpisode();
  }

  @override
  Widget build(BuildContext context) {
    return ReelPlayer(
      key: ValueKey<String>(_currentPost.id),
      post: _currentPost,
      isGuest: widget.isGuest,
      onGuestAction: widget.onGuestAction,
      authorId: _currentAuthorId,
      enableAds: widget.enableAds,
      isActive: true,
      isDetailSurface: true,
      initialResolvedVideoUrl: _currentPost.previewVideoUrl ??
          _currentPost.videoUrl ??
          _currentPost.hlsVideoUrl,
      initialAuthorName: _currentAuthorName ?? _currentPost.username,
      initialAuthorAvatarUrl:
          _currentAuthorAvatarUrl ?? _currentPost.userAvatar,
      nextEpisode: _nextEpisode,
      onPlayNextEpisode: _nextEpisode != null ? _playNextEpisode : null,
      bottomOverlay: _episodeMeta != null
          ? SeriesEpisodeTray(
              currentPostId: _currentPost.id,
              ownerUserId: ((_episodeMeta!['userId'] as String?) ?? '').trim(),
              seriesTitle:
                  ((_episodeMeta!['seriesTitle'] as String?) ?? '').trim(),
              contentType:
                  ((_episodeMeta!['episodeContentType'] as String?) ?? 'reel')
                      .trim()
                      .toLowerCase(),
              compact: true,
            )
          : null,
    );
  }
}

