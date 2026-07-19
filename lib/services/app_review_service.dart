import 'package:url_launcher/url_launcher.dart';

class AppReviewService {
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=badmuscodehive.appldq';

  static Future<void> requestReview() async {
    await openStoreListing();
  }

  static Future<void> openStoreListing() async {
    final uri = Uri.parse(
      _playStoreUrl,
    );
    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }
}
