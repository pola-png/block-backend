import 'package:xapzap/models/database_models.dart' as aw;
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../services/backend_service.dart';
import '../services/storage_service.dart';
import '../screens/reel_detail_screen.dart';
import '../screens/series_page_screen.dart';
import '../screens/video_detail_screen.dart';

class SeriesEpisodeTray extends StatefulWidget {
  const SeriesEpisodeTray({
    super.key,
    required this.currentPostId,
    required this.ownerUserId,
    required this.seriesTitle,
    required this.contentType,
    this.compact = false,
  });

  final String currentPostId;
  final String ownerUserId;
  final String seriesTitle;
  final String contentType;
  final bool compact;

  @override
  State<SeriesEpisodeTray> createState() => _SeriesEpisodeTrayState();
}

class _SeriesEpisodeTrayState extends State<SeriesEpisodeTray> {
  bool _isLoading = true;
  List<_TrayEpisode> _episodes = <_TrayEpisode>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await BackendService.fetchSeriesEpisodeRows(
        userId: widget.ownerUserId,
        seriesTitle: widget.seriesTitle,
        contentType: widget.contentType,
      );
      final mapped = await Future.wait(rows.map(_mapRow));
      if (!mounted) return;
      setState(() {
        _episodes = mapped;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<_TrayEpisode> _mapRow(aw.Row row) async {
    final data = row.data;
    final rawMedia = data['mediaUrls'] is List
        ? (data['mediaUrls'] as List).map((item) => item.toString()).toList()
        : <String>[];
    final rawThumb = (data['thumbnailUrl'] as String?)?.trim() ?? '';
    String? thumb;
    if (rawThumb.isNotEmpty) {
      thumb = rawThumb.startsWith('http')
          ? rawThumb
          : await StorageService.getImageDisplayUrl(rawThumb);
    }
    String? videoUrl;
    if (rawMedia.isNotEmpty) {
      final first = rawMedia.first;
      videoUrl = first.startsWith('http')
          ? first
          : await StorageService.getVideoDisplayUrl(first);
    }
    final number = data['episodeNumber'] is int
        ? data['episodeNumber'] as int
        : int.tryParse('${data['episodeNumber']}') ?? 0;
    return _TrayEpisode(
      post: Post(
        id: row.$id,
        username: (data['username'] as String?)?.trim() ?? '',
        userAvatar: (data['userAvatar'] as String?) ?? '',
        content: ((data['episodeDescription'] as String?) ?? '').trim(),
        imageUrl: thumb,
        videoUrl: videoUrl,
        postType: (data['postType'] as String?)?.trim(),
        title: ((data['episodeTitle'] as String?)?.trim().isNotEmpty == true)
            ? (data['episodeTitle'] as String).trim()
            : (data['title'] as String?),
        thumbnailUrl: thumb,
        timestamp: DateTime.tryParse(row.$createdAt) ?? DateTime.now(),
        likes: data['likes'] as int? ?? 0,
        comments: data['comments'] as int? ?? 0,
        reposts: data['reposts'] as int? ?? 0,
        impressions: data['impressions'] as int? ?? 0,
        views: data['views'] as int? ?? 0,
      ),
      authorId: (data['userId'] as String?)?.trim(),
      episodeNumber: number,
    );
  }

  void _openSeriesPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SeriesPageScreen(
          seriesTitle: widget.seriesTitle,
          ownerUserId: widget.ownerUserId,
          contentType: widget.contentType,
        ),
      ),
    );
  }

  void _openEpisode(_TrayEpisode episode) {
    final isReel = (episode.post.postType ?? '').toLowerCase().contains('reel');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => isReel
            ? ReelDetailScreen(
                post: episode.post,
                authorId: episode.authorId,
                initialAuthorName: episode.post.username,
                initialAuthorAvatarUrl: episode.post.userAvatar,
              )
            : VideoDetailScreen(
                post: episode.post,
                authorId: episode.authorId,
                autoPlay: true,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_episodes.length <= 1) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final surface = widget.compact
        ? Colors.black.withOpacity(0.72)
        : theme.colorScheme.surface;
    return Container(
      margin: widget.compact ? EdgeInsets.zero : const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: widget.compact
              ? Colors.white.withOpacity(0.12)
              : theme.dividerColor.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'More Episodes',
                      style: TextStyle(
                        color: widget.compact
                            ? Colors.white
                            : theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.seriesTitle,
                      style: TextStyle(
                        color: widget.compact
                            ? Colors.white.withOpacity(0.72)
                            : theme.colorScheme.onSurfaceVariant,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _openSeriesPage,
                child: const Text('Open series'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _episodes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final item = _episodes[index];
                final isCurrent = item.post.id == widget.currentPostId;
                return GestureDetector(
                  onTap: isCurrent ? null : () => _openEpisode(item),
                  child: SizedBox(
                    width: 118,
                    child: Opacity(
                      opacity: isCurrent ? 0.65 : 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Stack(
                              children: [
                                SizedBox(
                                  width: 118,
                                  height: 94,
                                  child: item.post.thumbnailUrl != null &&
                                          item.post.thumbnailUrl!.isNotEmpty
                                      ? Image.network(
                                          item.post.thumbnailUrl!,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          color: widget.compact
                                              ? Colors.white.withOpacity(0.08)
                                              : theme.colorScheme
                                                  .surfaceContainerHighest,
                                          alignment: Alignment.center,
                                          child: Icon(
                                            Icons.play_circle_fill_rounded,
                                            color: widget.compact
                                                ? Colors.white
                                                : theme.colorScheme.primary,
                                          ),
                                        ),
                                ),
                                Positioned(
                                  left: 8,
                                  top: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.68),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'EP ${item.episodeNumber}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.post.title?.trim().isNotEmpty == true
                                ? item.post.title!.trim()
                                : 'Episode ${item.episodeNumber}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.compact
                                  ? Colors.white
                                  : theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TrayEpisode {
  const _TrayEpisode({
    required this.post,
    required this.authorId,
    required this.episodeNumber,
  });

  final Post post;
  final String? authorId;
  final int episodeNumber;
}

