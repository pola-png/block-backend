import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart' show AppwriteException;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/upload_type.dart';
import '../utils/news_seo.dart';
import 'appwrite_service.dart';
import 'storage_service.dart';

class PendingUpload {
  PendingUpload({
    required this.id,
    required this.title,
    required this.request,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String title;
  PostUploadRequest request;
  final DateTime createdAt;
  double progress = 0.0;
  String status = 'Queued';
  bool completed = false;
  bool failed = false;
  bool isDraft = false;
  String? error;
  int attempt = 0;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'request': request.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'progress': progress,
      'status': status,
      'completed': completed,
      'failed': failed,
      'isDraft': isDraft,
      'error': error,
      'attempt': attempt,
    };
  }

  factory PendingUpload.fromJson(Map<String, dynamic> json) {
    final requestRaw = json['request'];
    if (requestRaw is! Map) {
      throw StateError('Missing upload request.');
    }
    final request =
        PostUploadRequest.fromJson(requestRaw.cast<String, dynamic>());
    final upload = PendingUpload(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      request: request,
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
    );
    upload.progress = (json['progress'] as num?)?.toDouble() ?? 0.0;
    upload.status = (json['status'] as String?) ?? 'Queued';
    upload.completed = json['completed'] == true;
    upload.failed = json['failed'] == true;
    upload.isDraft = json['isDraft'] == true;
    upload.error = json['error'] as String?;
    upload.attempt = (json['attempt'] as num?)?.toInt() ?? 0;
    return upload;
  }
}

class PostUploadRequest {
  PostUploadRequest({
    required this.type,
    required this.content,
    required this.title,
    required this.mediaPaths,
    this.videoPath,
    this.thumbnailPath,
    this.cleanupPaths = const <String>[],
    this.textBgColor,
    this.postTypeOverride,
    this.isEpisode = false,
    this.seriesTitle,
    this.episodeNumber,
    this.episodeTitle,
    this.episodeDescription,
  });

