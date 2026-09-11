import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../models/upload_type.dart';
import '../services/pending_upload_service.dart';
import '../services/backend_service.dart';

enum _VideoUploadStep { preview, details }

const int _regularUserVideoLimitSeconds = 180;

class UploadScreen extends StatefulWidget {
  final UploadType type;
  final XFile? initialVideo;
  final String? initialEpisodeSeriesTitle;
  final int? initialEpisodeNumber;
  final String? initialEpisodeTitle;
  final String? initialEpisodeDescription;

  const UploadScreen({
    super.key,
    required this.type,
    this.initialVideo,
    this.initialEpisodeSeriesTitle,
    this.initialEpisodeNumber,
    this.initialEpisodeTitle,
    this.initialEpisodeDescription,
  });

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _videoDescriptionController =
      TextEditingController();
  final TextEditingController _seriesTitleController = TextEditingController();
  final TextEditingController _episodeNumberController =
      TextEditingController(text: '1');
  final TextEditingController _episodeTitleController = TextEditingController();
  final TextEditingController _episodeDescriptionController =
      TextEditingController();
  final List<XFile> _selectedMedia = [];
  final ImagePicker _picker = ImagePicker();
  final List<Color> _textBgOptions = const [
    Color(0xFF0EA5E9), // sky
    Color(0xFF10B981), // green
    Color(0xFFF59E0B), // amber
    Color(0xFFE11D48), // rose
    Color(0xFF6366F1), // indigo
    Color(0xFF111827), // dark
  ];
  Color? _selectedTextBg;
  bool _isPosting = false;
  XFile? _selectedVideo;
  XFile? _selectedThumbnail;
  VideoPlayerController? _videoController;
  Future<void>? _videoInit;
  bool _isVideoPlaying = false;
  bool _isAdmin = false;
  Duration _videoDuration = Duration.zero;
  _VideoUploadStep _videoStep = _VideoUploadStep.preview;
  String? _episodePostType;
  bool _hasAttemptedInitialVideoPick = false;
  bool _isDescriptionExpanded = false;
  final Set<String> _bannedKeywords = const {
    'sex',
    'nude',
    'nudity',
    'porn',
    'xxx',
    'nsfw',
    'explicit',
  };

  bool _canUseBg() =>
      _selectedMedia.isEmpty &&
      _selectedTextBg != null &&
      _textController.text.length <= 50;

  bool _containsBannedText() {
    final combined =
        '${_titleController.text} ${_textController.text} ${_videoDescriptionController.text} ${_seriesTitleController.text} ${_episodeTitleController.text} ${_episodeDescriptionController.text}'
            .toLowerCase();
    for (final word in _bannedKeywords) {
      if (combined.contains(word)) return true;
    }
    return false;
  }

  bool get _isVideoFlow =>
      widget.type == UploadType.video ||
      widget.type == UploadType.reel ||
      widget.type == UploadType.episode;

  bool get _isEpisodeFlow => widget.type == UploadType.episode;

  bool get _requiresVerticalVideo => widget.type == UploadType.reel;

  bool get _requiresHorizontalVideo => widget.type == UploadType.video;

  int get _episodeNumber =>
      int.tryParse(_episodeNumberController.text.trim()) ?? 0;

  bool get _isEpisodeOne => _episodeNumber == 1;

  String get _resolvedVideoPostType {
    if (_isEpisodeFlow) {
      return _episodePostType ?? 'video';
    }
    return widget.type == UploadType.reel ? 'reel' : 'video';
  }

  bool get _canAdvanceVideoStep => _selectedVideo != null;

