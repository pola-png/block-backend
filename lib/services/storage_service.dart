import 'dart:io';
import 'dart:math';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'network_status_service.dart';

/// Storage helper managing Supabase Storage uploads to the 'Xapzapmedia' bucket.
class StorageService {
  static const String _bucket = 'Xapzapmedia';
  static const String _projectId = 'tnjmwahnzosuhqpkvuwo';

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

  // ---------------------------------------------------------------------------
  // Public URL builder
  // ---------------------------------------------------------------------------

  static String _publicUrl(String storagePath) {
    return 'https://$_projectId.supabase.co/storage/v1/object/public/$_bucket/$storagePath';
  }

  // ---------------------------------------------------------------------------
  // URL resolution (backward-compat with previously stored URLs / appwrite:// refs)
  // ---------------------------------------------------------------------------

  static final Map<String, String> _displayUrlCache = <String, String>{};

  static String getImageDisplayUrlSync(String value) {
    if (value.isEmpty) return value;
    final cached = _displayUrlCache[value];
    if (cached != null) return cached;
    // Already a full https URL — return as-is
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    // Legacy appwrite:// scheme → remap file ID into Supabase public URL
    if (value.startsWith('appwrite://')) {
      final uri = Uri.tryParse(value);
      final segments = uri?.pathSegments ?? [];
      final fileId = segments.isNotEmpty ? segments.first : '';
      final resolved = _publicUrl(fileId);
      _displayUrlCache[value] = resolved;
      return resolved;
    }
    return value;
  }

  static Future<String> getImageDisplayUrl(String value) async =>
      getImageDisplayUrlSync(value);

  static Future<String> getVideoDisplayUrl(String value) async =>
      getImageDisplayUrlSync(value);

  static String getVideoDisplayUrlSync(String value) =>
      getImageDisplayUrlSync(value);

  static Future<String> getSignedUrl(String key, {int expires = 3600}) async =>
      getImageDisplayUrlSync(key);

  static bool _looksLikeVideo(String value) {
    final n = value.toLowerCase();
    return n.endsWith('.mp4') ||
        n.endsWith('.mov') ||
        n.endsWith('.webm') ||
        n.endsWith('.mkv') ||
        n.endsWith('.m4v') ||
        n.endsWith('.m3u8');
  }

  // ---------------------------------------------------------------------------
  // Core upload — writes bytes directly to Supabase Storage
  // ---------------------------------------------------------------------------

  static Future<String> _uploadFile(File file, String storagePath) async {
    const attempts = 3;
    Object? lastError;

    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) throw StateError('Upload file is empty.');

        final ext = p.extension(storagePath).toLowerCase();
        final mimeType = _looksLikeVideo(storagePath)
            ? 'video/${ext.isEmpty ? 'mp4' : ext.substring(1)}'
            : 'image/${ext.isEmpty ? 'jpeg' : ext.substring(1)}';

        try {
          await Supabase.instance.client.storage.createBucket(
            _bucket,
            const BucketOptions(public: true),
          );
        } catch (_) {}

        await Supabase.instance.client.storage
            .from(_bucket)
            .uploadBinary(
              storagePath,
              bytes,
              fileOptions: FileOptions(
                contentType: mimeType,
                upsert: true,
              ),
            ).timeout(const Duration(minutes: 3));

        final url = _publicUrl(storagePath);
        _displayUrlCache[storagePath] = url;
        return url;
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

  // ---------------------------------------------------------------------------
  // Public upload helpers (same signatures as before — no callers need changes)
  // ---------------------------------------------------------------------------

  static Future<String> uploadFileAtPath(File file, String objectPath) =>
      _uploadFile(file, objectPath);

  static Future<List<String>> uploadMultiplePostMedia(
    List<XFile> files,
    String userId,
  ) async {
    final List<String> urls = [];
    for (final file in files) {
      final ext = p.extension(file.path);
      final key =
          'posts/$userId/media_${DateTime.now().millisecondsSinceEpoch}$ext';
      final url = await _uploadFile(File(file.path), key);
      urls.add(url);
    }
    return urls;
  }

  static Future<String?> uploadVoiceComment(
      String path, String userId) async {
    try {
      final ext = p.extension(path);
      final key =
          'comments/$userId/voice_${DateTime.now().millisecondsSinceEpoch}$ext';
      return await _uploadFile(File(path), key);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> uploadProfileImage(XFile file, String userId) async {
    try {
      final ext = p.extension(file.path);
      final key =
          'profiles/$userId/avatar_${DateTime.now().millisecondsSinceEpoch}$ext';
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
      return await _uploadFile(File(file.path), key);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> uploadThumbnail(File file, String userId) async {
    try {
      final key =
          'posts/$userId/thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
      return await _uploadFile(file, key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteFile(String path) async {
    try {
      String storagePath = path;
      if (path.contains('/object/public/$_bucket/')) {
        storagePath = path.split('/object/public/$_bucket/').last;
      } else if (path.startsWith('appwrite://')) {
        final uri = Uri.tryParse(path);
        final segments = uri?.pathSegments ?? [];
        storagePath = segments.isNotEmpty ? segments.first : '';
      }
      if (storagePath.isEmpty) return;
      await Supabase.instance.client.storage
          .from(_bucket)
          .remove([storagePath]);
    } catch (_) {}
  }
}
