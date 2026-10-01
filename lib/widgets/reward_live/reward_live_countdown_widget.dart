import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../../models/reward_live_model.dart';
import '../../services/reward_live_service.dart';
import 'gift_3d_visual.dart';

class RewardLiveCountdownWidget extends StatefulWidget {
  final Function(bool isActive) onClaimWindowStateChanged;

  const RewardLiveCountdownWidget({
    super.key,
    required this.onClaimWindowStateChanged,
  });

  @override
  State<RewardLiveCountdownWidget> createState() => _RewardLiveCountdownWidgetState();
}

class _RewardLiveCountdownWidgetState extends State<RewardLiveCountdownWidget> {
  Timer? _ticker;
  int _secondsRemaining = 180;
  int _currentCycle = 0;
  bool _isClaimActive = false;
  RewardDefinition? _currentReward;

  @override
  void initState() {
    super.initState();
    _updateCountdown();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _updateCountdown());
  }

  void _updateCountdown() {
    if (!mounted) return;
    final service = RewardLiveService.instance;
    final state = service.liveStateNotifier.value;
    final remaining = service.calculateSecondsRemaining(state);
    final cycle = service.calculateCurrentCycle(state);

    // 3-Minute Cycle (180s total):
    // - First 2 Minutes (remaining > 60): Gifts are LIVE & claimable (120s duration)
    // - Last 1 Minute (remaining <= 60): Preparation phase (60s duration)
    final claimActive = remaining > 60;

    if (claimActive != _isClaimActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onClaimWindowStateChanged(claimActive);
        }
      });
    }

    setState(() {
      _secondsRemaining = remaining;
      _currentCycle = cycle;
      _isClaimActive = claimActive;
      _currentReward = service.getDeterministicRewardForCycle(cycle);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatTime(int totalSeconds) {
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final reward = _currentReward ?? RewardLiveService.defaultDefinitions.first;

    // First 2 mins (remaining: 180 -> 61): dropActive with dropRemaining (120 -> 1)
    // Last 1 min (remaining: 60 -> 1): prepActive with prepRemaining (60 -> 1)
    final isDropActive = _secondsRemaining > 60;
    final dropSecondsRemaining = isDropActive ? _secondsRemaining - 60 : 0;
    final prepSecondsRemaining = isDropActive ? 0 : _secondsRemaining;
    final isImminent15s = !isDropActive && prepSecondsRemaining <= 15 && prepSecondsRemaining > 0;

    final double rawProgress = isDropActive
        ? (1.0 - (dropSecondsRemaining / 120.0))
        : (1.0 - (prepSecondsRemaining / 60.0));
    final double progress = (rawProgress.isNaN || rawProgress.isInfinite)
        ? 0.0
        : rawProgress.clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xDD0E111E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDropActive
              ? const Color(0xFFFFD700)
              : (isImminent15s ? const Color(0xFFFF9100).withOpacity(0.5) : Colors.white.withOpacity(0.12)),
          width: isDropActive ? 2.0 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isDropActive
                ? const Color(0xFFFFD700).withOpacity(0.35)
                : (isImminent15s
                    ? const Color(0xFFFF9100).withOpacity(0.2)
                    : Colors.black.withOpacity(0.4)),
            blurRadius: isDropActive ? 20 : 10,
            spreadRadius: isDropActive ? 2 : 0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 15-Second Faint Transparent Overlay Banner
          if (isImminent15s) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withOpacity(0.06), // Faint transparent overlay
                border: Border.all(
                  color: Colors.white.withOpacity(0.15),
                  width: 0.8,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.timer_outlined, color: Colors.amberAccent, size: 13),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '⚡ Ad & 2-Min Drop in ${prepSecondsRemaining}s...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],

          Row(
            children: [
              // 3D Reward preview
              Gift3DVisual(
                reward: reward,
                size: 44,
                showGlow: isDropActive,
              ),
              const SizedBox(width: 10),
              // Cycle & Status label
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            isDropActive
                                ? '⚡ 2-MIN GIFT DROP LIVE!'
                                : (isImminent15s ? '⚡ DROP IN $prepSecondsRemaining SECONDS!' : 'PREPARING NEXT ROUND'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 0.4,
                              fontWeight: FontWeight.w900,
                              color: isDropActive
                                  ? const Color(0xFFFFD700)
                                  : (isImminent15s ? const Color(0xFFFF3B30) : Colors.cyanAccent),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '#$_currentCycle',
                            style: const TextStyle(fontSize: 8, color: Colors.white60, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${reward.name} (+${reward.pointValue} pts)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Timer Display
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isDropActive
                      ? const Color(0xFFFFD700)
                      : (isImminent15s ? const Color(0xFFFF3B30) : const Color(0xFF1E2438)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isDropActive ? Icons.touch_app : Icons.timer_outlined,
                      size: 14,
                      color: isDropActive ? Colors.black : Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isDropActive ? _formatTime(dropSecondsRemaining) : _formatTime(prepSecondsRemaining),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: isDropActive ? Colors.black : Colors.white,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Smooth Linear Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation<Color>(
                isDropActive
                    ? const Color(0xFFFFD700)
                    : (isImminent15s ? const Color(0xFFFF3B30) : const Color(0xFF00E5FF)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