  bool get _canSubmitVideoPost {
    if (widget.type == UploadType.video) {
      return _selectedVideo != null && _titleController.text.trim().isNotEmpty;
    }
    return _selectedVideo != null && _textController.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _isVideoFlow
        ? (_videoStep == _VideoUploadStep.preview
            ? (widget.type == UploadType.reel
                ? 'Preview Reel'
                : widget.type == UploadType.episode
                    ? 'Preview Episode'
                    : 'Preview Video')
            : (widget.type == UploadType.reel
                ? 'Reel Details'
                : widget.type == UploadType.episode
                    ? 'Episode Details'
                    : 'Video Details'))
        : switch (widget.type) {
            UploadType.standard => 'New Post',
            UploadType.video => 'New Video',
            UploadType.reel => 'New Reel',
            UploadType.episode => 'New Episode',
            UploadType.news => 'News / Blog',
          };

    return WillPopScope(
      onWillPop: () async {
        if (_isVideoFlow && _videoStep == _VideoUploadStep.details) {
          setState(() => _videoStep = _VideoUploadStep.preview);
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        resizeToAvoidBottomInset: false,
        body: Container(
          constraints: const BoxConstraints(maxWidth: 768),
          child: Column(
            children: [
              _buildHeader(title),
              Expanded(child: _buildContentArea()),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadAdminStatus();
    if (_isEpisodeFlow) {
      _seriesTitleController.text = widget.initialEpisodeSeriesTitle ?? '';
      _episodeNumberController.text =
          '${widget.initialEpisodeNumber ?? 1}'.trim();
      _episodeTitleController.text = widget.initialEpisodeTitle ?? '';
      _episodeDescriptionController.text =
          widget.initialEpisodeDescription ?? '';
    }
    if (_isVideoFlow) {
      if (widget.initialVideo != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _applyPickedVideo(widget.initialVideo!);
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openInitialVideoPicker();
        });
      }
    }
  }

  Future<void> _loadAdminStatus() async {
    final isAdmin = await BackendService.isCurrentUserAdmin();
    if (mounted) {
      setState(() {
        _isAdmin = isAdmin;
      });
    } else {
      _isAdmin = isAdmin;
    }
  }

  Future<void> _openInitialVideoPicker() async {
    if (_hasAttemptedInitialVideoPick || !mounted) return;
    _hasAttemptedInitialVideoPick = true;
    await _pickVideo();
    if (!mounted || _selectedVideo != null) return;
    Navigator.of(context).maybePop();
  }

  Widget _buildHeader(String title) {
    final theme = Theme.of(context);
    final canStepBack = _isVideoFlow && _videoStep == _VideoUploadStep.details;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 44, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.96),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () {
              if (canStepBack) {
                setState(() => _videoStep = _VideoUploadStep.preview);
                return;
              }
              Navigator.pop(context);
            },
            child: Icon(LucideIcons.arrowLeft,
                size: 24, color: theme.colorScheme.onSurface),
          ),
          Text(
            title,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1DA1F2)),
          ),
          const SizedBox(width: 24),
        ],
      ),
    );
  }

  Widget _buildContentArea() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = theme.colorScheme.surface;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final keyboardOpen = keyboardInset > 0;
    final fieldFillStrong =
        isDark ? const Color(0xFF111827) : const Color(0xFFF3F4F6);
    final fieldFillSoft =
        isDark ? const Color(0xFF020617) : const Color(0xFFF9FAFB);
    final textColor = theme.textTheme.bodyLarge?.color ??
        (isDark ? Colors.white : Colors.black87);

    if (_isVideoFlow) {
      if (_videoStep == _VideoUploadStep.preview) {
        return SingleChildScrollView(
          key: const ValueKey('episode-preview-scroll'),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildVideoPreview(),
                    const SizedBox(height: 16),
                    Text(
                      _isEpisodeFlow
                          ? 'Preview your episode, then tap Next.'
                          : 'Preview your ${widget.type == UploadType.reel ? 'reel' : 'video'}, then tap Next.',
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    if (_isEpisodeFlow && _episodePostType != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Auto-detected as ${_episodePostType == 'reel' ? 'Reel' : 'Video'} Episode',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _buildNudityWarning(),
            ],
          ),
        );
      }

      return AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(16, 16, 16, keyboardInset > 0 ? 12 : 16),
        child: SingleChildScrollView(
          key: const ValueKey('episode-details-scroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: SizedBox(
                            height: keyboardOpen ? 120.0 : 200.0,
                            width: double.infinity,
                            child: _buildVideoPreview(resetOnPlay: false),
                          ),
                        ),
                        // TOP-LEFT: Change Video (pencil icon)
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Material(
                            color: Colors.black.withOpacity(0.65),
                            shape: const CircleBorder(),
                            child: InkWell(
                              onTap: _pickVideo,
                              customBorder: const CircleBorder(),
                              child: const Padding(
                                padding: EdgeInsets.all(10),
                                child: Icon(
                                  LucideIcons.pencil,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // TOP-RIGHT: Add/Change Thumbnail (for Video or Episode 1)
                        if (widget.type == UploadType.video || (_isEpisodeFlow && _isEpisodeOne))
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Material(
                              color: Colors.black.withOpacity(0.65),
                              shape: const CircleBorder(),
                              child: InkWell(
                                onTap: _pickThumbnail,
                                customBorder: const CircleBorder(),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: _selectedThumbnail != null
                                      ? Image.file(
                                          File(_selectedThumbnail!.path),
                                          width: 38,
                                          height: 38,
                                          fit: BoxFit.cover,
                                        )
                                      : const Padding(
                                          padding: EdgeInsets.all(10),
                                          child: Icon(
                                            LucideIcons.image,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: keyboardOpen ? 10 : 16),
                  if (_isEpisodeFlow) ...[
                    TextField(
                      controller: _seriesTitleController,
                      maxLines: 1,
                      decoration: InputDecoration(
                        hintText: 'Series title',
                        hintStyle:
                            TextStyle(fontSize: 16, color: theme.hintColor),
                        filled: true,
                        fillColor: fieldFillStrong,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      style: TextStyle(fontSize: 16, color: textColor),
                      onChanged: (_) => setState(() {}),
                    ),
                    SizedBox(height: keyboardOpen ? 8 : 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: fieldFillSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _episodePostType == 'reel'
                                ? LucideIcons.playCircle
                                : LucideIcons.video,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _episodePostType == null
                                  ? 'Pick a video and the app will detect reel or video automatically.'
                                  : 'Auto-detected as ${_episodePostType == 'reel' ? 'Reel' : 'Video'} Episode',
                              style: TextStyle(
                                fontSize: 15,
                                color: _episodePostType == null
                                    ? theme.hintColor
                                    : textColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: keyboardOpen ? 8 : 12),
                    Row(
                      children: [
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: _episodeNumberController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'Episode',
                              hintStyle: TextStyle(
                                fontSize: 16,
                                color: theme.hintColor,
                              ),
                              filled: true,
                              fillColor: fieldFillStrong,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                            style: TextStyle(fontSize: 16, color: textColor),
                            onChanged: (_) {
                              if (!_isEpisodeOne &&
                                  _selectedThumbnail != null) {
                                _selectedThumbnail = null;
                              }
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _episodeTitleController,
                            maxLines: 1,
                            decoration: InputDecoration(
                              hintText: 'Episode title',
                              hintStyle: TextStyle(
                                fontSize: 16,
                                color: theme.hintColor,
                              ),
                              filled: true,
                              fillColor: fieldFillStrong,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                            style: TextStyle(fontSize: 16, color: textColor),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: keyboardOpen ? 8 : 12),
                    Container(
                      decoration: BoxDecoration(
                        color: fieldFillSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            onTap: () {
                              setState(() {
                                _isDescriptionExpanded = !_isDescriptionExpanded;
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _episodeDescriptionController.text.trim().isEmpty
                                        ? 'Add episode description'
                                        : 'Episode description',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: _episodeDescriptionController.text.trim().isEmpty
                                          ? theme.hintColor
                                          : textColor,
                                    ),
                                  ),
                                  Icon(
                                    _isDescriptionExpanded
                                        ? LucideIcons.chevronDown
                                        : LucideIcons.chevronRight,
                                    size: 18,
                                    color: theme.hintColor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_isDescriptionExpanded)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                              child: TextField(
                                controller: _episodeDescriptionController,
                                maxLines: keyboardOpen ? 4 : 6,
                                minLines: 2,
                                maxLength: 2000,
                                textAlignVertical: TextAlignVertical.top,
                                decoration: InputDecoration(
                                  hintText: 'Describe your episode here...',
                                  hintStyle: TextStyle(
                                    fontSize: 15,
                                    color: theme.hintColor,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: theme.dividerColor.withOpacity(0.5),
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.all(12),
                                  counterText: '${_episodeDescriptionController.text.length}/2000',
                                ),
                                style: TextStyle(fontSize: 15, color: textColor),
                                onChanged: (val) {
                                  setState(() {});
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ] else if (widget.type == UploadType.video) ...[
                    TextField(
                      controller: _titleController,
                      maxLines: 1,
                      decoration: InputDecoration(
                        hintText: 'Add video title',
                        hintStyle:
                            TextStyle(fontSize: 16, color: theme.hintColor),
                        filled: true,
                        fillColor: fieldFillStrong,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      style: TextStyle(fontSize: 16, color: textColor),
                      onChanged: (_) => setState(() {}),
                    ),
                    SizedBox(height: keyboardOpen ? 8 : 12),
                    Container(
                      decoration: BoxDecoration(
                        color: fieldFillSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            onTap: () {
                              setState(() {
                                _isDescriptionExpanded = !_isDescriptionExpanded;
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _videoDescriptionController.text.trim().isEmpty
                                        ? 'Add video description'
                                        : 'Video description',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: _videoDescriptionController.text.trim().isEmpty
                                          ? theme.hintColor
                                          : textColor,
                                    ),
                                  ),
                                  Icon(
                                    _isDescriptionExpanded
                                        ? LucideIcons.chevronDown
                                        : LucideIcons.chevronRight,
                                    size: 18,
                                    color: theme.hintColor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_isDescriptionExpanded)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                              child: TextField(
                                controller: _videoDescriptionController,
                                maxLines: keyboardOpen ? 4 : 6,
                                minLines: 2,
                                maxLength: 2000,
                                textAlignVertical: TextAlignVertical.top,
                                decoration: InputDecoration(
                                  hintText: 'Describe your video here...',
                                  hintStyle: TextStyle(
                                    fontSize: 15,
                                    color: theme.hintColor,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: theme.dividerColor.withOpacity(0.5),
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.all(12),
                                  counterText: '${_videoDescriptionController.text.length}/2000',
                                ),
                                style: TextStyle(fontSize: 15, color: textColor),
                                onChanged: (val) {
                                  setState(() {});
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ] else
                    TextField(
                      controller: _textController,
                      maxLines: keyboardOpen ? 3 : 4,
                      minLines: keyboardOpen ? 3 : 4,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: InputDecoration(
                        hintText:
                            'Add a caption for your reel (you can include #tags)',
                        hintStyle:
                            TextStyle(fontSize: 16, color: theme.hintColor),
                        filled: true,
                        fillColor: fieldFillSoft,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      style: TextStyle(fontSize: 16, color: textColor),
                      onChanged: (_) => setState(() {}),
                    ),
                  if (!keyboardOpen) ...[
                    const SizedBox(height: 12),
                    _buildNudityWarning(),
                  ] else ...[
                    const SizedBox(height: 12),
                    _buildNudityWarning(),
                  ],
                ],
              );
            },
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: _canUseBg() ? _selectedTextBg : null,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: _canUseBg()
                          ? const EdgeInsets.all(8)
                          : EdgeInsets.zero,
                      child: TextField(
                        controller: _textController,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        textAlign:
                            _canUseBg() ? TextAlign.center : TextAlign.start,
                        decoration: InputDecoration.collapsed(
                          hintText: widget.type == UploadType.news
                              ? 'Write your news or blog...'
                              : "What's on your mind?",
                          hintStyle:
                              TextStyle(fontSize: 18, color: theme.hintColor),
                        ),
                        style: TextStyle(
                          fontSize: 18,
                          color: textColor,
                          fontWeight: _textController.text.length < 40
                              ? FontWeight.w800
                              : (_textController.text.length < 120
                                  ? FontWeight.w700
                                  : FontWeight.w600),
                        ),
                        onChanged: (value) {
                          if (value.length > 50 && _selectedTextBg != null) {
                            _selectedTextBg = null;
                          }
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                  if (_selectedMedia.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ..._textBgOptions.map(
                            (c) => GestureDetector(
                              onTap: () => setState(() => _selectedTextBg = c),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _selectedTextBg == c
                                        ? Colors.white
                                        : Colors.white54,
                                    width: _selectedTextBg == c ? 3 : 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _selectedTextBg = null),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceVariant,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: theme.dividerColor),
                              ),
                              child: Text(
                                'No color',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_selectedMedia.isNotEmpty) _buildMediaPreview(),
                  const SizedBox(height: 12),
                  _buildAddMediaButton(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildNudityWarning(),
        ],
      ),
    );
  }

  Widget _buildNudityWarning() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseRed = Colors.red;
    final bg = isDark ? baseRed.withOpacity(0.16) : baseRed.withOpacity(0.06);
    final border = baseRed.withOpacity(0.6);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 0.7),
      ),
      child: const Row(
        children: [
          Icon(LucideIcons.alertTriangle, color: Colors.red, size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Nudity and explicit content are strictly forbidden. Accounts violating this policy will be terminated.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddMediaButton() {
    return GestureDetector(
      onTap: () {
        if (widget.type == UploadType.standard ||
            widget.type == UploadType.news) {
          _pickFromGallery();
        }
      },
      child: Row(
        children: [
          Icon(
            widget.type == UploadType.news
                ? LucideIcons.fileEdit
                : LucideIcons.image,
            size: 20,
            color: const Color(0xFF1DA1F2),
          ),
          const SizedBox(width: 8),
          Text(
            widget.type == UploadType.news
                ? 'Add cover image (optional)'
                : 'Add Photos/Videos',
            style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF1DA1F2),
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPreview() {
    return Container(
      height: 120,
      margin: const EdgeInsets.only(top: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedMedia.length,
        itemBuilder: (context, index) {
          final media = _selectedMedia[index];
          return Container(
            width: 120,
            margin: const EdgeInsets.only(right: 8),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(media.path),
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => _removeMedia(index),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(LucideIcons.x,
                          color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooter() {
    final theme = Theme.of(context);
    final hasStandardContent =
        _textController.text.trim().isNotEmpty || _selectedMedia.isNotEmpty;
    final isVideoDetailsStep =
        _isVideoFlow && _videoStep == _VideoUploadStep.details;
    final isPrimaryEnabled = _isVideoFlow
        ? (_isEpisodeFlow
            ? true
            : (isVideoDetailsStep ? _canSubmitVideoPost : _canAdvanceVideoStep))
        : hasStandardContent;
    final primaryLabel =
        _isVideoFlow ? (isVideoDetailsStep ? 'Post' : 'Next') : 'Post';

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 16, 6, 18),
      color: theme.colorScheme.surface,
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: ElevatedButton(
          onPressed: isPrimaryEnabled && !_isPosting
              ? () {
                  if (_isVideoFlow && !isVideoDetailsStep) {
                    setState(() => _videoStep = _VideoUploadStep.details);
                    return;
                  }
                  _createPost();
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: isPrimaryEnabled
                ? const Color(0xFF1DA1F2)
                : theme.disabledColor.withOpacity(0.4),
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999)),
            elevation: isPrimaryEnabled ? 4 : 0,
          ),
          child: _isPosting
              ? const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white))
              : Text(
                  primaryLabel,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
        ),
      ),
    );
  }

  Future<void> _pickFromGallery() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        _selectedMedia.addAll(images);
        _selectedTextBg = null;
      });
    }
  }



  Widget _buildVideoPreview({bool resetOnPlay = true}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    if (_selectedVideo == null) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceVariant.withOpacity(isDark ? 0.2 : 0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            'Select a video to preview',
            style: TextStyle(color: Color(0xFF6B7280)),
          ),
        ),
      );
    }
    if (_videoInit == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return FutureBuilder<void>(
      future: _videoInit,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            _videoController == null) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final aspect = _videoController!.value.aspectRatio == 0
            ? 16 / 9
            : _videoController!.value.aspectRatio;
        return GestureDetector(
          onTap: () async {
            if (_videoController == null) return;
            if (_videoController!.value.isPlaying) {
              await _videoController!.pause();
              setState(() => _isVideoPlaying = false);
            } else {
              if (resetOnPlay) {
                await _videoController!.seekTo(Duration.zero);
              }
              await _videoController!.play();
              setState(() => _isVideoPlaying = true);
            }
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: aspect,
                child: VideoPlayer(_videoController!),
              ),
              if (!_isVideoPlaying)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child:
                        Icon(Icons.play_arrow, color: Colors.white, size: 36),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickVideo() async {
    final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;
    await _applyPickedVideo(video);
  }

  Future<void> _applyPickedVideo(XFile video) async {
    final controller = VideoPlayerController.file(File(video.path));
    try {
      await controller.initialize();
      final size = controller.value.size;
      final duration = controller.value.duration;
      final isVertical = size.height > size.width;

      if (!_isEpisodeFlow && _requiresHorizontalVideo && isVertical) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Horizontal videos only for Videos. Use Reels for vertical videos.')),
          );
        }
        await controller.dispose();
        return;
      }
      if (!_isEpisodeFlow && _requiresVerticalVideo && !isVertical) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Vertical videos only for Reels. Use Videos for horizontal videos.')),
          );
        }
        await controller.dispose();
        return;
      }
      if (_isEpisodeFlow) {
        _episodePostType = isVertical ? 'reel' : 'video';
      }

      if (!_isAdmin && duration.inSeconds > _regularUserVideoLimitSeconds) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Uploads are limited to 3 minutes for non-admin users. Please choose a shorter clip.')),
          );
        }
        await controller.dispose();
        return;
      }

      _videoController?.dispose();

      if (mounted) {
        setState(() {
          _selectedVideo = video;
          _videoDuration = duration;
          _isVideoPlaying = false;
          _videoController = controller;
          _videoInit = Future.value();
          _videoStep = _VideoUploadStep.preview;
        });
      }
    } catch (_) {
      await controller.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load video preview.')),
        );
      }
    }
  }

  Future<void> _pickThumbnail() async {
    if (_isEpisodeFlow && !_isEpisodeOne) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only Episode 1 can upload the custom thumbnail.'),
        ),
      );
      return;
    }
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedThumbnail = image;
      });
    }
  }



  void _removeMedia(int index) {
    setState(() {
      _selectedMedia.removeAt(index);
    });
  }


  Future<void> _createPost() async {
    if (_isPosting) return;
    if (_containsBannedText()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Posting blocked: nudity/explicit content not allowed.')),
      );
      return;
    }
    setState(() => _isPosting = true);
    try {
      String? effectiveVideo = _selectedVideo?.path;
      final cleanup = <String>[];

      if (_selectedVideo != null) {
        final durationSecs = _videoDuration.inSeconds;
        if (!_isAdmin && durationSecs > _regularUserVideoLimitSeconds) {
          if (mounted) {
            setState(() => _isPosting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'Only admins can post videos longer than 3 minutes.')),
            );
          }
          return;
        }
      }

      final request = PostUploadRequest(
        type: widget.type,
        content: _isEpisodeFlow
            ? _episodeDescriptionController.text.trim()
            : widget.type == UploadType.video
                ? _videoDescriptionController.text.trim()
                : _textController.text.trim(),
        title: _isEpisodeFlow
            ? _episodeTitleController.text.trim()
            : widget.type == UploadType.video
                ? _titleController.text.trim()
                : _textController.text.trim(),
        mediaPaths: _selectedMedia.map((m) => m.path).toList(),
        videoPath: effectiveVideo,
        thumbnailPath: _selectedThumbnail?.path,
        cleanupPaths: cleanup,
        textBgColor: _canUseBg() ? _selectedTextBg?.value : null,
        postTypeOverride: _isEpisodeFlow ? _resolvedVideoPostType : null,
        isEpisode: _isEpisodeFlow,
        seriesTitle: _isEpisodeFlow ? _seriesTitleController.text.trim() : null,
        episodeNumber: _isEpisodeFlow ? _episodeNumber : null,
        episodeTitle:
            _isEpisodeFlow ? _episodeTitleController.text.trim() : null,
        episodeDescription:
            _isEpisodeFlow ? _episodeDescriptionController.text.trim() : null,
      );
      PendingUploadService.enqueuePostUpload(request);
      if (!mounted) return;
      final theme = Theme.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: theme.colorScheme.primary,
          content: Text(
            'Upload in progress.',
            style: TextStyle(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _textController.dispose();
    _videoDescriptionController.dispose();
    _seriesTitleController.dispose();
    _episodeNumberController.dispose();
    _episodeTitleController.dispose();
    _episodeDescriptionController.dispose();
    _videoController?.dispose();
    super.dispose();
  }
}


