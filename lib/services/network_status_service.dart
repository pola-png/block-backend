import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;



enum NetworkBannerState {
  hidden,
  offline,
  online,
}

class NetworkStatusService {
  NetworkStatusService._();

  static final ValueNotifier<bool> isOffline = ValueNotifier<bool>(false);
  static final ValueNotifier<NetworkBannerState> bannerState =
      ValueNotifier<NetworkBannerState>(NetworkBannerState.hidden);
  static bool _initialized = false;
  static Timer? _onlineBannerTimer;
  static Timer? _offlineDelayTimer;
  static Timer? _retryTimer;
  static StreamSubscription<List<ConnectivityResult>>? _subscription;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Check initial connectivity
    try {
      final initialResults = await Connectivity().checkConnectivity();
      await _updateState(initialResults);
    } catch (_) {}

    // Listen for changes
    _subscription?.cancel();
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      unawaited(_updateState(results));
    });
  }

  static Future<void> refresh() async {
    try {
      final results = await Connectivity().checkConnectivity();
      await _updateState(results);
    } catch (_) {}
  }

  static void _scheduleRetryCheck() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 4), () {
      refresh();
    });
  }

  static Future<void> _updateState(List<ConnectivityResult> results) async {
    final hasNoInterface = results.isEmpty || results.contains(ConnectivityResult.none);
    bool offline = hasNoInterface;
    if (!hasNoInterface) {
      // Validate that the network is actually reachable
      offline = !await _hasReachableNetwork();
    }

    if (offline) {
      if (!hasNoInterface) {
        _scheduleRetryCheck();
      }
      if (isOffline.value) {
        return;
      }
      _offlineDelayTimer ??= Timer(const Duration(minutes: 1), () {
        isOffline.value = true;
        bannerState.value = NetworkBannerState.offline;
        _offlineDelayTimer = null;
      });
    } else {
      _offlineDelayTimer?.cancel();
      _offlineDelayTimer = null;
      _retryTimer?.cancel();
      _retryTimer = null;

      if (isOffline.value) {
        isOffline.value = false;
        bannerState.value = NetworkBannerState.online;
        _onlineBannerTimer?.cancel();
        _onlineBannerTimer = Timer(
          const Duration(seconds: 1),
          () {
            if (!isOffline.value) {
              bannerState.value = NetworkBannerState.hidden;
            }
          },
        );
      } else {
        bannerState.value = NetworkBannerState.hidden;
      }
    }
  }

  static Future<bool> _hasReachableNetwork() async {
    try {
      // clients3.google.com/generate_204 is a highly available global edge endpoint
      // returning a 204 No Content response instantly.
      // We use a HEAD request with a 1.5 second timeout to keep the check ultra-fast.
      final uri = Uri.parse('https://clients3.google.com/generate_204');
      final response =
          await http.head(uri).timeout(const Duration(milliseconds: 1500));
      return response.statusCode == 204 ||
          (response.statusCode >= 200 && response.statusCode < 400);
    } catch (_) {
      return false;
    }
  }

  static void dispose() {
    _subscription?.cancel();
    _onlineBannerTimer?.cancel();
    _offlineDelayTimer?.cancel();
    _retryTimer?.cancel();
  }
}
