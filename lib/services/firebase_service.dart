import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class FirebaseService {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized || Firebase.apps.isNotEmpty) {
      _initialized = true;
      return;
    }

    final options = _optionsFromEnv();
    if (options == null) {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          await Firebase.initializeApp();
          _initialized = true;
        } catch (_) {
          // Fall through and keep Firebase optional if the native
          // Android config file is not present yet.
        }
      }
      return;
    }

    try {
      await Firebase.initializeApp(options: options);
      _initialized = true;
    } catch (_) {
      // Firebase stays optional. The app continues without analytics
      // until the project config is supplied.
    }
  }

  static bool get isReady => _initialized || Firebase.apps.isNotEmpty;

  static FirebaseOptions? _optionsFromEnv() {
    final apiKey = _env('FIREBASE_API_KEY');
    final appId = _env('FIREBASE_APP_ID');
    final messagingSenderId = _env('FIREBASE_MESSAGING_SENDER_ID');
    final projectId = _env('FIREBASE_PROJECT_ID');

    if (apiKey.isEmpty ||
        appId.isEmpty ||
        messagingSenderId.isEmpty ||
        projectId.isEmpty) {
      return null;
    }

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: _env('FIREBASE_AUTH_DOMAIN').isEmpty
          ? null
          : _env('FIREBASE_AUTH_DOMAIN'),
      storageBucket: _env('FIREBASE_STORAGE_BUCKET').isEmpty
          ? null
          : _env('FIREBASE_STORAGE_BUCKET'),
      measurementId: _env('FIREBASE_MEASUREMENT_ID').isEmpty
          ? null
          : _env('FIREBASE_MEASUREMENT_ID'),
      databaseURL: _env('FIREBASE_DATABASE_URL').isEmpty
          ? null
          : _env('FIREBASE_DATABASE_URL'),
      androidClientId: _env('FIREBASE_ANDROID_CLIENT_ID').isEmpty
          ? null
          : _env('FIREBASE_ANDROID_CLIENT_ID'),
      iosClientId: _env('FIREBASE_IOS_CLIENT_ID').isEmpty
          ? null
          : _env('FIREBASE_IOS_CLIENT_ID'),
      iosBundleId: _env('FIREBASE_IOS_BUNDLE_ID').isEmpty
          ? null
          : _env('FIREBASE_IOS_BUNDLE_ID'),
    );
  }

  static String _env(String key) {
    try {
      return dotenv.env[key] ?? '';
    } catch (_) {
      return '';
    }
  }
}
