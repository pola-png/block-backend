import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../models/post.dart';
import '../services/backend_service.dart';
import '../services/storage_service.dart';

class EpisodeMediaEditorScreen extends StatefulWidget {
  const EpisodeMediaEditorScreen({super.key, required this.post});

  final Post post;

  @override
  State<EpisodeMediaEditorScreen> createState() =>
      _EpisodeMediaEditorScreenState();
}

class _EpisodeMediaEditorScreenState extends State<EpisodeMediaEditorScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isArchived = false;
  bool _isEpisodeOne = false;
  String _ownerUserId = '';
  String _contentType = 'video';
  int _episodeNumber = 1;
  String? _currentVideoPath;
  String? _currentThumbnailPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final meta = await BackendService.fetchEpisodeMetadata(widget.post.id);
      final row = await BackendService.getRow(
        BackendService.postsCollectionId,
        widget.post.id,
      );
      if (!mounted) return;
      final mediaUrls = row.data['mediaUrls'] is List
          ? (row.data['mediaUrls'] as List)
              .map((item) => item.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList()
          : <String>[];
      setState(() {
        _ownerUserId = ((meta['userId'] as String?) ?? '').trim();
        _contentType = ((meta['episodeContentType'] as String?) ?? 'video')
            .trim()
            .toLowerCase();
        _episodeNumber = (meta['episodeNumber'] as int?) ?? 1;
        _isEpisodeOne = _episodeNumber == 1;
        _isArchived = row.data['isArchived'] == true ||
            '${row.data['isArchived']}'.toLowerCase() == 'true';
        _currentVideoPath = mediaUrls.isNotEmpty ? mediaUrls.first : null;
        _currentThumbnailPath =
            (row.data['thumbnailUrl'] as String?)?.trim().isNotEmpty == true
                ? (row.data['thumbnailUrl'] as String).trim()
                : null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load episode media.')),
      );
    }
  }

  Future<void> _replaceVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    final validator = VideoPlayerController.file(File(picked.path));
    try {
      await validator.initialize();
      final size = validator.value.size;
      final isVertical = size.height > size.width;
      await validator.dispose();
      if (_contentType == 'video' && isVertical) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video episodes use horizontal clips.'),
          ),
        );
        return;
      }
      if (_contentType == 'reel' && !isVertical) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reel episodes use vertical clips.'),
          ),
        );
        return;
      }
    } catch (_) {
      try {
        await validator.dispose();
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to validate selected video.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final oldVideo = _currentVideoPath;
      final file = File(picked.path);
      final ext = file.path.contains('.') ? file.path.split('.').last : 'mp4';
      final key = 'videos/$_ownerUserId/episode_${widget.post.id}_video.$ext';
      final stored = await StorageService.uploadFileAtPath(file, key);
      await BackendService.updateRow(
        BackendService.postsCollectionId,
        widget.post.id,
        <String, dynamic>{
          'mediaUrls': [stored],
        },
      );
      if (oldVideo != null && oldVideo != stored) {
        try {
          await StorageService.deleteFile(oldVideo);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _currentVideoPath = stored;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video replaced.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to replace video.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _replaceThumbnail() async {
    if (!_isEpisodeOne) return;
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _isSaving = true);
    try {
      final oldThumb = _currentThumbnailPath;
      final file = File(picked.path);
      final ext = file.path.contains('.') ? file.path.split('.').last : 'png';
      final key = 'videos/$_ownerUserId/episode_${widget.post.id}_thumb.$ext';
      final stored = await StorageService.uploadFileAtPath(file, key);
      await BackendService.updateRow(
        BackendService.postsCollectionId,
        widget.post.id,
        <String, dynamic>{
          'thumbnailUrl': stored,
          if (_isEpisodeOne) 'seriesThumbnailUrl': stored,
        },
      );
      if (oldThumb != null && oldThumb != stored) {
        try {
          await StorageService.deleteFile(oldThumb);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _currentThumbnailPath = stored;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thumbnail replaced.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to replace thumbnail.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _toggleArchive() async {
    setState(() => _isSaving = true);
    try {
      await BackendService.archivePost(widget.post.id, archived: !_isArchived);
      if (!mounted) return;
      setState(() => _isArchived = !_isArchived);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(_isArchived ? 'Episode archived.' : 'Episode restored.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update archive state.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteEpisode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete episode'),
        content: const Text(
          'This will permanently delete the episode and its media. This cannot be undone.',
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
    setState(() => _isSaving = true);
    try {
      if (_currentVideoPath != null) {
        try {
          await StorageService.deleteFile(_currentVideoPath!);
        } catch (_) {}
      }
      if (_currentThumbnailPath != null) {
        try {
          await StorageService.deleteFile(_currentThumbnailPath!);
        } catch (_) {}
      }
      await BackendService.deletePost(widget.post.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete episode.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Episode Media'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                _HeaderCard(
                  title: widget.post.title?.trim().isNotEmpty == true
                      ? widget.post.title!.trim()
                      : 'Episode $_episodeNumber',
                  subtitle:
                      'Replace the episode media, archive it, or remove it entirely.',
                ),
                const SizedBox(height: 16),
                _ActionSection(
                  title: 'Video',
                  body: _currentVideoPath?.isNotEmpty == true
                      ? 'Current clip is connected and ready to replace.'
                      : 'No video linked right now.',
                  trailing: FilledButton.icon(
                    onPressed: _isSaving ? null : _replaceVideo,
                    icon: const Icon(Icons.video_library_rounded),
                    label: const Text('Replace video'),
                  ),
                ),
                const SizedBox(height: 14),
                _ActionSection(
                  title: 'Thumbnail',
                  body: _isEpisodeOne
                      ? 'Episode 1 can carry the custom series thumbnail.'
                      : 'Thumbnail replacement is locked to Episode 1.',
                  trailing: OutlinedButton.icon(
                    onPressed:
                        !_isEpisodeOne || _isSaving ? null : _replaceThumbnail,
                    icon: const Icon(Icons.image_rounded),
                    label: Text(_isEpisodeOne
                        ? 'Replace thumbnail'
                        : 'Thumbnail locked'),
                  ),
                ),
                const SizedBox(height: 14),
                _ActionSection(
                  title: 'Visibility',
                  body: _isArchived
                      ? 'This episode is archived and hidden from the public series flow.'
                      : 'This episode is live in the public series flow.',
                  trailing: FilledButton.tonalIcon(
                    onPressed: _isSaving ? null : _toggleArchive,
                    icon: Icon(
                      _isArchived
                          ? Icons.unarchive_rounded
                          : Icons.archive_rounded,
                    ),
                    label: Text(_isArchived ? 'Restore' : 'Archive'),
                  ),
                ),
                const SizedBox(height: 14),
                _ActionSection(
                  title: 'Danger zone',
                  body: 'This permanently removes the episode and media files.',
                  trailing: TextButton.icon(
                    onPressed: _isSaving ? null : _deleteEpisode,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text(
                      'Delete episode',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withOpacity(0.16),
            theme.colorScheme.surfaceContainerHighest,
          ],
        ),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Episode Media',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionSection extends StatelessWidget {
  const _ActionSection({
    required this.title,
    required this.body,
    required this.trailing,
  });

  final String title;
  final String body;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          trailing,
        ],
      ),
    );
  }
}

