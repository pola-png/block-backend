import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DeviceModeService {
  DeviceModeService._();

  static const MethodChannel _channel = MethodChannel('xapzap/device_mode');
  static bool _initialized = false;
  static bool _isTv = false;

  static bool get isTv => _isTv;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _isTv = false;
      return;
    }

    try {
      final result = await _channel.invokeMethod<bool>('isTvDevice');
      _isTv = result ?? false;
    } catch (_) {
      _isTv = false;
    }
  }
}
