import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../config/environment.dart';
import 'network_status_service.dart';

/// Storage helper managing Appwrite Storage uploads and legacy Bunny CDN paths.
class StorageService {
  static const String _mediaBucketId = '6915baaa00381391d7b2';

  static Client? _client;
  static Storage? _storage;
  static String? _legacyStorageZone;
  static String? _legacyStorageKey;
  static String? _legacyStorageHost;
  static bool _initialized = false;
  static final Map<String, String> _displayUrlCache = <String, String>{};

  static Future<void> initialize() async {
    _client = Client()
        .setEndpoint(Environment.appwritePublicEndpoint)
        .setProject(Environment.appwriteProjectId);
    _storage = Storage(_client!);
    _legacyStorageZone = _readEnv('BUNNY_STORAGE_ZONE') ?? 'xapzap';
    _legacyStorageKey = _readEnv('BUNNY_STORAGE_KEY');
    _legacyStorageHost =
        _readEnv('BUNNY_STORAGE_HOST') ?? 'storage.bunnycdn.com';
    _initialized = true;
  }

  static String? _readEnv(String key) {
    try {
      final value = dotenv.env[key];
      if (value == null) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  static String _buildAppwriteKey({
    required String bucketId,
    required String fileId,
    required String fileName,
  }) {
    final safeName = Uri.encodeComponent(fileName.trim().isEmpty ? fileId : fileName);
    return 'appwrite://$bucketId/$fileId/$safeName';
  }

  static Future<String> _stableUploadFileId(
    File file,
    String objectPath,
  ) async {
    final length = await file.length();
    final seed = '$objectPath|$length';
    final hash = md5.convert(utf8.encode(seed)).toString();
    return 'u${hash.substring(0, 32)}';
  }

  static bool _isTransientUploadError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('broken pipe') ||
        text.contains('connection reset by peer') ||
        text.contains('connection aborted') ||
        text.contains('socketexception') ||
        text.contains('clientexception') ||
        text.contains('timed out') ||
        text.contains('timeout');
  }

  static Future<models.File> _createStorageFile({
    required String bucketId,
    required String fileId,
    required File file,
    required String fileName,
    required bool forceBytes,
  }) async {
    final storage = _storage!;
    if (kIsWeb || forceBytes) {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw StateError('Upload file is empty.');
      }
      return storage.createFile(
        bucketId: bucketId,
        fileId: fileId,
        file: InputFile.fromBytes(
          bytes: bytes,
          filename: fileName,
        ),
      );
    }

    return storage.createFile(
      bucketId: bucketId,
      fileId: fileId,
      file: InputFile.fromPath(path: file.path, filename: fileName),
    );
  }



