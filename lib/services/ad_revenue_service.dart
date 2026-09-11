import 'dart:async';
import 'dart:convert';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'backend_service.dart';
import 'firebase_service.dart';

/// Lightweight helper to capture impression-level ad revenue (ILRD).
/// Tracks totals per ad format so banner/native/rewarded are separated.
class AdRevenueService {
  static const _totalByFormatKey = 'ad_rev_total_by_format';
  static const _countByFormatKey = 'ad_rev_count_by_format';
  static const _backendStatusKey = 'ad_backend_status_v1';

  static OnPaidEventCallback paidEventHandler({
    required String adUnitId,
    required String format,
    required String placement,
  }) {
    return (ad, valueMicros, precision, currencyCode) {
      unawaited(
        recordPaidEvent(
          adUnitId: adUnitId,
          format: format,
          placement: placement,
          valueMicros: valueMicros.round(),
          currencyCode: currencyCode,
          precisionType: precision.index,
        ),
      );
    };
  }

  /// Record a paid event locally. You can extend this to send to your backend.
  static Future<void> recordPaidEvent({
    required String adUnitId,
    required String format, // e.g. rewarded, banner, native, interstitial
    required String placement,
    required int valueMicros,
    required String? currencyCode,
    required int? precisionType,
    String? countryCode, // ISO 3166-1 alpha-2
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final totals = await _readCounterMap(prefs, _totalByFormatKey);
    final counts = await _readCounterMap(prefs, _countByFormatKey);

    totals[format] = (totals[format] ?? 0) + valueMicros;
    counts[format] = (counts[format] ?? 0) + 1;

    await _writeCounterMap(prefs, _totalByFormatKey, totals);
    await _writeCounterMap(prefs, _countByFormatKey, counts);

    if (FirebaseService.isReady) {
      try {
        final analyticsParams = <String, Object>{
          'ad_unit_id': adUnitId,
          'format': format,
          'placement': placement,
          'value_micros': valueMicros,
        };
        if (currencyCode != null && currencyCode.isNotEmpty) {
          analyticsParams['currency'] = currencyCode;
        }
        if (precisionType != null) {
          analyticsParams['precision'] = precisionType;
        }
        if (countryCode != null && countryCode.isNotEmpty) {
          analyticsParams['country'] = countryCode;
        }
        await FirebaseAnalytics.instance.logEvent(
          name: 'ad_paid_event',
          parameters: analyticsParams,
        );
      } catch (_) {
        // Firebase Analytics stays best-effort.
      }
    }

    // Send to Appwrite for server-side payout tracking (best-effort).
    try {
      final user = await BackendService.getCurrentUser();
      await BackendService.createDocument(
        BackendService.adRevenueCollectionId,
        {
          'userId': user?.$id,
          'adUnitId': adUnitId,
          'format': format,
          'placement': placement,
          'valueMicros': valueMicros,
          'currency': currencyCode,
          'country': countryCode,
          'precision': precisionType,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      await _writeBackendStatus(
        table: BackendService.adRevenueCollectionId,
        success: true,
      );
    } catch (_) {
      await _writeBackendStatus(
        table: BackendService.adRevenueCollectionId,
        success: false,
        message:
            'Failed to write ad revenue event to Appwrite. Check table permissions and schema.',
      );
    }
  }

  static Future<void> recordCreatorImpression({
    required String adUnitId,
    required String creatorId,
    required String format,
    required String placement,
    String? postId,
  }) async {
    final safeCreatorId = creatorId.trim();
    final safeAdUnitId = adUnitId.trim();
    if (safeCreatorId.isEmpty || safeAdUnitId.isEmpty) return;

    try {
      final user = await BackendService.getCurrentUser();
      final now = DateTime.now().toUtc();
      await BackendService.createDocument(
        BackendService.adImpressionsCollectionId,
        {
          'creatorId': safeCreatorId,
          'viewerUserId': user?.$id,
          'adUnitId': safeAdUnitId,
          'format': format,
          'placement': placement,
          'postId': postId,
          'impressions': 1,
          'eventDate': now.toIso8601String(),
          'createdAt': now.toIso8601String(),
        },
      );
      await _writeBackendStatus(
        table: BackendService.adImpressionsCollectionId,
        success: true,
      );
    } catch (_) {
      await _writeBackendStatus(
        table: BackendService.adImpressionsCollectionId,
        success: false,
        message:
            'Failed to write creator ad impression to Appwrite. Check table permissions and schema.',
      );
    }
  }

  /// Returns locally accumulated micros per format.
  static Future<Map<String, int>> getTotalsByFormat() async {
    final prefs = await SharedPreferences.getInstance();
    return _readCounterMap(prefs, _totalByFormatKey);
  }

  /// Returns event counts per format.
  static Future<Map<String, int>> getCountsByFormat() async {
    final prefs = await SharedPreferences.getInstance();
    return _readCounterMap(prefs, _countByFormatKey);
  }

  static Future<Map<String, dynamic>> getBackendStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_backendStatusKey);
    if (raw == null || raw.isEmpty) {
      return const <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? decoded
          : const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  static Future<void> recordSyncResult({
    required bool success,
    String? message,
  }) async {
    await _writeBackendStatus(
      table: 'admob_sync',
      success: success,
      message: message,
    );
  }

  static Future<Map<String, int>> _readCounterMap(
    SharedPreferences prefs,
    String key,
  ) async {
    final raw = prefs.getStringList(key) ?? const <String>[];
    final map = <String, int>{};
    for (final entry in raw) {
      final parts = entry.split('|');
      if (parts.length != 2) continue;
      final name = parts[0].trim();
      final value = int.tryParse(parts[1].trim()) ?? 0;
      if (name.isEmpty) continue;
      map[name] = value;
    }
    return map;
  }

  static Future<void> _writeCounterMap(
    SharedPreferences prefs,
    String key,
    Map<String, int> values,
  ) async {
    await prefs.setStringList(
      key,
      values.entries.map((e) => '${e.key}|${e.value}').toList(growable: false),
    );
  }

  static Future<void> _writeBackendStatus({
    required String table,
    required bool success,
    String? message,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await getBackendStatus();
    final next = <String, dynamic>{
      ...existing,
      'lastTable': table,
      'lastSuccess': success,
      'lastCheckedAt': DateTime.now().toIso8601String(),
      'lastMessage': message ?? (success ? 'OK' : 'Unknown backend error'),
    };
    await prefs.setString(_backendStatusKey, jsonEncode(next));
  }
}