  final UploadType type;
  final String content;
  final String title;
  final List<String> mediaPaths;
  final String? videoPath;
  final String? thumbnailPath;
  final List<String> cleanupPaths;
  final int? textBgColor;
  final String? postTypeOverride;
  final bool isEpisode;
  final String? seriesTitle;
  final int? episodeNumber;
  final String? episodeTitle;
  final String? episodeDescription;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type.name,
      'content': content,
      'title': title,
      'mediaPaths': mediaPaths,
      'videoPath': videoPath,
      'thumbnailPath': thumbnailPath,
      'cleanupPaths': cleanupPaths,
      'textBgColor': textBgColor,
      'postTypeOverride': postTypeOverride,
      'isEpisode': isEpisode,
      'seriesTitle': seriesTitle,
      'episodeNumber': episodeNumber,
      'episodeTitle': episodeTitle,
      'episodeDescription': episodeDescription,
    };
  }

  factory PostUploadRequest.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] as String?) ?? UploadType.standard.name;
    final uploadType = UploadType.values.firstWhere(
      (value) => value.name == rawType,
      orElse: () => UploadType.standard,
    );
    return PostUploadRequest(
      type: uploadType,
      content: (json['content'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      mediaPaths: (json['mediaPaths'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const <String>[],
      videoPath: json['videoPath'] as String?,
      thumbnailPath: json['thumbnailPath'] as String?,
      cleanupPaths: (json['cleanupPaths'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const <String>[],
      textBgColor: (json['textBgColor'] as num?)?.toInt(),
      postTypeOverride: json['postTypeOverride'] as String?,
      isEpisode: json['isEpisode'] == true,
      seriesTitle: json['seriesTitle'] as String?,
      episodeNumber: (json['episodeNumber'] as num?)?.toInt(),
      episodeTitle: json['episodeTitle'] as String?,
      episodeDescription: json['episodeDescription'] as String?,
    );
  }
}

class PendingUploadService {
  static const String _storageKey = 'pending_upload_queue_v1';
  static final ValueNotifier<List<PendingUpload>> uploads =
      ValueNotifier<List<PendingUpload>>([]);
  static final ValueNotifier<int> publishedVersion = ValueNotifier<int>(0);
  static final ValueNotifier<String?> publishedPostId = ValueNotifier<String?>(
    null,
  );
  static final Map<String, PostUploadRequest> _requests = {};
  static bool _initialized = false;
  static bool _restoring = false;

  static String enqueuePostUpload(PostUploadRequest request) {
    final uploadId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final upload = PendingUpload(
      id: uploadId,
      title: switch (request.type) {
        UploadType.video => 'Uploading video',
        UploadType.reel => 'Uploading reel',
        UploadType.episode => 'Uploading episode',
        UploadType.news => 'Publishing article',
        _ => 'Uploading post',
      },
      request: request,
    );
    _requests[upload.id] = request;
    _addUpload(upload);
    unawaited(_stageUploadThenProcess(upload));
    return upload.id;
  }

  static void _addUpload(PendingUpload upload) {
    uploads.value = [...uploads.value, upload];
  }

  static void _notify() {
    uploads.value = List<PendingUpload>.from(uploads.value);
    unawaited(_persistQueue());
  }

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _restoreQueue();
  }

  static Future<void> retry(String uploadId) async {
    final uploadIndex = uploads.value.indexWhere((u) => u.id == uploadId);
    if (uploadIndex == -1) return;
    final request = _requests[uploadId];
    if (request == null) return;
    final upload = uploads.value[uploadIndex];
    upload.failed = false;
    upload.isDraft = false;
    upload.error = null;
    upload.progress = 0.0;
    upload.completed = false;
    upload.status = 'Retrying...';
    _notify();
    await _processPostUpload(upload, request);
  }

  static Future<void> clearCompletedUploads() async {
    final remaining = uploads.value.where((upload) {
      return !upload.completed;
    }).toList(growable: false);
    if (remaining.length == uploads.value.length) return;
    final completedIds = uploads.value
        .where((upload) => upload.completed)
        .map((upload) => upload.id)
        .toSet();
    uploads.value = remaining;
    for (final id in completedIds) {
      _requests.remove(id);
    }
    _notify();
    await _persistQueue();
  }

  static Future<Directory> _stagingRoot() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'pending_uploads'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<String?> _stageFile(
    String uploadId,
    String sourcePath,
    String kind,
  ) async {
    final source = File(sourcePath);
    if (!await source.exists()) return null;
    final root = await _stagingRoot();
    final uploadDir = Directory(p.join(root.path, uploadId));
    if (!await uploadDir.exists()) {
      await uploadDir.create(recursive: true);
    }
    final ext = p.extension(sourcePath);
    final dest = File(
      p.join(uploadDir.path, '$kind${ext.isNotEmpty ? ext : ''}'),
    );
    final normalizedSource = p.normalize(source.absolute.path);
    final normalizedDest = p.normalize(dest.absolute.path);
    if (normalizedSource == normalizedDest) {
      return dest.path;
    }
    await source.copy(dest.path);
    return dest.path;
  }

  static Future<PostUploadRequest> _stageRequestFiles(
    String uploadId,
    PostUploadRequest request,
  ) async {
    final cleanupPaths = <String>[...request.cleanupPaths];
    final stagedMedia = <String>[];
    for (var i = 0; i < request.mediaPaths.length; i++) {
      final staged = await _stageFile(uploadId, request.mediaPaths[i], 'media_$i');
      if (staged != null) {
        stagedMedia.add(staged);
        cleanupPaths.add(staged);
      } else {
        stagedMedia.add(request.mediaPaths[i]);
      }
    }
    String? videoPath = request.videoPath;
    if (request.videoPath != null) {
      final staged = await _stageFile(uploadId, request.videoPath!, 'video');
      if (staged != null) {
        videoPath = staged;
        cleanupPaths.add(staged);
      }
    }
    String? thumbnailPath = request.thumbnailPath;
    if (request.thumbnailPath != null) {
      final staged = await _stageFile(uploadId, request.thumbnailPath!, 'thumb');
      if (staged != null) {
        thumbnailPath = staged;
        cleanupPaths.add(staged);
      }
    }
    return PostUploadRequest(
      type: request.type,
      content: request.content,
      title: request.title,
      mediaPaths: stagedMedia,
      videoPath: videoPath,
      thumbnailPath: thumbnailPath,
      cleanupPaths: cleanupPaths,
      textBgColor: request.textBgColor,
      postTypeOverride: request.postTypeOverride,
      isEpisode: request.isEpisode,
      seriesTitle: request.seriesTitle,
      episodeNumber: request.episodeNumber,
      episodeTitle: request.episodeTitle,
      episodeDescription: request.episodeDescription,
    );
  }

  static Future<void> _stageUploadThenProcess(PendingUpload upload) async {
    try {
      final stagedRequest = await _stageRequestFiles(upload.id, upload.request);
      _requests[upload.id] = stagedRequest;
      upload.request = stagedRequest;
      _notify();
      await _persistQueue();
      if (!upload.completed && !upload.failed) {
        await _processPostUpload(upload, stagedRequest);
      }
    } catch (_) {}
  }

  static Future<void> _persistQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = uploads.value.map((upload) => upload.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(payload));
    } catch (_) {}
  }

  static Future<void> _restoreQueue() async {
    if (_restoring) return;
    _restoring = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final restored = <PendingUpload>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          final upload = PendingUpload.fromJson(item.cast<String, dynamic>());
          if (upload.id.isEmpty) continue;
          _requests[upload.id] = upload.request;
          restored.add(upload);
        } catch (_) {}
      }
      uploads.value = restored;
      for (final upload in restored) {
        if (!upload.completed && !upload.failed) {
          unawaited(_stageUploadThenProcess(upload));
        }
      }
    } catch (_) {}
    finally {
      _restoring = false;
    }
  }

  static Future<void> _processPostUpload(
      PendingUpload upload, PostUploadRequest request) async {
    const int maxAttempts = 3;
    for (int i = 0; i < maxAttempts; i++) {
      upload.attempt = i + 1;
      upload.failed = false;
      upload.isDraft = false;
      upload.error = null;
      try {
        upload.status = i == 0
            ? 'Preparing media'
            : 'Retrying (${upload.attempt}/$maxAttempts)';
        upload.progress = 0.05;
        _notify();
        final user = await AppwriteService.getCurrentUser();
        if (user == null) {
          throw Exception('Login required');
        }

        String? avatarUrl;
        String? displayName;
        String? username;
        try {
          final profile = await AppwriteService.getProfileByUserId(user.$id);
          avatarUrl = profile?.data['avatarUrl'] as String?;
          displayName = (profile?.data['displayName'] as String?)?.trim();
          username = (profile?.data['username'] as String?)?.trim();
        } catch (_) {}

        final List<String> uploadedMedia = [];
        String? thumbnailUrl;
        if (request.type == UploadType.video ||
            request.type == UploadType.reel ||
            request.type == UploadType.episode) {
          if (request.videoPath != null) {
            upload.status = 'Uploading video';
            upload.progress = 0.2;
            _notify();
            final file = File(request.videoPath!);
            if (!file.existsSync()) {
              throw Exception('Video file missing at ${file.path}');
            }
            final ext = p.extension(file.path);
            final key =
                'videos/${user.$id}/${upload.id}${ext.isNotEmpty ? ext : '.mp4'}';
            final storedPath = await StorageService.uploadFileAtPath(file, key);
            uploadedMedia.add(storedPath);
          } else {
            throw Exception('Missing video file');
          }

          if (request.thumbnailPath != null &&
              request.thumbnailPath!.isNotEmpty &&
              (request.type == UploadType.video ||
                  request.type == UploadType.episode)) {
            upload.status = 'Uploading thumbnail';
            upload.progress = 0.35;
            _notify();
            final thumbFile = File(request.thumbnailPath!);
            final ext = p.extension(thumbFile.path);
            final key =
                'videos/${user.$id}/thumb_${upload.id}${ext.isNotEmpty ? ext : '.png'}';
            final storedThumb =
                await StorageService.uploadFileAtPath(thumbFile, key);
            thumbnailUrl = storedThumb;
          } else {
            upload.status = 'Generating thumbnail';
            upload.progress = 0.35;
            _notify();
            try {
              final thumbPath = await VideoThumbnail.thumbnailFile(
                video: request.videoPath!,
                imageFormat: ImageFormat.PNG,
                maxHeight: 480,
                quality: 75,
              );
              if (thumbPath != null) {
                final thumbFile = File(thumbPath);
                if (!thumbFile.existsSync()) {
                  throw Exception('Generated thumbnail file missing');
                }
                final ext = p.extension(thumbFile.path);
                final key =
                    'videos/${user.$id}/thumb_${upload.id}${ext.isNotEmpty ? ext : '.png'}';
                final storedThumb =
                    await StorageService.uploadFileAtPath(thumbFile, key);
                thumbnailUrl = storedThumb;
              }
            } catch (_) {
              // If thumbnail generation fails, continue without blocking upload.
              thumbnailUrl = null;
            }
          }
        } else if (request.mediaPaths.isNotEmpty) {
          upload.status = 'Uploading media';
          upload.progress = 0.2;
          _notify();
          for (var index = 0; index < request.mediaPaths.length; index++) {
            final path = request.mediaPaths[index];
            final file = File(path);
            final ext = p.extension(file.path);
            final key =
                'posts/${user.$id}/${upload.id}/media_${index + 1}$ext';
            final storedPath = await StorageService.uploadFileAtPath(file, key);
            uploadedMedia.add(storedPath);
          }
        }

        upload.status = 'Publishing post';
        upload.progress = 0.8;
        _notify();

        final hasMedia = uploadedMedia.isNotEmpty;
        final String postType = switch (request.type) {
          UploadType.standard => hasMedia ? 'image' : 'text',
          UploadType.video => 'video',
          UploadType.reel => 'reel',
          UploadType.episode =>
            (request.postTypeOverride?.trim().isNotEmpty == true)
                ? request.postTypeOverride!.trim().toLowerCase()
                : 'video',
          UploadType.news => 'news',
        };

        final trimmedContent = request.content.trim();
        final trimmedTitle = request.title.trim();
        final shortDescription = trimmedContent.length <= 160
            ? trimmedContent
            : '${trimmedContent.substring(0, 157).trimRight()}...';
        final storedTitle = request.type == UploadType.video ||
                request.type == UploadType.news ||
                (request.type == UploadType.episode && postType == 'video')
            ? trimmedTitle
            : '';
        final effectiveUsername =
            (username != null && username.isNotEmpty) ? username : user.name;
        final effectiveDisplayName =
            (displayName != null && displayName.isNotEmpty)
                ? displayName
                : effectiveUsername;

        String? seoTitle;
        String? seoDescription;
        String? seoSlug;
        List<String>? seoKeywords;
        String? seoCategory;
        if (request.type == UploadType.news) {
          final seo = buildNewsSeo(trimmedTitle, trimmedContent);
          seoTitle = seo.seoTitle;
          seoDescription = seo.seoDescription;
          seoSlug = seo.seoSlug;
          seoKeywords = seo.seoKeywords;
          seoCategory = 'news';
        } else if (request.type == UploadType.video ||
            request.type == UploadType.reel ||
            request.type == UploadType.episode) {
          if (trimmedTitle.isNotEmpty) {
            seoTitle = trimmedTitle;
          }
          if (trimmedContent.isNotEmpty) {
            seoDescription = trimmedContent.length <= 160
                ? trimmedContent
                : '${trimmedContent.substring(0, 157).trimRight()}...';
          }
          seoCategory = postType;
        }

        final data = <String, dynamic>{
          'userId': user.$id,
          'username': effectiveUsername,
          'displayName': effectiveDisplayName,
          if (avatarUrl != null && avatarUrl.isNotEmpty)
            'userAvatar': avatarUrl,
          'content': request.content,
          'title': storedTitle,
          'description': shortDescription,
          'caption': trimmedContent,
          if (request.textBgColor != null) 'textBgColor': request.textBgColor,
          'likes': 0,
          'comments': 0,
          'reposts': 0,
          'shares': 0,
          'impressions': 0,
          'views': 0,
          'isBoosted': false,
          'createdAt': DateTime.now().toIso8601String(),
          'mediaUrls': uploadedMedia,
          'postType': postType,
          if (postType == 'video' || postType == 'reel')
            'thumbnailUrl': thumbnailUrl,
          if (request.isEpisode) 'isEpisode': true,
          if (request.isEpisode &&
              request.postTypeOverride?.trim().isNotEmpty == true)
            'episodeContentType':
                request.postTypeOverride!.trim().toLowerCase(),
          if (request.isEpisode &&
              request.seriesTitle?.trim().isNotEmpty == true)
            'seriesTitle': request.seriesTitle!.trim(),
          if (request.isEpisode && request.episodeNumber != null)
            'episodeNumber': request.episodeNumber,
          if (request.isEpisode &&
              request.episodeTitle?.trim().isNotEmpty == true)
            'episodeTitle': request.episodeTitle!.trim(),
          if (request.isEpisode &&
              request.episodeDescription?.trim().isNotEmpty == true)
            'episodeDescription': request.episodeDescription!.trim(),
          if (request.isEpisode &&
              request.episodeNumber == 1 &&
              thumbnailUrl != null &&
              thumbnailUrl.isNotEmpty)
            'seriesThumbnailUrl': thumbnailUrl,
          if (seoTitle != null && seoTitle.isNotEmpty) 'seoTitle': seoTitle,
          if (seoDescription != null && seoDescription.isNotEmpty)
            'seoDescription': seoDescription,
          if (seoSlug != null && seoSlug.isNotEmpty) 'seoSlug': seoSlug,
          if (seoKeywords != null && seoKeywords.isNotEmpty)
            'seoKeywords': seoKeywords,
          if (seoCategory != null && seoCategory.isNotEmpty)
            'seoCategory': seoCategory,
        };

        final createdPost = await AppwriteService.createPost(data);

        upload.status = 'Completed';
        upload.progress = 1.0;
        upload.completed = true;
        publishedPostId.value = createdPost.$id;
        publishedVersion.value += 1;
        _notify();
        // Cleanup temp files
        for (final path in request.cleanupPaths) {
          try {
            final f = File(path);
            if (await f.exists()) {
              await f.delete();
            }
          } catch (_) {}
        }
        return;
      } catch (e) {
        upload.failed = i + 1 >= maxAttempts;
        upload.error = _formatUploadError(e);
        upload.isDraft = upload.failed;
        upload.status = upload.failed ? 'Saved to drafts' : 'Retrying...';
        _notify();
        if (upload.failed) return;
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  static String _formatUploadError(Object error) {
    if (error is AppwriteException) {
      if (!kDebugMode) {
        return 'Upload failed. Please try again.';
      }
      final type = (error.type ?? '').trim();
      final message = (error.message ?? '').trim();
      final code = error.code;

      final parts = <String>[];
      if (type.isNotEmpty) parts.add(type);
      if (message.isNotEmpty) parts.add(message);
      if (code != null && code > 0) parts.add('Code $code');

      if (parts.isNotEmpty) {
        return parts.join(': ');
      }
    }

    if (error is SocketException) {
      return 'Network error: ${error.message}';
    }

    if (error is TimeoutException) {
      return 'Request timed out. Please try again.';
    }

    if (error is FileSystemException) {
      return error.message.isNotEmpty
          ? 'File error: ${error.message}'
          : 'File error: Unable to read the selected file.';
    }

    final text = error.toString().trim();
    if (text.isEmpty || text == 'Exception') {
      return 'Upload failed. Please try again.';
    }
    return text;
  }
}

