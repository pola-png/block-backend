import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../../services/reward_live_service.dart';

class RewardLiveMiddleNoticeOverlay extends StatefulWidget {
  const RewardLiveMiddleNoticeOverlay({super.key});

  @override
  State<RewardLiveMiddleNoticeOverlay> createState() => _RewardLiveMiddleNoticeOverlayState();
}

class _RewardLiveMiddleNoticeOverlayState extends State<RewardLiveMiddleNoticeOverlay>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  int _secondsRemaining = 180;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _updateState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateState());
  }

  void _updateState() {
    if (!mounted) return;
    final service = RewardLiveService.instance;
    final state = service.liveStateNotifier.value;
    final remaining = service.calculateSecondsRemaining(state);

    setState(() {
      _secondsRemaining = remaining;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _formatTime(int totalSecs) {
    final m = (totalSecs ~/ 60).toString().padLeft(2, '0');
    final s = (totalSecs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // 3-Minute total cycle:
    // - Drop Active (remaining > 60): 120s down to 1s
    // - Prep Phase (remaining <= 60): 60s down to 1s
    final isDropActive = _secondsRemaining > 60;
    final dropSecsRemaining = isDropActive ? _secondsRemaining - 60 : 0;
    final prepSecsRemaining = isDropActive ? 0 : _secondsRemaining;

    // Show initial drop banner for the first 8 seconds of the drop (120 -> 112)
    final showDropIntroBanner = isDropActive && dropSecsRemaining >= 112;
    final isImminent15s = !isDropActive && prepSecsRemaining <= 15 && prepSecsRemaining > 0;
    final isNormalPrep = !isDropActive && prepSecsRemaining > 15;

    // If during the main drop past 8s, we let the floating gifts take full spotlight
    if (isDropActive && !showDropIntroBanner) {
      return const SizedBox.shrink();
    }

    return Center(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: isImminent15s ? _pulseAnimation.value : 1.0,
              child: child,
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              // Faint, transparent glassmorphic overlay
              color: isImminent15s
                  ? const Color(0x33FF9100) // Faint amber tint for 15s warning
                  : (showDropIntroBanner
                      ? const Color(0x3300E676) // Faint emerald tint for live drop
                      : const Color(0x2A10172A)), // Ultra-faint translucent dark slate
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isImminent15s
                    ? const Color(0x88FFD700)
                    : (showDropIntroBanner ? const Color(0x8800E676) : Colors.white.withOpacity(0.18)),
                width: isImminent15s ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: isImminent15s
                      ? const Color(0x44FF9100)
                      : (showDropIntroBanner ? const Color(0x4400E676) : Colors.black.withOpacity(0.25)),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isImminent15s) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bolt, color: Colors.amberAccent, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '2-Min Gift Drop in ${prepSecsRemaining}s...',
                              style: const TextStyle(
                                color: Colors.amberAccent,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Get ready to tap & claim 3D gifts!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ] else if (showDropIntroBanner) ...[
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.stars_rounded, color: Color(0xFF00E676), size: 20),
                            SizedBox(width: 8),
                            Text(
                              '🎉 2-Min Drop is LIVE!',
                              style: TextStyle(
                                color: Color(0xFF00E676),
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tap the animated 3D gifts on screen to earn cash!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ] else if (isNormalPrep) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer_outlined, color: Colors.white70, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'Next Drop in ${_formatTime(prepSecsRemaining)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Get ready to tap gifts when the drop starts',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
