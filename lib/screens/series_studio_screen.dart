import 'package:xapzap/models/database_models.dart' as aw;
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/upload_type.dart';
import '../services/backend_service.dart';
import '../services/storage_service.dart';
import 'episode_editor_screen.dart';
import 'episode_media_editor_screen.dart';
import 'series_header_editor_screen.dart';
import 'upload_screen.dart';

class SeriesStudioScreen extends StatefulWidget {
  const SeriesStudioScreen({
    super.key,
    required this.post,
    required this.seriesTitle,
    required this.ownerUserId,
    required this.contentType,
  });

  final Post post;
  final String seriesTitle;
  final String ownerUserId;
  final String contentType;

  @override
  State<SeriesStudioScreen> createState() => _SeriesStudioScreenState();
}

class _SeriesStudioScreenState extends State<SeriesStudioScreen> {
  bool _isLoading = true;
  bool _isSavingOrder = false;
  List<_SeriesEpisodeItem> _episodes = <_SeriesEpisodeItem>[];

  @override
  void initState() {
    super.initState();
    _loadEpisodes();
  }

  Future<void> _loadEpisodes() async {
    setState(() => _isLoading = true);
    try {
      final rows = await BackendService.fetchSeriesEpisodeRows(
        userId: widget.ownerUserId,
        seriesTitle: widget.seriesTitle,
        contentType: widget.contentType,
        includeArchived: true,
      );
      final mapped = await Future.wait(rows.map(_mapEpisodeRow));
      if (!mounted) return;
      setState(() {
        _episodes = mapped;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load series episodes.'),
        ),
      );
    }
  }

  Future<_SeriesEpisodeItem> _mapEpisodeRow(aw.Row row) async {
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
    String? rawVideoPath;
    if (rawMedia.isNotEmpty) {
      rawVideoPath = rawMedia.first;
    }
    final episodeNumber = data['episodeNumber'] is int
        ? data['episodeNumber'] as int
        : int.tryParse('${data['episodeNumber']}') ?? 0;
    final post = Post(
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
      videoUrl: rawMedia.isNotEmpty ? rawMedia.first : null,
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
    );
    return _SeriesEpisodeItem(
      post: post,
      rowId: row.$id,
      episodeNumber: episodeNumber,
      title: ((data['episodeTitle'] as String?)?.trim().isNotEmpty == true)
          ? (data['episodeTitle'] as String).trim()
          : ((data['title'] as String?)?.trim().isNotEmpty == true)
              ? (data['title'] as String).trim()
              : 'Episode $episodeNumber',
      subtitle:
          ((data['episodeDescription'] as String?)?.trim().isNotEmpty == true)
              ? (data['episodeDescription'] as String).trim()
              : ((data['content'] as String?) ?? '').trim(),
      thumbnailUrl: thumb,
      rawVideoPath: rawVideoPath,
      rawThumbnailPath: rawThumb.isNotEmpty ? rawThumb : null,
      isArchived: row.data['isArchived'] == true ||
          '${row.data['isArchived']}'.toLowerCase() == 'true',
    );
  }

