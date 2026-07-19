import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class VideoCacheService {
  VideoCacheService._();

  static final BaseCacheManager _cache = DefaultCacheManager();
  static final Set<String> _warmingUrls = <String>{};

  static Future<File?> getCachedFileIfAvailable(String url) async {
    if (kIsWeb || url.trim().isEmpty) return null;
    try {
      final cached = await _cache.getFileFromCache(url.trim());
      final file = cached?.file;
      if (file == null) return null;
      if (!await file.exists()) return null;
      return file;
    } catch (_) {
      return null;
    }
  }

  static Future<File?> cacheVideo(String url) async {
    if (kIsWeb || url.trim().isEmpty) return null;
    final safeUrl = url.trim();
    try {
      return await _cache.getSingleFile(safeUrl);
    } catch (_) {
      return null;
    }
  }

  static void warm(String url) {
    if (kIsWeb || url.trim().isEmpty) return;
    final safeUrl = url.trim();
    if (_warmingUrls.contains(safeUrl)) return;
    _warmingUrls.add(safeUrl);
    unawaited(
      cacheVideo(safeUrl).whenComplete(() {
        _warmingUrls.remove(safeUrl);
      }),
    );
  }
}
