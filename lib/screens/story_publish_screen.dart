import 'dart:async';
import 'dart:io';

import 'package:appwrite/appwrite.dart' show ID;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../models/status.dart';
import '../services/appwrite_service.dart';
import '../services/story_manager.dart';
import '../services/storage_service.dart';

class StoryPublishScreen extends StatefulWidget {
  final XFile media;

  const StoryPublishScreen({super.key, required this.media});

  @override
  State<StoryPublishScreen> createState() => _StoryPublishScreenState();
}

class _StoryPublishScreenState extends State<StoryPublishScreen> {
  final TextEditingController _captionController = TextEditingController();
  final FocusNode _captionFocusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();
  static const Duration _maxStoryVideoDuration = Duration(seconds: 30);
  static const double _maxClipLength = 30.0;
  static const List<String> _fontChoices = <String>[
    'Poppins',
    'Roboto',
    'Lora',
    'Oswald',
    'Inconsolata',
  ];
  static const List<Color> _captionColors = <Color>[
    Colors.white,
    Color(0xFFFFF176),
    Color(0xFFFFAB91),
    Color(0xFF80DEEA),
    Color(0xFFE1BEE7),
  ];

  late XFile _media;
  bool _isUploading = false;
  bool _isPreviewMuted = false;
  bool _isVideoPlaying = false;
  bool _previewUsesCoverFit = true;
  bool _isScrubbingProgress = false;
  double _playbackProgressSeconds = 0.0;
  String _captionFontFamily = _fontChoices.first;
  double _captionFontSize = 26;
  FontWeight _captionFontWeight = FontWeight.w700;
  bool _captionItalic = false;
  Color _captionColor = Colors.white;
  VideoPlayerController? _videoController;

  bool get _isVideo =>
      _media.path.toLowerCase().endsWith('.mp4') ||
      _media.path.toLowerCase().endsWith('.mov') ||
      _media.path.toLowerCase().endsWith('mkv') ||
      _media.path.toLowerCase().endsWith('.webm');

  double get _videoDuration =>
      _videoController?.value.duration.inSeconds.toDouble() ?? 0.0;

  double get _fileSizeMb => File(_media.path).lengthSync() / (1024 * 1024);

  String get _fileSizeLabel => '${_fileSizeMb.toStringAsFixed(1)} MB';

  @override
  void initState() {
    super.initState();
    _media = widget.media;
    _initializePreview();
  }