  Future<void> _saveOrder() async {
    setState(() => _isSavingOrder = true);
    try {
      await BackendService.reorderSeriesEpisodes(
        postIdsInOrder: _episodes.map((item) => item.rowId).toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Episode order updated.')),
      );
      await _loadEpisodes();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save episode order.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingOrder = false);
      }
    }
  }

  Future<void> _addEpisode() async {
    final nextEpisodeNumber = _episodes.isEmpty
        ? 1
        : (_episodes
                .map((e) => e.episodeNumber)
                .reduce((a, b) => a > b ? a : b) +
            1);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UploadScreen(
          type: UploadType.episode,
          initialEpisodeSeriesTitle: widget.seriesTitle,
          initialEpisodeNumber: nextEpisodeNumber,
        ),
      ),
    );
    await _loadEpisodes();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Series Studio'),
        actions: [
          TextButton(
            onPressed: _isSavingOrder ? null : _saveOrder,
            child: _isSavingOrder
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Save order',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addEpisode,
        icon: const Icon(Icons.add),
        label: const Text('Add episode'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary.withOpacity(0.17),
                        theme.colorScheme.surfaceContainerHighest,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border:
                        Border.all(color: theme.dividerColor.withOpacity(0.45)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.seriesTitle,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Manage every episode in a dedicated native studio. Drag to reorder, then save the sequence safely.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SeriesHeaderEditorScreen(
                                  seriesTitle: widget.seriesTitle,
                                  ownerUserId: widget.ownerUserId,
                                  contentType: widget.contentType,
                                ),
                              ),
                            );
                            await _loadEpisodes();
                          },
                          icon: const Icon(Icons.photo_library_rounded),
                          label: const Text('Edit series header'),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                    itemCount: _episodes.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) {
                          newIndex -= 1;
                        }
                        final item = _episodes.removeAt(oldIndex);
                        _episodes.insert(newIndex, item);
                        for (var i = 0; i < _episodes.length; i++) {
                          _episodes[i] =
                              _episodes[i].copyWith(episodeNumber: i + 1);
                        }
                      });
                    },
                    itemBuilder: (context, index) {
                      final item = _episodes[index];
                      return Container(
                        key: ValueKey<String>(item.rowId),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: theme.dividerColor.withOpacity(0.6),
                          ),
                        ),
                        child: Row(
                          children: [
                            _EpisodeThumb(url: item.thumbnailUrl),
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
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (item.subtitle.isNotEmpty) ...[
                                    const SizedBox(height: 4),
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
                                  const SizedBox(height: 10),
                                  if (item.isArchived)
                                    _StatusPill(
                                      label: 'Archived',
                                      color: theme.colorScheme.error,
                                    ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) async {
                                switch (value) {
                                  case 'edit':
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => EpisodeEditorScreen(
                                          post: item.post,
                                        ),
                                      ),
                                    );
                                    await _loadEpisodes();
                                    break;
                                  case 'media':
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            EpisodeMediaEditorScreen(
                                          post: item.post,
                                        ),
                                      ),
                                    );
                                    await _loadEpisodes();
                                    break;
                                  case 'archive':
                                    await _toggleArchive(item);
                                    break;
                                  case 'delete':
                                    await _deleteEpisode(item);
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit episode'),
                                ),
                                const PopupMenuItem(
                                  value: 'media',
                                  child: Text('Replace media'),
                                ),
                                PopupMenuItem(
                                  value: 'archive',
                                  child: Text(
                                    item.isArchived ? 'Restore' : 'Archive',
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                              icon: Icon(
                                Icons.more_vert_rounded,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _toggleArchive(_SeriesEpisodeItem item) async {
    try {
      await BackendService.archivePost(
        item.rowId,
        archived: !item.isArchived,
      );
      await _loadEpisodes();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(item.isArchived ? 'Episode restored.' : 'Episode archived.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update archive state.')),
      );
    }
  }

  Future<void> _deleteEpisode(_SeriesEpisodeItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete episode'),
        content: const Text(
          'This permanently deletes the episode and its media. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (item.rawVideoPath != null) {
        try {
          await StorageService.deleteFile(item.rawVideoPath!);
        } catch (_) {}
      }
      if (item.rawThumbnailPath != null) {
        try {
          await StorageService.deleteFile(item.rawThumbnailPath!);
        } catch (_) {}
      }
      await BackendService.deletePost(item.rowId);
      await _loadEpisodes();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Episode deleted.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete episode.')),
      );
    }
  }
}

class _SeriesEpisodeItem {
  const _SeriesEpisodeItem({
    required this.post,
    required this.rowId,
    required this.episodeNumber,
    required this.title,
    required this.subtitle,
    required this.thumbnailUrl,
    required this.isArchived,
    required this.rawVideoPath,
    required this.rawThumbnailPath,
  });

  final Post post;
  final String rowId;
  final int episodeNumber;
  final String title;
  final String subtitle;
  final String? thumbnailUrl;
  final bool isArchived;
  final String? rawVideoPath;
  final String? rawThumbnailPath;

  _SeriesEpisodeItem copyWith({
    int? episodeNumber,
  }) {
    return _SeriesEpisodeItem(
      post: post,
      rowId: rowId,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      title: title,
      subtitle: subtitle,
      thumbnailUrl: thumbnailUrl,
      isArchived: isArchived,
      rawVideoPath: rawVideoPath,
      rawThumbnailPath: rawThumbnailPath,
    );
  }
}

class _EpisodeThumb extends StatelessWidget {
  const _EpisodeThumb({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 82,
        height: 102,
        child: url != null && url!.isNotEmpty
            ? Image.network(url!, fit: BoxFit.cover)
            : Container(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withOpacity(0.7),
                alignment: Alignment.center,
                child: const Icon(Icons.play_circle_fill_rounded, size: 28),
              ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
        ),
      ),
    );
  }
}

