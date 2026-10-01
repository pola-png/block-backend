import 'package:flutter/material.dart';
import '../../models/reward_live_model.dart';
import 'gift_3d_visual.dart';

class RewardLiveClaimOverlay extends StatefulWidget {
  final RewardClaimResult result;
  final VoidCallback onDismiss;

  const RewardLiveClaimOverlay({
    super.key,
    required this.result,
    required this.onDismiss,
  });

  @override
  State<RewardLiveClaimOverlay> createState() => _RewardLiveClaimOverlayState();
}

class _RewardLiveClaimOverlayState extends State<RewardLiveClaimOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    _animController.forward();

    // Auto dismiss after 3.5 seconds
    Future.delayed(const Duration(milliseconds: 3500), () {
      if (mounted) {
        _animController.reverse().then((_) {
          if (mounted) widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final success = widget.result.success;

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _animController.reverse().then((_) {
            if (mounted) widget.onDismiss();
          });
        },
        child: Container(
          color: Colors.black.withOpacity(0.4),
          alignment: Alignment.center,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 36),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF161928),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: success ? const Color(0xFFFFD700) : Colors.redAccent,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (success ? const Color(0xFFFFD700) : Colors.redAccent).withOpacity(0.35),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 3D Gift Visual Display (No Round Circle!)
                    if (success && widget.result.rewardId != null)
                      Gift3DVisual(
                        reward: RewardDefinition(
                          id: widget.result.rewardId!,
                          name: widget.result.rewardName ?? 'Live Gift',
                          icon: widget.result.rewardIcon ?? '🎁',
                          category: 'cute',
                          animationType: 'float_burst',
                          pointValue: widget.result.points,
                          rarity: widget.result.rarity ?? 'legendary',
                          defaultStock: 100,
                          weight: 100,
                        ),
                        size: 96,
                        showGlow: true,
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: const LinearGradient(
                            colors: [Colors.redAccent, Colors.red],
                          ),
                        ),
                        child: const Icon(
                          Icons.info_outline,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      success ? 'REWARD CLAIMED!' : 'CLAIM NOTICE',
                      style: TextStyle(
                        color: success ? const Color(0xFFFFD700) : Colors.redAccent,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (success) ...[
                      Text(
                        '+${widget.result.points} Points Awarded',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.result.rewardName ?? "Live Reward"} • Cycle #${widget.result.cycleNumber ?? ""}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      if (widget.result.newBalanceUsd != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'New Balance: \$${widget.result.newBalanceUsd!.toStringAsFixed(3)}',
                            style: const TextStyle(
                              color: Color(0xFF00E676),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ] else ...[
                      Text(
                        widget.result.message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    TextButton(
                      onPressed: () {
                        _animController.reverse().then((_) {
                          if (mounted) widget.onDismiss();
                        });
                      },
                      child: const Text(
                        'Tap anywhere to continue',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
