import 'package:xapzap/models/database_models.dart' as aw;
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../services/backend_service.dart';
import '../services/storage_service.dart';
import 'reel_detail_screen.dart';
import 'video_detail_screen.dart';

class SeriesPageScreen extends StatefulWidget {
  const SeriesPageScreen({
    super.key,
    required this.seriesTitle,
    required this.ownerUserId,
    required this.contentType,
  });

  final String seriesTitle;
  final String ownerUserId;
  final String contentType;

  @override
  State<SeriesPageScreen> createState() => _SeriesPageScreenState();
}

class _SeriesPageScreenState extends State<SeriesPageScreen> {
  bool _isLoading = true;
  List<_SeriesPageItem> _episodes = <_SeriesPageItem>[];
  Map<String, dynamic>? _headerData;

  @override
  void initState() {
    super.initState();
    _loadEpisodes();
  }

  Future<void> _loadEpisodes() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait<dynamic>([
        BackendService.fetchSeriesEpisodeRows(
          userId: widget.ownerUserId,
          seriesTitle: widget.seriesTitle,
          contentType: widget.contentType,
        ),
        BackendService.fetchSeriesHeaderData(
          userId: widget.ownerUserId,
          seriesTitle: widget.seriesTitle,
          contentType: widget.contentType,
        ),
      ]);
      final rows = results[0] as List<aw.Row>;
      final header = results[1] as Map<String, dynamic>?;
      final resolvedHeader = <String, dynamic>{};
      if (header != null) {
        resolvedHeader.addAll(header);
        final rawCover = (header['seriesCoverUrl'] as String?)?.trim();
        if (rawCover != null &&
            rawCover.isNotEmpty &&
            !rawCover.startsWith('http')) {
          resolvedHeader['seriesCoverUrl'] =
              await StorageService.getImageDisplayUrl(rawCover);
        }
      }
      final items = await Future.wait(rows.map(_mapItem));
      if (!mounted) return;
      setState(() {
        _episodes = items;
        _headerData = resolvedHeader.isEmpty ? header : resolvedHeader;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<_SeriesPageItem> _mapItem(aw.Row row) async {
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
    return _SeriesPageItem(
      post: Post(
        id: row.$id,
        username: (data['displayName'] as String?)?.trim().isNotEmpty == true
            ? (data['displayName'] as String).trim()
            : ((data['username'] as String?)?.trim() ?? ''),
        userAvatar: (data['userAvatar'] as String?) ?? '',
        content:
            ((data['episodeDescription'] as String?)?.trim().isNotEmpty == true)
                ? (data['episodeDescription'] as String).trim()
                : ((data['content'] as String?) ?? ''),
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
      subtitle: ((data['episodeDescription'] as String?) ?? '').trim(),
    );
  }

  void _openEpisode(_SeriesPageItem item) {
    final isReel = (item.post.postType ?? '').toLowerCase().contains('reel');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => isReel
            ? ReelDetailScreen(
                post: item.post,
                authorId: item.authorId,
                initialAuthorName: item.post.username,
                initialAuthorAvatarUrl: item.post.userAvatar,
              )
            : VideoDetailScreen(
                post: item.post,
                authorId: item.authorId,
                autoPlay: true,
              ),
      ),
    );
  }

  void _openFirstEpisode() {
    if (_episodes.isEmpty) return;
    _openEpisode(_episodes.first);
  }

  void _continueSeries() {
    if (_episodes.isEmpty) return;
    _openEpisode(_episodes.last);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerCover = _headerData?['seriesCoverUrl'] as String?;
    final headerText =
        (_headerData?['seriesHeaderText'] as String?)?.trim() ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Series Page')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                Container(
                  height: 290,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    color: theme.colorScheme.surfaceContainerHighest,
                    image: headerCover != null && headerCover.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(headerCover),
                            fit: BoxFit.cover,
                          )
                        : null,
                    border:
                        Border.all(color: theme.dividerColor.withOpacity(0.5)),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.12),
                          Colors.black.withOpacity(0.72),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          widget.seriesTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          headerText.isNotEmpty
                              ? headerText
                              : 'Browse every episode in order from a dedicated native series screen.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed:
                                    _episodes.isEmpty ? null : _continueSeries,
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Continue series'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _episodes.isEmpty
                                    ? null
                                    : _openFirstEpisode,
                                icon: const Icon(Icons.skip_next_rounded),
                                label: const Text('Start from Episode 1'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ..._episodes.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () => _openEpisode(item),
                      borderRadius: BorderRadius.circular(22),
                      child: Ink(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: theme.dividerColor.withOpacity(0.55),
                          ),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: SizedBox(
                                width: 88,
                                height: 108,
                                child: item.post.thumbnailUrl != null &&
                                        item.post.thumbnailUrl!.isNotEmpty
                                    ? Image.network(
                                        item.post.thumbnailUrl!,
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        color: theme.colorScheme
                                            .surfaceContainerHighest,
                                        alignment: Alignment.center,
                                        child: const Icon(
                                          Icons.play_circle_fill_rounded,
                                          size: 28,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Episode ${item.episodeNumber}',
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.post.title?.trim().isNotEmpty == true
                                        ? item.post.title!.trim()
                                        : 'Episode ${item.episodeNumber}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (item.subtitle.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      item.subtitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SeriesPageItem {
  const _SeriesPageItem({
    required this.post,
    required this.authorId,
    required this.episodeNumber,
    required this.subtitle,
  });

  final Post post;
  final String? authorId;
  final int episodeNumber;
  final String subtitle;
}

