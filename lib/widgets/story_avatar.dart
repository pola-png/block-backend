import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../models/story.dart';

class StoryAvatar extends StatelessWidget {
  final Story story;
  final bool isCurrentUser;

  const StoryAvatar(
      {super.key, required this.story, this.isCurrentUser = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor =
        theme.textTheme.bodySmall?.color ?? theme.colorScheme.onBackground;
    final innerBgColor = isDark ? theme.colorScheme.background : Colors.white;
    final innerBorderColor = theme.colorScheme.background;

    return Container(
      width: 72,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: story.isUploading
                      ? null
                      : (isCurrentUser && !story.hasActiveStories)
                          ? null
                          : story.isViewed
                              ? null
                              : const LinearGradient(
                                  colors: [
                                    Color(0xFFFEDA75),
                                    Color(0xFFF58529),
                                    Color(0xFFDD2A7B),
                                    Color(0xFF8134AF),
                                    Color(0xFF515BD4)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                  color: story.isUploading
                      ? Colors.transparent
                      : (isCurrentUser && !story.hasActiveStories)
                          ? Colors.transparent
                          : story.isViewed
                              ? (isDark ? Colors.white30 : Colors.black26)
                              : Colors.transparent,
                ),
              ),
              if (story.isUploading)
                SizedBox(
                  width: 68,
                  height: 68,
                  child: const CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF1DA1F2),
                    ),
                    backgroundColor: Colors.white24,
                  ),
                ),
              Container(
                width: 62,
                height: 62,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: innerBgColor,
                  border: Border.all(color: innerBorderColor, width: 2),
                ),
                child: _buildAvatarImage(story.imageUrl),
              ),
              if (isCurrentUser && !story.hasActiveStories)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1DA1F2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                        width: 2,
                      ),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 16),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            story.isUploading
                ? 'Uploading...'
                : isCurrentUser
                    ? 'Your Story'
                    : story.username,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: textColor),
          ),
        ],
      ),
    );
  }
}

Widget _buildAvatarImage(String url) {
  if (url.isEmpty) {
    return const CircleAvatar(
      radius: 34,
      backgroundColor: Colors.transparent,
      child: Icon(Icons.person, color: Colors.grey),
    );
  }
  if (_looksLikeVideoStory(url)) {
    return _VideoStoryThumbnail(videoUrl: url);
  }
  final isNetworkImage =
      url.startsWith('http://') || url.startsWith('https://');
  return ClipOval(
    child: isNetworkImage
        ? CachedNetworkImage(
            imageUrl: url,
            width: 62,
            height: 62,
            fit: BoxFit.cover,
            placeholder: (context, _) => const CircleAvatar(
              radius: 34,
              backgroundColor: Colors.transparent,
              child: Icon(Icons.person, color: Colors.grey),
            ),
            errorWidget: (context, _, __) => const CircleAvatar(
              radius: 34,
              backgroundColor: Colors.transparent,
              child: Icon(Icons.person, color: Colors.grey),
            ),
          )
        : Image.file(
            File(url),
            width: 62,
            height: 62,
            fit: BoxFit.cover,
            errorBuilder: (context, _, __) => const CircleAvatar(
              radius: 34,
              backgroundColor: Colors.transparent,
              child: Icon(Icons.person, color: Colors.grey),
            ),
          ),
  );
}

bool _looksLikeVideoStory(String url) {
  final normalized = url.toLowerCase();
  final uri = Uri.tryParse(url);
  final candidate = uri?.queryParameters['filename']?.toLowerCase() ??
      uri?.queryParameters['path']?.toLowerCase() ??
      normalized;
  return candidate.endsWith('.mp4') ||
      candidate.endsWith('.mov') ||
      candidate.endsWith('.webm') ||
      candidate.endsWith('.mkv') ||
      candidate.endsWith('.m4v') ||
      candidate.endsWith('.m3u8');
}

class _VideoStoryThumbnail extends StatelessWidget {
  const _VideoStoryThumbnail({required this.videoUrl});

  final String videoUrl;
  static final Map<String, Future<String?>> _thumbnailFutures =
      <String, Future<String?>>{};

  Future<String?> _loadThumbnail() {
    return _thumbnailFutures.putIfAbsent(
      videoUrl,
      () => VideoThumbnail.thumbnailFile(
        video: videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxHeight: 160,
        quality: 70,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _loadThumbnail(),
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (path == null || path.isEmpty) {
          return Container(
            color: Colors.black87,
            alignment: Alignment.center,
            child: const Icon(
              Icons.play_arrow,
              color: Colors.white,
              size: 26,
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (context, _, __) => Container(
                color: Colors.black87,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 24,
              ),
            ),
          ],
        );
      },
    );
  }
}
