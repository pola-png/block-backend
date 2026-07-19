import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:share_plus/share_plus.dart';

class ShareUtils {
  static String _siteBaseUrl() {
    final raw = dotenv.env['XAPZAP_SITE_URL']?.trim();
    if (raw == null || raw.isEmpty) {
      return 'https://www.xapzap.com';
    }
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  static Future<void> sharePost({
    required String postId,
    required String username,
    required String content,
  }) async {
    final String url = '${_siteBaseUrl()}/p/$postId';
    final normalizedContent = content.trim();
    final String shareText =
        normalizedContent.isNotEmpty ? '"$normalizedContent"\n\n$url' : url;
    final params = ShareParams(text: shareText, subject: 'XapZap post');
    try {
      await SharePlus.instance.share(params);
    } catch (e) {
      await SharePlus.instance.share(ShareParams(text: url, subject: 'XapZap post'));
    }
  }

  static Future<void> shareProfile({
    required String username,
    required String displayName,
  }) async {
    final String url = '${_siteBaseUrl()}/@$username';
    final String shareText = 'Check out $displayName (@$username) on XapZap!\n$url';
    final params = ShareParams(text: shareText, subject: 'XapZap profile');
    try {
      await SharePlus.instance.share(params);
    } catch (e) {
      await SharePlus.instance.share(ShareParams(text: url, subject: 'XapZap profile'));
    }
  }
}
