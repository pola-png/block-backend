import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/upload_type.dart';
import '../services/backend_service.dart';
import 'episode_media_editor_screen.dart';
import 'series_studio_screen.dart';
import 'series_page_screen.dart';
import 'upload_screen.dart';

class EpisodeEditorScreen extends StatefulWidget {
  const EpisodeEditorScreen({super.key, required this.post});

  final Post post;

  @override
  State<EpisodeEditorScreen> createState() => _EpisodeEditorScreenState();
}

class _EpisodeEditorScreenState extends State<EpisodeEditorScreen> {
  late final TextEditingController _seriesTitleController;
  late final TextEditingController _episodeNumberController;
  late final TextEditingController _episodeTitleController;
  late final TextEditingController _episodeDescriptionController;
  bool _isSaving = false;
  bool _isLoading = true;
  String _episodeContentType = 'video';
  String _ownerUserId = '';

  @override
  void initState() {
    super.initState();
    _seriesTitleController = TextEditingController();
    _episodeNumberController = TextEditingController(text: '1');
    _episodeTitleController = TextEditingController();
    _episodeDescriptionController = TextEditingController();
    _loadEpisodeState();
  }

  Future<void> _loadEpisodeState() async {
    setState(() => _isLoading = true);
    try {
      final meta = await BackendService.fetchEpisodeMetadata(widget.post.id);
      if (!mounted) return;
      _episodeContentType = ((meta['episodeContentType'] as String?) ?? 'video')
          .trim()
          .toLowerCase();
      _ownerUserId = ((meta['userId'] as String?) ?? '').trim();
      _seriesTitleController.text = (meta['seriesTitle'] as String?) ?? '';
      _episodeNumberController.text = '${(meta['episodeNumber'] as int?) ?? 1}';
      _episodeTitleController.text =
          (meta['episodeTitle'] as String?)?.trim().isNotEmpty == true
              ? (meta['episodeTitle'] as String).trim()
              : (widget.post.title ?? '');
      _episodeDescriptionController.text =
          (meta['episodeDescription'] as String?)?.trim().isNotEmpty == true
              ? (meta['episodeDescription'] as String).trim()
              : widget.post.content;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _seriesTitleController.dispose();
    _episodeNumberController.dispose();
    _episodeTitleController.dispose();
    _episodeDescriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final description = _episodeDescriptionController.text.trim();
    if (description.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await BackendService.updateRow(
        BackendService.postsCollectionId,
        widget.post.id,
        <String, dynamic>{
          'content': description,
          'title': _episodeTitleController.text.trim(),
          'seriesTitle': _seriesTitleController.text.trim(),
          'episodeNumber':
              int.tryParse(_episodeNumberController.text.trim()) ?? 1,
          'episodeTitle': _episodeTitleController.text.trim(),
          'episodeDescription': description,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update episode. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _addNextEpisode() async {
    final nextEpisodeNumber =
        (int.tryParse(_episodeNumberController.text.trim()) ?? 0) + 1;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UploadScreen(
          type: UploadType.episode,
          initialEpisodeSeriesTitle: _seriesTitleController.text.trim(),
          initialEpisodeNumber: nextEpisodeNumber <= 0 ? 1 : nextEpisodeNumber,
        ),
      ),
    );
  }

  Future<void> _openSeriesStudio() async {
    final title = _seriesTitleController.text.trim();
    if (title.isEmpty || _ownerUserId.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SeriesStudioScreen(
          post: widget.post,
          seriesTitle: title,
          ownerUserId: _ownerUserId,
          contentType: _episodeContentType,
        ),
      ),
    );
  }

  Future<void> _openPublicSeriesPage() async {
    final title = _seriesTitleController.text.trim();
    if (title.isEmpty || _ownerUserId.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SeriesPageScreen(
          seriesTitle: title,
          ownerUserId: _ownerUserId,
          contentType: _episodeContentType,
        ),
      ),
    );
  }

  Future<void> _openMediaEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EpisodeMediaEditorScreen(post: widget.post),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Episode Studio'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      14,
                      16,
                      24 + MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _HeroSection(contentType: _episodeContentType),
                          const SizedBox(height: 16),
                          _SectionCard(
                            title: 'Episode Details',
                            subtitle:
                                'This is the main editing surface for the current episode.',
                            child: Column(
                              children: [
                                TextField(
                                  controller: _seriesTitleController,
                                  decoration: _inputDecoration(
                                    theme,
                                    label: 'Series title',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: TextField(
                                        controller: _episodeNumberController,
                                        keyboardType: TextInputType.number,
                                        decoration: _inputDecoration(
                                          theme,
                                          label: 'Episode number',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 5,
                                      child: TextField(
                                        controller: _episodeTitleController,
                                        decoration: _inputDecoration(
                                          theme,
                                          label: 'Episode title',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _episodeDescriptionController,
                                  maxLines: 7,
                                  minLines: 5,
                                  decoration: _inputDecoration(
                                    theme,
                                    label: 'Episode description',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _SectionCard(
                            title: 'Series Actions',
                            subtitle:
                                'Keep the flow moving without going back to the generic create menu.',
                            child: Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _openPublicSeriesPage,
                                    icon: const Icon(Icons.public_rounded),
                                    label:
                                        const Text('Open public series page'),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: _openMediaEditor,
                                    icon: const Icon(Icons.tune_rounded),
                                    label:
                                        const Text('Replace video / thumbnail'),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _openSeriesStudio,
                                    icon: const Icon(Icons.view_list_rounded),
                                    label: const Text('Open series studio'),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: _addNextEpisode,
                                    icon: const Icon(Icons.add_circle_outline),
                                    label: const Text('Add next episode'),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceVariant
                                        .withOpacity(0.22),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Text(
                                    'Thumbnail rule: only Episode 1 should carry the custom series thumbnail. Later episodes keep generated previews.',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  InputDecoration _inputDecoration(
    ThemeData theme, {
    required String label,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      filled: true,
      fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.25),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      alignLabelWithHint: true,
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.contentType});

  final String contentType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withOpacity(0.18),
            theme.colorScheme.surfaceContainerHighest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Episode Studio',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A dedicated native editing surface for episodic content, with room for metadata and next-episode publishing.',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(
                  label:
                      contentType == 'reel' ? 'Reel Episode' : 'Video Episode'),
              const _Pill(label: 'Native screen'),
              const _Pill(label: 'Series flow'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

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
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.82),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
