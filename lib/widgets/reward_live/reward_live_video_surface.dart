import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import '../../models/reward_live_model.dart';
import '../../services/reward_live_media_service.dart';

class RewardLiveVideoSurface extends StatefulWidget {
  final RewardLiveState? liveState;
  final bool isMyUserHost;

  const RewardLiveVideoSurface({
    super.key,
    required this.liveState,
    required this.isMyUserHost,
  });

  @override
  State<RewardLiveVideoSurface> createState() => _RewardLiveVideoSurfaceState();
}

class _RewardLiveVideoSurfaceState extends State<RewardLiveVideoSurface>
    with SingleTickerProviderStateMixin {
  late AnimationController _ambientController;

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ambientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. If current user is host, render their LiveKit camera track
    if (widget.isMyUserHost) {
      return ValueListenableBuilder<lk.VideoTrack?>(
        valueListenable: LiveKitMediaSessionManager.instance.localVideoTrackNotifier,
        builder: (context, localTrack, _) {
          if (localTrack != null) {
            return SizedBox.expand(
              child: lk.VideoTrackRenderer(
                localTrack,
              ),
            );
          }
          return _buildHostWaitingSurface();
        },
      );
    }

    // 2. Observe LiveKit Media Session Manager State
    return ValueListenableBuilder<LiveKitMediaStatus>(
      valueListenable: LiveKitMediaSessionManager.instance.statusNotifier,
      builder: (context, mediaStatus, _) {
        final hasHost = widget.liveState?.hasHost == true;

        // 2.a Reconnecting Grace Period (Host network drop)
        if (mediaStatus == LiveKitMediaStatus.reconnectingGracePeriod) {
          return Container(
            color: const Color(0xFF0F172A),
            alignment: Alignment.center,
            child: ValueListenableBuilder<int>(
              valueListenable: LiveKitMediaSessionManager.instance.graceSecondsNotifier,
              builder: (context, graceSecs, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.amberAccent.withOpacity(0.5)),
                      ),
                      child: const Icon(Icons.sync, color: Colors.amberAccent, size: 36),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Host Reconnecting...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade900.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Preserving LiveKit Media • ${graceSecs}s grace period',
                        style: const TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        }

        // 2.b If host is active and LiveKit media connected
        if (hasHost && mediaStatus == LiveKitMediaStatus.connected) {
          return ValueListenableBuilder<lk.VideoTrack?>(
            valueListenable: LiveKitMediaSessionManager.instance.remoteVideoTrackNotifier,
            builder: (context, remoteTrack, _) {
              if (remoteTrack != null) {
                return SizedBox.expand(
                  child: lk.VideoTrackRenderer(
                    remoteTrack,
                  ),
                );
              }
              return Container(
                color: const Color(0xFF0A0D18),
                alignment: Alignment.center,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _ambientController,
                        builder: (context, _) {
                          return Container(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment(
                                  0.2 * (_ambientController.value - 0.5),
                                  0.2 * (0.5 - _ambientController.value),
                                ),
                                radius: 1.2,
                                colors: const [
                                  Color(0xFF1F1235),
                                  Color(0xFF0F172A),
                                  Color(0xFF050711),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 46,
                      backgroundColor: const Color(0xFFFF3B30),
                      child: CircleAvatar(
                        radius: 43,
                        backgroundColor: const Color(0xFF161824),
                        backgroundImage: widget.liveState?.currentHostAvatar?.isNotEmpty == true
                            ? CachedNetworkImageProvider(widget.liveState!.currentHostAvatar!)
                            : null,
                        child: widget.liveState?.currentHostAvatar?.isNotEmpty != true
                            ? const Icon(Icons.person, size: 48, color: Colors.white70)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.liveState?.currentHostName ?? 'Live Host',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFF3B30).withOpacity(0.5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fiber_manual_record, color: Color(0xFFFF3B30), size: 10),
                          SizedBox(width: 6),
                          Text(
                            'HOST STREAMING NOW',
                            style: TextStyle(
                              color: Color(0xFFFF3B30),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    }

        // 3. Disconnected / 24/7 Waiting for host state (0 LiveKit media bandwidth)
        return AnimatedBuilder(
          animation: _ambientController,
          builder: (context, _) {
            final val = _ambientController.value;
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(const Color(0xFF0F172A), const Color(0xFF1E1B4B), val)!,
                    Color.lerp(const Color(0xFF0B0F19), const Color(0xFF111827), 1 - val)!,
                    const Color(0xFF030712),
                  ],
                ),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1DA1F2).withOpacity(0.12),
                      border: Border.all(
                        color: const Color(0xFF1DA1F2).withOpacity(0.4),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.wifi_tethering,
                      color: Color(0xFF1DA1F2),
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Reward Live 24/7',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Waiting for a host to join the stage...',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                    Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.35)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, color: Color(0xFF00E5FF), size: 14),
                        SizedBox(width: 6),
                        Text(
                          '🎁 Rewards are active • Tap to Earn',
                          style: TextStyle(
                            color: Color(0xFF00E5FF),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHostWaitingSurface() {
    return Container(
      color: const Color(0xFF0F172A),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFE53935).withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE53935).withOpacity(0.5)),
            ),
            child: const Icon(Icons.videocam, color: Color(0xFFE53935), size: 36),
          ),
          const SizedBox(height: 14),
          const Text(
            'Starting Live Stream...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Connecting camera to LiveKit Cloud WebRTC',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