  static Uri _buildLegacyStorageUri(String path) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return Uri.https(_legacyStorageHost!, '${_legacyStorageZone!}/$cleanPath');
  }

  static String _buildLegacyCdnUrl(String path) {
    // The legacy Bunny CDN Pull Zone is suspended, so return an empty string
    // to bypass failing requests and trigger local UI default fallbacks instantly.
    return '';
  }

  static _AppwriteMediaRef? _parseAppwriteRef(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('appwrite://')) {
      final uri = Uri.tryParse(trimmed);
      final bucketId = uri?.host ?? '';
      final fileId = uri?.pathSegments.isNotEmpty == true
          ? uri!.pathSegments.first
          : '';
      final fileName = uri != null && uri.pathSegments.length > 1
          ? Uri.decodeComponent(uri.pathSegments.sublist(1).join('/'))
          : '';
      if (bucketId.isEmpty || fileId.isEmpty) return null;
      return _AppwriteMediaRef(
        bucketId: bucketId,
        fileId: fileId,
        fileName: fileName,
      );
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    if ((uri.path == '/api/image-proxy' || uri.path == '/api/video-proxy') &&
        uri.queryParameters.containsKey('path')) {
      final rawPath = uri.queryParameters['path']?.trim() ?? '';
      if (rawPath.isEmpty) return null;
      return _parseAppwriteRef(rawPath);
    }

    final segments = uri.pathSegments;
    final bucketsIndex = segments.indexOf('buckets');
    final filesIndex = segments.indexOf('files');
    if (bucketsIndex >= 0 &&
        filesIndex == bucketsIndex + 2 &&
        filesIndex + 1 < segments.length) {
      final bucketId = segments[bucketsIndex + 1];
      final fileId = segments[filesIndex + 1];
      final fileName = uri.queryParameters['filename']?.trim() ?? '';
      if (bucketId.isEmpty || fileId.isEmpty) return null;
      return _AppwriteMediaRef(
        bucketId: bucketId,
        fileId: fileId,
        fileName: fileName,
      );
    }

    return null;
  }

  static String _fileNameHint(String value) {
    final appwriteRef = _parseAppwriteRef(value);
    if (appwriteRef != null && appwriteRef.fileName.isNotEmpty) {
      return appwriteRef.fileName.toLowerCase();
    }
    final uri = Uri.tryParse(value);
    final filename = uri?.queryParameters['filename']?.toLowerCase();
    if (filename != null && filename.isNotEmpty) {
      return filename;
    }
    if ((uri?.path == '/api/image-proxy' || uri?.path == '/api/video-proxy') &&
        uri?.queryParameters.containsKey('path') == true) {
      return (uri!.queryParameters['path'] ?? '').toLowerCase();
    }
    return value.toLowerCase();
  }

  static bool _looksLikeVideo(String value) {
    final normalized = _fileNameHint(value);
    return normalized.endsWith('.mp4') ||
        normalized.endsWith('.mov') ||
        normalized.endsWith('.webm') ||
        normalized.endsWith('.mkv') ||
        normalized.endsWith('.m4v') ||
        normalized.endsWith('.m3u8') ||
        normalized.contains('/api/video-proxy') ||
        (normalized.contains('/videos/') &&
            !normalized.contains('/thumb_') &&
            !normalized.contains('thumbnail'));
  }

  static bool _looksLikeImage(String value) {
    final normalized = _fileNameHint(value);
    return normalized.endsWith('.jpg') ||
        normalized.endsWith('.jpeg') ||
        normalized.endsWith('.png') ||
        normalized.endsWith('.webp') ||
        normalized.endsWith('.gif') ||
        normalized.endsWith('.bmp') ||
        normalized.endsWith('.svg') ||
        normalized.contains('thumbnail') ||
        normalized.contains('/thumb_') ||
        normalized.contains('/posts/') ||
        normalized.contains('/avatars/') ||
        normalized.contains('/covers/') ||
        normalized.contains('/profiles/') ||
        normalized.contains('/api/image-proxy');
  }

  static String? _extractLegacyObjectKey(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || _parseAppwriteRef(trimmed) != null) {
      return null;
    }
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      if (trimmed.startsWith('/media/')) {
        return trimmed.substring(1);
      }
      return trimmed.replaceFirst(RegExp(r'^/+'), '');
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return null;
    }

    if ((uri.path == '/api/image-proxy' || uri.path == '/api/video-proxy') &&
        uri.queryParameters.containsKey('path')) {
      final path = uri.queryParameters['path'];
      if (path == null || path.trim().isEmpty) {
        return null;
      }
      return path.trim();
    }

    final path = uri.path;
    final mediaIndex = path.indexOf('/media/');
    if (mediaIndex >= 0) {
      return path.substring(mediaIndex + 1);
    }

    if (uri.host.contains('b-cdn.net') ||
        uri.host.contains('bunnycdn.com')) {
      return path.replaceFirst(RegExp(r'^/+'), '');
    }

    return null;
  }

  static String _buildAppwriteFileViewUrl(_AppwriteMediaRef ref) {
    final base =
        '${Environment.appwritePublicEndpoint}/storage/buckets/${ref.bucketId}/files/${ref.fileId}/view';
    final query = <String, String>{
      'project': Environment.appwriteProjectId,
      'mode': 'public',
      if (ref.fileName.isNotEmpty) 'filename': ref.fileName,
    };
    return Uri.parse(base).replace(queryParameters: query).toString();
  }

  static String getImageDisplayUrlSync(String value) {
    final cached = _displayUrlCache[value];
    if (cached != null) return cached;

    final appwriteRef = _parseAppwriteRef(value);
    if (appwriteRef != null) {
      final resolved = _buildAppwriteFileViewUrl(appwriteRef);
      _displayUrlCache[value] = resolved;
      _displayUrlCache[resolved] = resolved;
      _displayUrlCache[_buildAppwriteKey(
        bucketId: appwriteRef.bucketId,
        fileId: appwriteRef.fileId,
        fileName: appwriteRef.fileName,
      )] = resolved;
      return resolved;
    }

    final objectKey = _extractLegacyObjectKey(value);
    if (objectKey == null) {
      return value;
    }
    final resolved = _buildLegacyCdnUrl(objectKey);
    _displayUrlCache[value] = resolved;
    _displayUrlCache[resolved] = resolved;
    _displayUrlCache[objectKey] = resolved;
    return resolved;
  }

  static Future<String> getImageDisplayUrl(String value) async {
    await _ensureInitialized();
    final cached = _displayUrlCache[value];
    if (cached != null) return cached;

    final appwriteRef = _parseAppwriteRef(value);
    if (appwriteRef != null) {
      final resolved = _buildAppwriteFileViewUrl(appwriteRef);
      _displayUrlCache[value] = resolved;
      _displayUrlCache[resolved] = resolved;
      _displayUrlCache[_buildAppwriteKey(
        bucketId: appwriteRef.bucketId,
        fileId: appwriteRef.fileId,
        fileName: appwriteRef.fileName,
      )] = resolved;
      return resolved;
    }

    final objectKey = _extractLegacyObjectKey(value);
    if (objectKey == null) {
      return value;
    }
    final resolved = _buildLegacyCdnUrl(objectKey);
    _displayUrlCache[value] = resolved;
    _displayUrlCache[objectKey] = resolved;
    return resolved;
  }

  static Future<String> getVideoDisplayUrl(String value) async {
    await _ensureInitialized();
    final cached = _displayUrlCache[value];
    if (cached != null) return cached;

    final appwriteRef = _parseAppwriteRef(value);
    if (appwriteRef != null) {
      final resolved = _buildAppwriteFileViewUrl(appwriteRef);
      _displayUrlCache[value] = resolved;
      _displayUrlCache[resolved] = resolved;
      _displayUrlCache[_buildAppwriteKey(
        bucketId: appwriteRef.bucketId,
        fileId: appwriteRef.fileId,
        fileName: appwriteRef.fileName,
      )] = resolved;
      return resolved;
    }

    final objectKey = _extractLegacyObjectKey(value);
    if (objectKey == null) {
      return value;
    }
    final resolved = _buildLegacyCdnUrl(objectKey);
    _displayUrlCache[value] = resolved;
    _displayUrlCache[objectKey] = resolved;
    return resolved;
  }

  static String getVideoDisplayUrlSync(String value) {
    return getImageDisplayUrlSync(value);
  }

  static Future<String> getSignedUrl(String key, {int expires = 3600}) async {
    await _ensureInitialized();
    final cached = _displayUrlCache[key];
    if (cached != null) return cached;

    if (_parseAppwriteRef(key) != null) {
      return _looksLikeVideo(key) ? getVideoDisplayUrl(key) : getImageDisplayUrl(key);
    }

    final subject = _extractLegacyObjectKey(key) ?? key;
    if (_looksLikeVideo(subject)) {
      return getVideoDisplayUrl(key);
    }
    if (_looksLikeImage(subject)) {
      return getImageDisplayUrl(key);
    }
    if (key.startsWith('http://') || key.startsWith('https://')) {
      _displayUrlCache[key] = key;
      return key;
    }
    final resolved = _buildLegacyCdnUrl(key);
    _displayUrlCache[key] = resolved;
    return resolved;
  }

  static Future<String> _uploadToBunny(File file, String objectPath) async {
    await _ensureInitialized();
    if (_legacyStorageKey == null || _legacyStorageKey!.isEmpty) {
      throw StateError('Bunny Storage Key is not configured.');
    }
    final key = objectPath.startsWith('/') ? objectPath.substring(1) : objectPath;
    final uri = Uri.https(_legacyStorageHost!, '${_legacyStorageZone!}/$key');
    final bytes = await file.readAsBytes();
    final client = HttpClient();
    try {
      final request = await client.putUrl(uri);
      request.headers.set('AccessKey', _legacyStorageKey!);
      request.headers.set('Content-Length', bytes.length.toString());
      request.add(bytes);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Bunny Storage upload failed (${response.statusCode})');
      }
      return _buildLegacyCdnUrl(key);
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> _uploadFile(File file, String objectPath) async {
    await _ensureInitialized();
    final fileName = p.basename(objectPath).trim().isEmpty
        ? p.basename(file.path)
        : p.basename(objectPath);
    final fileId = await _stableUploadFileId(file, objectPath);
    final attempts = 3;
    Object? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final created = await _createStorageFile(
          bucketId: _mediaBucketId,
          fileId: fileId,
          file: file,
          fileName: fileName,
          forceBytes: kIsWeb,
        );
        final ref = _AppwriteMediaRef(
          bucketId: created.bucketId,
          fileId: created.$id,
          fileName: created.name,
        );
        return _buildAppwriteFileViewUrl(ref);
      } catch (error) {
        lastError = error;
        if (attempt == attempts - 1 || !_isTransientUploadError(error)) {
          rethrow;
        }
        final backoffMs = 750 * pow(2, attempt).toInt();
        while (NetworkStatusService.isOffline.value) {
          await Future<void>.delayed(const Duration(seconds: 2));
          await NetworkStatusService.refresh();
        }
        await Future<void>.delayed(Duration(milliseconds: backoffMs));
      }
    }
    throw lastError ?? StateError('Upload failed.');
  }

  /// Returns an Appwrite storage key in the form
  /// `appwrite://<bucket>/<fileId>/<filename>`.
  static Future<String> uploadFileAtPath(File file, String objectPath) {
    return _uploadFile(file, objectPath);
  }

  static Future<List<String>> uploadMultiplePostMedia(
    List<XFile> files,
    String userId,
  ) async {
    final List<String> urls = [];
    for (final file in files) {
      final ext = p.extension(file.path);
      final key =
          'posts/$userId/media_${DateTime.now().millisecondsSinceEpoch}$ext';
      final storedPath = await _uploadFile(File(file.path), key);
      urls.add(storedPath);
    }
    return urls;
  }

  static Future<String?> uploadVoiceComment(String path, String userId) async {
    try {
      final ext = p.extension(path);
      final key =
          'comments/$userId/voice_${DateTime.now().millisecondsSinceEpoch}$ext';
      final storedPath = await _uploadFile(File(path), key);
      return storedPath;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> uploadProfileImage(XFile file, String userId) async {
    try {
      final ext = p.extension(file.path);
      final key =
          'profiles/$userId/avatar_${DateTime.now().millisecondsSinceEpoch}$ext';
      if (_legacyStorageKey != null && _legacyStorageKey!.isNotEmpty) {
        return await _uploadToBunny(File(file.path), key);
      }
      return await _uploadFile(File(file.path), key);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> uploadProfileCover(XFile file, String userId) async {
    try {
      final ext = p.extension(file.path);
      final key =
          'profiles/$userId/cover_${DateTime.now().millisecondsSinceEpoch}$ext';
      if (_legacyStorageKey != null && _legacyStorageKey!.isNotEmpty) {
        return await _uploadToBunny(File(file.path), key);
      }
      return await _uploadFile(File(file.path), key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteFile(String path) async {
    await _ensureInitialized();
    final appwriteRef = _parseAppwriteRef(path);
    if (appwriteRef != null) {
      await _storage!.deleteFile(
        bucketId: appwriteRef.bucketId,
        fileId: appwriteRef.fileId,
      );
      return;
    }

    if (_legacyStorageKey == null) {
      return;
    }

    String? key = _extractLegacyObjectKey(path);
    key ??= path.startsWith('/') ? path.substring(1) : path;
    if (key.isEmpty) return;
    final uri = _buildLegacyStorageUri(key);
    final client = HttpClient();
    try {
      final request = await client.deleteUrl(uri);
      request.headers.set('AccessKey', _legacyStorageKey!);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Legacy Bunny delete failed (${response.statusCode})');
      }
    } finally {
      client.close(force: true);
    }
  }
}

class _AppwriteMediaRef {
  final String bucketId;
  final String fileId;
  final String fileName;

  const _AppwriteMediaRef({
    required this.bucketId,
    required this.fileId,
    required this.fileName,
  });
}

