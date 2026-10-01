import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/reward_live_model.dart';
import 'gift_3d_visual.dart';

/// Controller item for an active on-screen gift animation
class ActiveStageAnimation {
  final String id;
  final RewardDefinition reward;
  final Offset startPosition;
  final DateTime startTime;

  ActiveStageAnimation({
    required this.id,
    required this.reward,
    required this.startPosition,
    required this.startTime,
  });
}

/// Plays rich multi-stage dynamic animations where the gift ITSELF is the animation
class RewardLiveStageAnimationPlayer extends StatefulWidget {
  final List<ActiveStageAnimation> activeAnimations;
  final VoidCallback onAnimationsUpdated;

  const RewardLiveStageAnimationPlayer({
    super.key,
    required this.activeAnimations,
    required this.onAnimationsUpdated,
  });

  @override
  State<RewardLiveStageAnimationPlayer> createState() => _RewardLiveStageAnimationPlayerState();
}

class _RewardLiveStageAnimationPlayerState extends State<RewardLiveStageAnimationPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.activeAnimations.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;
        final now = DateTime.now();

        // Prune finished animations (after 2.8 seconds)
        widget.activeAnimations.removeWhere(
          (anim) => now.difference(anim.startTime).inMilliseconds > 2800,
        );

        return IgnorePointer(
          child: Stack(
            children: widget.activeAnimations.map((anim) {
              final elapsedMs = now.difference(anim.startTime).inMilliseconds;
              final progress = (elapsedMs / 2800).clamp(0.0, 1.0);

              return _buildSpecificAnimation(
                anim.reward,
                progress,
                screenWidth,
                screenHeight,
                anim.startPosition,
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildSpecificAnimation(
    RewardDefinition reward,
    double progress,
    double width,
    double height,
    Offset tapPos,
  ) {
    switch (reward.animationType) {
      case 'puppy_run':
      case 'puppy_jump':
        return _buildPuppyRunAndJump(reward, progress, width, height);

      case 'sports_car':
        return _buildSportsCarDrift(reward, progress, width, height);

      case 'dragon_fly':
        return _buildDragonSpiralFly(reward, progress, width, height);

      case 'rocket_launch':
        return _buildRocketLaunch(reward, progress, width, height);

      case 'unicorn_rainbow':
        return _buildUnicornRainbow(reward, progress, width, height);

      case 'cupid_arrow':
        return _buildCupidArrow(reward, progress, width, height);

      case 'dancing_banana':
      case 'giant_chicken':
        return _buildFunnyWobbleRun(reward, progress, width, height);

      case 'galaxy_portal':
      case 'spectacular':
        return _buildGalaxyPortal(reward, progress, width, height);

      default:
        return _buildDefaultFloatBurst(reward, progress, width, height, tapPos);
    }
  }

  // 1. PUPPY RUN & JUMP: 3D Puppy Runs from left -> jumps toward center -> heart appears -> sparkle boom
  Widget _buildPuppyRunAndJump(RewardDefinition reward, double t, double w, double h) {
    double posX;
    double posY;
    double scale = 1.0;
    double opacity = 1.0;
    bool showHeart = t > 0.35;
    bool showSparkle = t > 0.65;

    if (t < 0.4) {
      // Stage 1: Running in from left with bounce
      final runT = t / 0.4;
      posX = -80 + (w * 0.45 + 80) * runT;
      posY = h * 0.55 + sin(runT * pi * 6) * 16;
      scale = 1.1 + sin(runT * pi * 4) * 0.15;
    } else if (t < 0.75) {
      // Stage 2: Leap up toward host / center
      final jumpT = (t - 0.4) / 0.35;
      posX = w * 0.45 + (w * 0.05) * jumpT;
      posY = h * 0.55 - sin(jumpT * pi) * 110;
      scale = 1.3 + sin(jumpT * pi) * 0.3;
    } else {
      // Stage 3: Sparkle boom & fade out
      final endT = (t - 0.75) / 0.25;
      posX = w * 0.5;
      posY = h * 0.45 - endT * 20;
      scale = 1.5 + endT * 0.5;
      opacity = (1.0 - endT).clamp(0.0, 1.0);
    }

    return Positioned(
      left: posX - 50,
      top: posY - 50,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showHeart)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('💖', style: TextStyle(fontSize: 24)),
                    if (showSparkle) const Text('✨💥', style: TextStyle(fontSize: 22)),
                  ],
                ),
              Gift3DVisual(reward: reward, size: 84),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber, width: 1.5),
                ),
                child: Text(
                  '+${reward.pointValue} PTS',
                  style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 2. SPORTS CAR DRIFT: 3D Sports Car Zooms from left to right with smoke puffs & boost sparkles
  Widget _buildSportsCarDrift(RewardDefinition reward, double t, double w, double h) {
    final posX = -120 + (w + 240) * (t * t * 0.5 + t * 0.5);
    final posY = h * 0.65 + sin(t * pi * 4) * 6;
    final opacity = t > 0.85 ? ((1.0 - t) / 0.15).clamp(0.0, 1.0) : 1.0;

    return Positioned(
      left: posX - 70,
      top: posY - 40,
      child: Opacity(
        opacity: opacity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Exhaust smoke & boost flames
            Transform.rotate(
              angle: -0.1,
              child: Text(
                t > 0.2 ? '💨💨🔥✨' : '💨',
                style: const TextStyle(fontSize: 24),
              ),
            ),
            const SizedBox(width: 4),
            Gift3DVisual(reward: reward, size: 88),
            const SizedBox(width: 6),
            if (t > 0.3)
              const Text('💥✨', style: TextStyle(fontSize: 26)),
          ],
        ),
      ),
    );
  }

  // 3. DRAGON FLY: 3D Dragon Swoops in an orbital curve around host with flame particles
  Widget _buildDragonSpiralFly(RewardDefinition reward, double t, double w, double h) {
    final angle = t * pi * 2.5;
    final radiusX = w * 0.38 * (1.0 - t * 0.2);
    final radiusY = h * 0.18 * (1.0 - t * 0.2);
    final centerX = w * 0.5;
    final centerY = h * 0.38;

    final posX = centerX + cos(angle) * radiusX;
    final posY = centerY + sin(angle) * radiusY;
    final opacity = t > 0.8 ? ((1.0 - t) / 0.2).clamp(0.0, 1.0) : 1.0;

    return Positioned(
      left: posX - 60,
      top: posY - 60,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: 1.2 + sin(t * pi * 3) * 0.2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('🔥🔥🔥', style: TextStyle(fontSize: 20)),
                ],
              ),
              Gift3DVisual(reward: reward, size: 96),
              const SizedBox(height: 2),
              const Text('⚡ ROAR! ⚡', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  // 4. ROCKET LAUNCH: 3D Rocket Launches vertically with flame plume and screen shake
  Widget _buildRocketLaunch(RewardDefinition reward, double t, double w, double h) {
    final posX = w * 0.5 + sin(t * pi * 8) * (1.0 - t) * 6; // Slight rocket shudder
    final posY = (h * 0.85) - pow(t, 2) * (h * 0.95);
    final opacity = t > 0.85 ? ((1.0 - t) / 0.15).clamp(0.0, 1.0) : 1.0;

    return Positioned(
      left: posX - 50,
      top: posY - 50,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: 1.0 + t * 0.4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Gift3DVisual(reward: reward, size: 88),
              const SizedBox(height: 2),
              const Text('🔥💨✨', style: TextStyle(fontSize: 24)),
              const Text('🌌 BLAST OFF 🌌', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  // 5. UNICORN RAINBOW: 3D Unicorn Gallops across screen leaving rainbow arc
  Widget _buildUnicornRainbow(RewardDefinition reward, double t, double w, double h) {
    final posX = -100 + (w + 200) * t;
    final posY = h * 0.48 + sin(t * pi * 6) * 22;
    final opacity = t > 0.85 ? ((1.0 - t) / 0.15).clamp(0.0, 1.0) : 1.0;

    return Positioned(
      left: posX - 60,
      top: posY - 40,
      child: Opacity(
        opacity: opacity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🌈✨💫', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 4),
            Gift3DVisual(reward: reward, size: 88),
          ],
        ),
      ),
    );
  }

  // 6. CUPID ARROW: Shoots arrow directly into host/heart
  Widget _buildCupidArrow(RewardDefinition reward, double t, double w, double h) {
    final arrowProgress = (t / 0.7).clamp(0.0, 1.0);
    final posX = (w * 0.15) + (w * 0.5 - w * 0.15) * arrowProgress;
    final posY = (h * 0.6) - (h * 0.25) * sin(arrowProgress * (pi / 2));
    final hasHit = t > 0.65;
    final opacity = t > 0.85 ? ((1.0 - t) / 0.15).clamp(0.0, 1.0) : 1.0;

    return Positioned(
      left: posX - 40,
      top: posY - 40,
      child: Opacity(
        opacity: opacity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasHit)
              const Text('💘💖💥', style: TextStyle(fontSize: 34))
            else
              const Text('🏹💖', style: TextStyle(fontSize: 30)),
            Gift3DVisual(reward: reward, size: 72),
          ],
        ),
      ),
    );
  }

  // 7. FUNNY WOBBLE RUN (Chicken / Banana / Popcorn)
  Widget _buildFunnyWobbleRun(RewardDefinition reward, double t, double w, double h) {
    final posX = -80 + (w + 160) * t;
    final posY = h * 0.58 + sin(t * pi * 8) * 14;
    final wobble = sin(t * pi * 12) * 0.25;
    final opacity = t > 0.85 ? ((1.0 - t) / 0.15).clamp(0.0, 1.0) : 1.0;

    return Positioned(
      left: posX - 45,
      top: posY - 45,
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: wobble,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Gift3DVisual(reward: reward, size: 76),
              const Text('🎉🎵💥', style: TextStyle(fontSize: 20)),
            ],
          ),
        ),
      ),
    );
  }

  // 8. GALAXY PORTAL / SPECTACULAR
  Widget _buildGalaxyPortal(RewardDefinition reward, double t, double w, double h) {
    final centerX = w * 0.5;
    final centerY = h * 0.42;
    final portalScale = t < 0.3 ? (t / 0.3) * 1.5 : (t < 0.7 ? 1.5 : (1.5 - (t - 0.7) * 3.0)).clamp(0.0, 1.6);
    final rotation = t * pi * 4;
    final opacity = t > 0.85 ? ((1.0 - t) / 0.15).clamp(0.0, 1.0) : 1.0;

    return Positioned(
      left: centerX - 80,
      top: centerY - 80,
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: rotation,
          child: Transform.scale(
            scale: portalScale,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.purpleAccent.withOpacity(0.8),
                    Colors.deepPurple.withOpacity(0.5),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Gift3DVisual(reward: reward, size: 84),
                    const SizedBox(height: 4),
                    const Text('✨ XAPZAP GALAXY ✨', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 9. DEFAULT 3D BURST
  Widget _buildDefaultFloatBurst(
    RewardDefinition reward,
    double t,
    double w,
    double h,
    Offset tapPos,
  ) {
    final posX = tapPos.dx > 0 ? tapPos.dx : w * 0.5;
    final posY = (tapPos.dy > 0 ? tapPos.dy : h * 0.5) - t * 80;
    final scale = 1.0 + sin(t * pi) * 0.6;
    final opacity = (1.0 - t).clamp(0.0, 1.0);

    return Positioned(
      left: posX - 45,
      top: posY - 45,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Gift3DVisual(reward: reward, size: 76),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber, width: 1.5),
                ),
                child: Text(
                  '+${reward.pointValue} PTS',
                  style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