  Future<void> _initializePreview() async {
    _playbackProgressSeconds = 0.0;
    _isVideoPlaying = false;
    if (!_isVideo) {
      await _disposeVideoController();
      if (mounted) setState(() {});
      return;
    }

    final controller = VideoPlayerController.file(File(_media.path));
    final previous = _videoController;
    previous?.removeListener(_handleVideoProgress);
    _videoController = controller;
    await previous?.dispose();

    try {
      await controller.initialize();
      final duration = controller.value.duration;
      if (duration > _maxStoryVideoDuration) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Story videos must not be longer than 30 seconds.'),
          ),
        );
        Navigator.of(context).pop();
        return;
      }
      await controller.setLooping(true);
      await controller.setVolume(_isPreviewMuted ? 0 : 1);
      controller.addListener(_handleVideoProgress);
      if (!mounted) return;
      setState(() {});
    } catch (_) {
      await controller.dispose();
      if (_videoController == controller) {
        _videoController = null;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to preview this video.')),
      );
    }
  }

  Future<void> _disposeVideoController() async {
    final controller = _videoController;
    _videoController = null;
    if (controller != null) {
      controller.removeListener(_handleVideoProgress);
      await controller.dispose();
    }
  }

  void _handleVideoProgress() {
    final controller = _videoController;
    if (!mounted || controller == null || !controller.value.isInitialized) {
      return;
    }
    if (_isScrubbingProgress) return;
    final positionSeconds = controller.value.position.inMilliseconds / 1000.0;
    final isPlaying = controller.value.isPlaying;
    if ((positionSeconds - _playbackProgressSeconds).abs() < 0.05 &&
        isPlaying == _isVideoPlaying) {
      return;
    }
    setState(() {
      _playbackProgressSeconds = positionSeconds.clamp(
        0.0,
        _videoDuration,
      );
      _isVideoPlaying = isPlaying;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildMediaPreview()),
            if (_captionController.text.trim().isNotEmpty)
              Positioned(
                left: 20,
                right: 20,
                bottom: 230,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        _captionController.text.trim(),
                        textAlign: TextAlign.center,
                        style: _buildCaptionStyle(),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: _buildTopActions(),
            ),
            if (_isVideo && _videoController?.value.isInitialized == true)
              Positioned(
                top: 80,
                left: 24,
                right: 24,
                child: _buildTrimSlider(theme),
              ),
            Positioned(
              bottom: 180,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _isVideo
                        ? 'Preview, play, edit title, then post'
                        : 'Preview, add caption, then post',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black,
                      Colors.black.withOpacity(0.0),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.photo, color: Colors.white54),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _captionController,
                            focusNode: _captionFocusNode,
                            onChanged: (_) => setState(() {}),
                            style: _buildCaptionStyle().copyWith(
                              fontSize: 18,
                              color: Colors.white,
                            ),
                            maxLines: null,
                            decoration: const InputDecoration(
                              hintText: 'Add a caption...',
                              hintStyle: TextStyle(color: Colors.white60),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _isUploading ? null : _postStory,
                          child: CircleAvatar(
                            radius: 26,
                            backgroundColor: Colors.green,
                            child: Icon(
                              _isUploading ? Icons.hourglass_top : Icons.send,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _isVideo
                            ? '${_formatDuration(_playbackProgressSeconds)} / ${_formatDuration(_videoDuration)} • $_fileSizeLabel'
                            : _fileSizeLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white60,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopActions() {
    final actions = <Widget>[
      _buildActionButton(
        icon: Icons.close,
        onTap: () => Navigator.of(context).pop(),
      ),
      _buildActionButton(
        icon: _isPreviewMuted ? Icons.music_off : Icons.music_note,
        onTap: _toggleMute,
      ),
      _buildActionButton(
        icon: Icons.switch_camera,
        onTap: _replaceMedia,
      ),
      _buildActionButton(
        icon: _previewUsesCoverFit ? Icons.crop_square : Icons.fit_screen,
        onTap: () {
          setState(() => _previewUsesCoverFit = !_previewUsesCoverFit);
        },
      ),
      _buildActionButton(
        icon: Icons.text_fields,
        onTap: _openTextStyleEditor,
      ),
      _buildActionButton(
        icon: Icons.edit,
        onTap: _editCaption,
      ),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: actions,
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Future<void> _toggleMute() async {
    if (!_isVideo || _videoController == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Audio control is available for videos only.')),
      );
      return;
    }
    final nextMuted = !_isPreviewMuted;
    await _videoController!.setVolume(nextMuted ? 0 : 1);
    if (!mounted) return;
    setState(() => _isPreviewMuted = nextMuted);
  }

  Future<void> _replaceMedia() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(
                    _isVideo ? 'Choose another video' : 'Choose another photo'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: Icon(_isVideo ? Icons.videocam : Icons.camera_alt),
                title: Text(_isVideo ? 'Record video' : 'Take photo'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );
    if (source == null) return;

    final XFile? replacement = _isVideo
        ? await _picker.pickVideo(
            source: source,
            maxDuration: _maxStoryVideoDuration,
          )
        : await _picker.pickImage(source: source);
    if (replacement == null) return;

    setState(() {
      _media = replacement;
      _previewUsesCoverFit = true;
    });
    await _initializePreview();
  }

  Future<void> _editCaption() async {
    final controller = TextEditingController(text: _captionController.text);
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Edit caption',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                minLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Add a caption...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(controller.text),
                  child: const Text('Save caption'),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (value == null) return;
    _captionController.text = value;
    setState(() {});
    _captionFocusNode.requestFocus();
  }

  Future<void> _openTextStyleEditor() async {
    final selected = await showModalBottomSheet<_CaptionStyleSelection>(
      context: context,
      builder: (context) {
        String draftFontFamily = _captionFontFamily;
        double draftFontSize = _captionFontSize;
        FontWeight draftFontWeight = _captionFontWeight;
        bool draftItalic = _captionItalic;
        Color draftColor = _captionColor;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            TextStyle previewStyle() {
              return GoogleFonts.getFont(
                draftFontFamily,
                fontSize: draftFontSize,
                fontWeight: draftFontWeight,
                fontStyle: draftItalic ? FontStyle.italic : FontStyle.normal,
                color: draftColor,
                shadows: const <Shadow>[
                  Shadow(
                    color: Colors.black54,
                    offset: Offset(0, 1),
                    blurRadius: 4,
                  ),
                ],
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Text Style',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _captionController.text.trim().isEmpty
                            ? 'Caption preview'
                            : _captionController.text.trim(),
                        textAlign: TextAlign.center,
                        style: previewStyle(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _fontChoices.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final font = _fontChoices[index];
                          final selected = font == draftFontFamily;
                          return ChoiceChip(
                            label: Text(font),
                            selected: selected,
                            onSelected: (_) {
                              setSheetState(() => draftFontFamily = font);
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Font size ${draftFontSize.toStringAsFixed(0)}',
                    ),
                    Slider(
                      min: 18,
                      max: 40,
                      value: draftFontSize,
                      onChanged: (value) {
                        setSheetState(() => draftFontSize = value);
                      },
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Bold'),
                            selected: draftFontWeight == FontWeight.w700,
                            onSelected: (_) {
                              setSheetState(() {
                                draftFontWeight =
                                    draftFontWeight == FontWeight.w700
                                        ? FontWeight.w400
                                        : FontWeight.w700;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Italic'),
                            selected: draftItalic,
                            onSelected: (_) {
                              setSheetState(() => draftItalic = !draftItalic);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _captionColors.map((color) {
                        final selected = color == draftColor;
                        return GestureDetector(
                          onTap: () {
                            setSheetState(() => draftColor = color);
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected ? Colors.black : Colors.grey,
                                width: selected ? 3 : 1,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop(
                            _CaptionStyleSelection(
                              fontFamily: draftFontFamily,
                              fontSize: draftFontSize,
                              fontWeight: draftFontWeight,
                              italic: draftItalic,
                              color: draftColor,
                            ),
                          );
                        },
                        child: const Text('Apply style'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() {
      _captionFontFamily = selected.fontFamily;
      _captionFontSize = selected.fontSize;
      _captionFontWeight = selected.fontWeight;
      _captionItalic = selected.italic;
      _captionColor = selected.color;
    });
    _captionFocusNode.requestFocus();
  }

  Future<void> _toggleVideoPlayback() async {
    if (!_isVideo || _videoController == null) return;
    if (_videoController!.value.isPlaying) {
      await _videoController!.pause();
      if (!mounted) return;
      setState(() => _isVideoPlaying = false);
      return;
    }
    await _videoController!.play();
    if (!mounted) return;
    setState(() => _isVideoPlaying = true);
  }

  Future<void> _postStory() async {
    if (_isUploading) return;
    if (_isVideo &&
        (_videoController?.value.duration ?? Duration.zero) >
            _maxStoryVideoDuration) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Story videos must not be longer than 30 seconds.'),
        ),
      );
      return;
    }
    setState(() => _isUploading = true);
    final caption = _captionController.text.trim();
    final mediaPath = _media.path;
    StoryManager.setMyUploading(
      true,
      caption: caption,
      mediaPath: mediaPath,
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
    unawaited(_uploadStoryInBackground(
      caption: caption,
      mediaPath: mediaPath,
    ));
  }

  Future<void> _uploadStoryInBackground({
    required String caption,
    required String mediaPath,
  }) async {
    try {
      final me = await AppwriteService.getCurrentUser();
      if (me == null) {
        StoryManager.setMyUploading(false);
        return;
      }
      final profile = await AppwriteService.getProfileByUserId(me.$id);
      final avatar = profile?.data['avatarUrl'] as String? ?? '';
      final displayName =
          (profile?.data['displayName'] as String?)?.trim() ?? '';

      final ext = mediaPath.split('.').last;
      final path =
          'stories/${me.$id}/story_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final storedPath =
          await StorageService.uploadFileAtPath(File(mediaPath), path);
      final url = await StorageService.getSignedUrl(storedPath);
      final statusId = ID.unique();

      await StoryManager.addStatus(
        StatusUpdate(
          id: statusId,
          username: displayName,
          userAvatar: avatar,
          timestamp: DateTime.now(),
          isViewed: false,
          mediaCount: 1,
          mediaUrls: [url],
          caption: caption,
          isUploading: false,
        ),
      );
      StoryManager.setMyUploading(false);
      await AppwriteService.createStatus(
        statusId,
        me.$id,
        storedPath,
        DateTime.now(),
        caption: caption,
      );
    } catch (_) {
      StoryManager.setMyUploading(false);
    } finally {
      StoryManager.setMyUploading(false);
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Widget _buildMediaPreview() {
    if (_isVideo &&
        _videoController != null &&
        _videoController!.value.isInitialized) {
      final preview = GestureDetector(
        onTap: _toggleVideoPlayback,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: FittedBox(
                fit: _previewUsesCoverFit ? BoxFit.cover : BoxFit.contain,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            ),
            if (!_isVideoPlaying)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(
                  Icons.play_arrow,
                  size: 42,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      );
      return Container(color: Colors.black, child: preview);
    }

    return Image.file(
      File(_media.path),
      fit: _previewUsesCoverFit ? BoxFit.cover : BoxFit.contain,
    );
  }

  Widget _buildTrimSlider(ThemeData theme) {
    final sliderMax = _videoDuration <= 0 ? 1.0 : _videoDuration;
    final sliderValue = _playbackProgressSeconds.clamp(0.0, sliderMax);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Slider(
            min: 0,
            max: sliderMax,
            value: sliderValue,
            activeColor: Colors.white,
            inactiveColor: Colors.white24,
            onChangeStart: (_) {
              _isScrubbingProgress = true;
            },
            onChangeEnd: (_) {
              _isScrubbingProgress = false;
            },
            onChanged: (value) async {
              setState(() {
                _playbackProgressSeconds = value;
              });
              await _videoController?.seekTo(
                Duration(milliseconds: (value * 1000).round()),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(_playbackProgressSeconds),
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            Text(
              'Duration progress • max ${_maxClipLength.toInt()}s',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDuration(double seconds) {
    final dur = Duration(seconds: seconds.toInt());
    final minutes = dur.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = dur.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  TextStyle _buildCaptionStyle() {
    return GoogleFonts.getFont(
      _captionFontFamily,
      fontSize: _captionFontSize,
      fontWeight: _captionFontWeight,
      fontStyle: _captionItalic ? FontStyle.italic : FontStyle.normal,
      color: _captionColor,
      shadows: const <Shadow>[
        Shadow(
          color: Colors.black54,
          offset: Offset(0, 1),
          blurRadius: 4,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _disposeVideoController();
    _captionController.dispose();
    _captionFocusNode.dispose();
    super.dispose();
  }
}

class _CaptionStyleSelection {
  final String fontFamily;
  final double fontSize;
  final FontWeight fontWeight;
  final bool italic;
  final Color color;

  const _CaptionStyleSelection({
    required this.fontFamily,
    required this.fontSize,
    required this.fontWeight,
    required this.italic,
    required this.color,
  });
}

