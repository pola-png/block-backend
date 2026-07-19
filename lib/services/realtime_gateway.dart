import 'package:flutter/foundation.dart';
import 'network_status_service.dart';

class RealtimeGateway {
  RealtimeGateway._();

  static final ValueNotifier<int> reconnectTrigger = ValueNotifier<int>(0);
  static bool _initialized = false;
  static bool _wasOffline = false;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    _wasOffline = NetworkStatusService.isOffline.value;
    NetworkStatusService.isOffline.addListener(_onNetworkStatusChanged);
  }

  static void _onNetworkStatusChanged() {
    final offline = NetworkStatusService.isOffline.value;
    if (_wasOffline && !offline) {
      // Transitioned from offline to online! Trigger reconnections.
      reconnectTrigger.value++;
    }
    _wasOffline = offline;
  }

  static void triggerManualReconnect() {
    reconnectTrigger.value++;
  }

  static void dispose() {
    NetworkStatusService.isOffline.removeListener(_onNetworkStatusChanged);
    _initialized = false;
  }
}
