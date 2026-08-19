import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/backend_service.dart';
import '../services/storage_service.dart';

class SeriesHeaderEditorScreen extends StatefulWidget {
  const SeriesHeaderEditorScreen({
    super.key,
    required this.seriesTitle,
    required this.ownerUserId,
    required this.contentType,
  });

  final String seriesTitle;
  final String ownerUserId;
  final String contentType;

  @override
  State<SeriesHeaderEditorScreen> createState() =>
      _SeriesHeaderEditorScreenState();
}

class _SeriesHeaderEditorScreenState extends State<SeriesHeaderEditorScreen> {
  final ImagePicker _picker = ImagePicker();
  late final TextEditingController _headerTextController;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _currentCoverPath;
  String? _currentCoverPreviewUrl;

  @override
  void initState() {
    super.initState();
    _headerTextController = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final data = await BackendService.fetchSeriesHeaderData(
        userId: widget.ownerUserId,
        seriesTitle: widget.seriesTitle,
        contentType: widget.contentType,
      );
      if (!mounted) return;
      final rawCover = (data?['seriesCoverUrl'] as String?)?.trim();
      final previewCover = rawCover == null || rawCover.isEmpty
          ? null
          : rawCover.startsWith('http')
              ? rawCover
              : await StorageService.getImageDisplayUrl(rawCover);
      setState(() {
        _currentCoverPath = rawCover;
        _currentCoverPreviewUrl = previewCover;
        _headerTextController.text =
            (data?['seriesHeaderText'] as String?) ?? '';
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load series header.')),
      );
    }
  }

  @override
  void dispose() {
    _headerTextController.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _isSaving = true);
    try {
      final oldCover = _currentCoverPath;
      final file = File(picked.path);
      final ext = file.path.contains('.') ? file.path.split('.').last : 'png';
      final safeTitle = widget.seriesTitle
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      final key =
          'videos/${widget.ownerUserId}/series_${safeTitle.isEmpty ? 'cover' : safeTitle}_cover.$ext';
      final stored = await StorageService.uploadFileAtPath(file, key);
      final previewUrl = stored.startsWith('http')
          ? stored
          : await StorageService.getImageDisplayUrl(stored);
      await BackendService.updateSeriesHeader(
        userId: widget.ownerUserId,
        seriesTitle: widget.seriesTitle,
        contentType: widget.contentType,
        seriesCoverUrl: stored,
        seriesHeaderText: _headerTextController.text.trim(),
      );
      if (oldCover != null && oldCover != stored) {
        try {
          await StorageService.deleteFile(oldCover);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _currentCoverPath = stored;
        _currentCoverPreviewUrl = previewUrl;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Series cover updated.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update series cover.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveHeaderText() async {
    setState(() => _isSaving = true);
    try {
      await BackendService.updateSeriesHeader(
        userId: widget.ownerUserId,
        seriesTitle: widget.seriesTitle,
        contentType: widget.contentType,
        seriesCoverUrl: _currentCoverPath,
        seriesHeaderText: _headerTextController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Series header updated.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update series header.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Series Header'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                _HeaderPreview(
                  seriesTitle: widget.seriesTitle,
                  headerText: _headerTextController.text.trim(),
                  coverUrl: _currentCoverPreviewUrl,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: theme.dividerColor.withOpacity(0.6),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shared series header',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This cover and intro text appear on the public page for the whole series.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isSaving ? null : _pickCover,
                          icon: const Icon(Icons.image_rounded),
                          label: const Text('Replace series cover'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _headerTextController,
                        maxLines: 5,
                        minLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Series header text',
                          labelStyle: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceVariant
                              .withOpacity(0.25),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isSaving ? null : _saveHeaderText,
                          icon: const Icon(Icons.save_rounded),
                          label: const Text('Save header text'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _HeaderPreview extends StatelessWidget {
  const _HeaderPreview({
    required this.seriesTitle,
    required this.headerText,
    required this.coverUrl,
  });

  final String seriesTitle;
  final String headerText;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 270,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: theme.colorScheme.surfaceContainerHighest,
        image: coverUrl != null && coverUrl!.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(coverUrl!),
                fit: BoxFit.cover,
              )
            : null,
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
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Public preview',
              style: TextStyle(
                color: Colors.white.withOpacity(0.88),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              seriesTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            if (headerText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                headerText,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

