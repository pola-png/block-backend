import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

enum LiveKitMediaStatus {
  disconnected,
  connecting,
  connected,
  reconnectingGracePeriod,
}

/// Dedicated LiveKit Media Session Manager
/// Connects to LiveKit Cloud SFU WebRTC server and manages camera/mic publishing and subscriptions.
class LiveKitMediaSessionManager {
  LiveKitMediaSessionManager._internal();
  static final LiveKitMediaSessionManager instance = LiveKitMediaSessionManager._internal();

  lk.Room? _room;
  lk.Room? get room => _room;

  // Observable Media Session State
  final ValueNotifier<LiveKitMediaStatus> statusNotifier =
      ValueNotifier<LiveKitMediaStatus>(LiveKitMediaStatus.disconnected);
  final ValueNotifier<int> graceSecondsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> isMediaActiveNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String?> activeStreamIdNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<String?> livekitTokenNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<String?> livekitUrlNotifier = ValueNotifier<String?>('wss://xapzap-bu7rsekx.livekit.cloud');
  final ValueNotifier<lk.VideoTrack?> remoteVideoTrackNotifier = ValueNotifier<lk.VideoTrack?>(null);
  final ValueNotifier<lk.VideoTrack?> localVideoTrackNotifier = ValueNotifier<lk.VideoTrack?>(null);

  // Configuration
  static const int defaultGracePeriodSeconds = 20;

  Timer? _graceTimer;
  int _graceRemaining = 0;
  bool _hadActivePublishers = false;

  void setMediaToken(String? token, String? url) {
    if (token != null && token.isNotEmpty) {
      livekitTokenNotifier.value = token;
    }
    if (url != null && url.isNotEmpty) {
      livekitUrlNotifier.value = url;
    }
  }

  /// Connect to LiveKit WebRTC Cloud
  Future<void> connectLiveKitRoom({
    required String url,
    required String token,
    bool isHost = false,
    bool isInvitee = false,
  }) async {
    if (token.isEmpty) return;
    try {
      if (_room != null) {
        try {
          await _room!.disconnect();
          await _room!.dispose();
        } catch (_) {}
        _room = null;
      }

      statusNotifier.value = LiveKitMediaStatus.connecting;
      debugPrint('[LiveKit] Connecting to $url with token: ${token.substring(0, token.length > 20 ? 20 : token.length)}...');

      final room = lk.Room(
        roomOptions: const lk.RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultCameraCaptureOptions: lk.CameraCaptureOptions(
            cameraPosition: lk.CameraPosition.front,
            maxFrameRate: 30,
          ),
        ),
      );

      _room = room;
      room.addListener(_onRoomUpdated);

      await room.connect(url, token);
      statusNotifier.value = LiveKitMediaStatus.connected;
      isMediaActiveNotifier.value = true;
      debugPrint('[LiveKit] Successfully connected to LiveKit room: ${room.name}');

      if (isHost) {
        debugPrint('[LiveKit] Publishing host camera & microphone to LiveKit Cloud...');
        await room.localParticipant?.setCameraEnabled(true);
        await room.localParticipant?.setMicrophoneEnabled(true);
      } else if (isInvitee) {
        debugPrint('[LiveKit] Publishing invitee microphone to LiveKit Cloud...');
        await room.localParticipant?.setMicrophoneEnabled(true);
      }

      _onRoomUpdated();
    } catch (e) {
      debugPrint('[LiveKit] Connect error: $e');
      statusNotifier.value = LiveKitMediaStatus.disconnected;
    }
  }

  void _onRoomUpdated() {
    if (_room == null) return;
    
    // Update local video track for host
    final localPubs = _room!.localParticipant?.videoTrackPublications;
    lk.VideoTrack? localTrack;
    if (localPubs != null && localPubs.isNotEmpty) {
      localTrack = localPubs.first.track as lk.VideoTrack?;
    }
    localVideoTrackNotifier.value = localTrack;

    // Update remote host video track for viewers
    lk.VideoTrack? hostTrack;
    for (final participant in _room!.remoteParticipants.values) {
      for (final pub in participant.videoTrackPublications) {
        if (pub.track != null && pub.subscribed) {
          hostTrack = pub.track as lk.VideoTrack?;
          break;
        }
      }
      if (hostTrack != null) break;
    }
    remoteVideoTrackNotifier.value = hostTrack;
  }

  Future<void> disconnectLiveKitRoom() async {
    try {
      if (_room != null) {
        _room!.removeListener(_onRoomUpdated);
        await _room!.disconnect();
        await _room!.dispose();
        _room = null;
      }
      localVideoTrackNotifier.value = null;
      remoteVideoTrackNotifier.value = null;
      statusNotifier.value = LiveKitMediaStatus.disconnected;
      isMediaActiveNotifier.value = false;
      debugPrint('[LiveKit] Disconnected from LiveKit Cloud.');
    } catch (_) {}
  }

  /// Evaluate publishers count and transition LiveKit media session accordingly
  void syncPublishersState({
    required bool hasHost,
    required int activeInviteesCount,
    String? streamId,
  }) {
    final totalPublishers = (hasHost ? 1 : 0) + activeInviteesCount;
    activeStreamIdNotifier.value = streamId;

    if (totalPublishers > 0) {
      _cancelGracePeriod();
      _hadActivePublishers = true;
      if (statusNotifier.value != LiveKitMediaStatus.connected && statusNotifier.value != LiveKitMediaStatus.connecting) {
        final token = livekitTokenNotifier.value;
        final url = livekitUrlNotifier.value ?? 'wss://xapzap-bu7rsekx.livekit.cloud';
        if (token != null && token.isNotEmpty) {
          connectLiveKitRoom(url: url, token: token, isHost: false);
        }
      }
    } else {
      if (_hadActivePublishers && statusNotifier.value == LiveKitMediaStatus.connected) {
        _startGracePeriod();
      } else if (statusNotifier.value != LiveKitMediaStatus.reconnectingGracePeriod) {
        disconnectLiveKitRoom();
      }
    }
  }

  void _startGracePeriod() {
    debugPrint('[LiveKitMediaManager] Publisher dropped. Starting $defaultGracePeriodSeconds-second grace period...');
    _graceTimer?.cancel();
    _graceRemaining = defaultGracePeriodSeconds;
    graceSecondsNotifier.value = _graceRemaining;
    statusNotifier.value = LiveKitMediaStatus.reconnectingGracePeriod;

    _graceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _graceRemaining--;
      graceSecondsNotifier.value = _graceRemaining;

      if (_graceRemaining <= 0) {
        timer.cancel();
        _graceTimer = null;
        debugPrint('[LiveKitMediaManager] Grace period expired. Disconnecting LiveKit.');
        disconnectLiveKitRoom();
      }
    });
  }

  void _cancelGracePeriod() {
    if (_graceTimer != null) {
      _graceTimer?.cancel();
      _graceTimer = null;
    }
    _graceRemaining = 0;
    graceSecondsNotifier.value = 0;
  }

  void dispose() {
    _cancelGracePeriod();
    disconnectLiveKitRoom();
  }
}
