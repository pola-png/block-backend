import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';

class AppReviewService {
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.xapzap.app';

  static final InAppReview _inAppReview = InAppReview.instance;

  /// Exposes the InAppReview instance for direct use (e.g. requestReview()).
  static InAppReview get inAppReview => _inAppReview;

  /// Requests a native in-app review popup. 
  /// Falls back to launching the store URL if in-app review is unavailable.
  static Future<void> requestReview() async {
    try {
      if (await _inAppReview.isAvailable()) {
        await _inAppReview.requestReview();
      } else {
        await openStoreListing();
      }
    } catch (_) {
      await openStoreListing();
    }
  }

  /// Opens the store listing via browser/Play Store app as fallback.
  static Future<void> openStoreListing() async {
    final uri = Uri.parse(_playStoreUrl);
    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }
}
