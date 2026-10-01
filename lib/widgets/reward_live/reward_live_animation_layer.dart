import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/reward_live_model.dart';
import '../../services/reward_live_service.dart';
import 'reward_live_stage_animations.dart';
import 'gift_3d_visual.dart';

class RewardLiveAnimationLayer extends StatefulWidget {
  final Function(RewardDefinition reward, Offset screenPos) onRewardTapped;
  final bool isClaimWindowActive;
  final RewardDefinition currentCycleReward;

  const RewardLiveAnimationLayer({
    super.key,
    required this.onRewardTapped,
    required this.isClaimWindowActive,
    required this.currentCycleReward,
  });

  @override
  State<RewardLiveAnimationLayer> createState() => _RewardLiveAnimationLayerState();
}

class _RewardLiveAnimationLayerState extends State<RewardLiveAnimationLayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _tickerController;
  final List<ActiveStageAnimation> _stageAnimations = [];
  final List<_FloatingToast> _floatingToasts = [];
  int _comboCount = 0;
  DateTime _lastClaimTime = DateTime.now();

  // Sequential Single-Gift State with Alive Locomotion Physics
  int _currentGiftIndex = 0;
  double _giftX = 0.5;
  double _giftY = 0.45;
  double _targetX = 0.5;
  double _targetY = 0.45;
  double _vx = 0.0020;
  double _vy = 0.0015;
  double _giftAgeSeconds = 0.0;
  double _timeSinceWaypoint = 0.0;
  bool _isTransitioning = false;
  final Random _random = Random();

  // Each gift roams for 7.0s, then disappears with a clean 2.2s gap before the next
  static const double _giftLifespanSeconds = 7.0;
  static const int _giftDistanceDelayMs = 2200;

  @override
  void initState() {
    super.initState();
    _resetGiftPosition();
    _tickerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_tickPhysics);
    _tickerController.repeat();
  }

  @override
  void didUpdateWidget(covariant RewardLiveAnimationLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isClaimWindowActive && widget.isClaimWindowActive) {
      _resetGiftPosition();
    }
  }

  void _resetGiftPosition() {
    _giftX = 0.15 + (_random.nextDouble() * 0.70);
    _giftY = 0.22 + (_random.nextDouble() * 0.45);
    _pickNewWaypoint();
    _vx = (_targetX > _giftX ? 1 : -1) * (0.0016 + _random.nextDouble() * 0.0014);
    _vy = (_targetY > _giftY ? 1 : -1) * (0.0014 + _random.nextDouble() * 0.0012);
    _giftAgeSeconds = 0.0;
    _timeSinceWaypoint = 0.0;
    _isTransitioning = false;
  }

  void _pickNewWaypoint() {
    _targetX = 0.15 + (_random.nextDouble() * 0.70);
    _targetY = 0.22 + (_random.nextDouble() * 0.45);
    _timeSinceWaypoint = 0.0;
  }

  void _tickPhysics() {
    if (!mounted) return;

    // 1. Clean old floating toasts
    final now = DateTime.now();
    _floatingToasts.removeWhere((t) => now.difference(t.timestamp).inMilliseconds > 1600);

    // 2. Clean finished stage animations
    _stageAnimations.removeWhere((anim) => now.difference(anim.startTime).inMilliseconds > 2600);

    // 3. Update physics if currently active and not in the distance delay
    if (widget.isClaimWindowActive && !_isTransitioning) {
      const dt = 1.0 / 60.0;
      _giftAgeSeconds += dt;
      _timeSinceWaypoint += dt;

      // Organic Steering toward living waypoint
      final dx = _targetX - _giftX;
      final dy = _targetY - _giftY;
      final dist = sqrt(dx * dx + dy * dy);

      if (dist < 0.06 || _timeSinceWaypoint > 2.8) {
        _pickNewWaypoint();
      }

      // Smooth acceleration & steering force
      final desiredVx = dist > 0.001 ? (dx / dist) * 0.0024 : 0.0;
      final desiredVy = dist > 0.001 ? (dy / dist) * 0.0020 : 0.0;

      // Gentle organic interpolation
      _vx += (desiredVx - _vx) * 0.035;
      _vy += (desiredVy - _vy) * 0.035;

      // Harmonic lifelike breathing/flutter wave
      final flutterX = sin(_giftAgeSeconds * 3.5) * 0.0005;
      final flutterY = cos(_giftAgeSeconds * 2.8) * 0.0006;

      _giftX += _vx + flutterX;
      _giftY += _vy + flutterY;

      // Keep comfortably inside visible screen bounds
      if (_giftX < 0.10) { _giftX = 0.10; _vx = _vx.abs(); }
      if (_giftX > 0.90) { _giftX = 0.90; _vx = -_vx.abs(); }
      if (_giftY > 0.18) { _giftY = 0.18; _vy = _vy.abs(); }
      if (_giftY > 0.72) { _giftY = 0.72; _vy = -_vy.abs(); }

      // Check if gift lifespan has expired without being caught
      if (_giftAgeSeconds >= _giftLifespanSeconds) {
        _nextGift();
        return;
      }
    }

    if (mounted) setState(() {});
  }

  void _nextGift() {
    if (_isTransitioning) return;
    _isTransitioning = true;
    _giftAgeSeconds = 0.0;
    if (mounted) setState(() {});

    // Clear distance gap where the screen has ZERO roaming gifts before next gift spawns
    Future.delayed(const Duration(milliseconds: _giftDistanceDelayMs), () {
      if (!mounted) return;
      final service = RewardLiveService.instance;
      final cycle = service.calculateCurrentCycle();
      final items = service.generateGiftRushPoolForCycle(cycle);

      if (items.isNotEmpty) {
        // Auto-replenish if all items were claimed so the full 2-minute window has gifts
        final anyAvailable = items.any((i) => i.isAvailable);
        if (!anyAvailable) {
          for (final itm in items) {
            itm.resetForNewCycle();
          }
        }

        int nextIdx = (_currentGiftIndex + 1) % items.length;
        int searchCount = 0;
        while (!items[nextIdx].isAvailable && searchCount < items.length) {
          nextIdx = (nextIdx + 1) % items.length;
          searchCount++;
        }
        _currentGiftIndex = nextIdx;
      }
      _resetGiftPosition();
      if (mounted) setState(() {});
    });
  }

  void _handleGiftClaimed(GiftRushPoolItem poolItem, Offset tapPos) {
    if (!poolItem.isAvailable || _isTransitioning) return;

    final now = DateTime.now();

    if (widget.isClaimWindowActive) {
      if (now.difference(_lastClaimTime).inMilliseconds < 2500) {
        _comboCount++;
      } else {
        _comboCount = 1;
      }
      _lastClaimTime = now;

      // 1. Decrement claim stock
      poolItem.claimOne();

      // 2. Gift totally disappears immediately from screen
      _isTransitioning = true;
      _giftAgeSeconds = 0.0;
      if (mounted) setState(() {});

      // 3. Stage visual burst animation at tap location
      final anim = ActiveStageAnimation(
        id: '${poolItem.reward.id}_${now.microsecondsSinceEpoch}',
        reward: poolItem.reward,
        startPosition: tapPos,
        startTime: now,
      );
      _stageAnimations.add(anim);

      // 4. Floating combo toast
      _floatingToasts.add(_FloatingToast(
        position: tapPos,
        text: _comboCount > 1
            ? '🔥 Combo x$_comboCount! +${poolItem.reward.pointValue * _comboCount} pts'
            : '+${poolItem.reward.pointValue} pts',
        timestamp: now,
        color: _getRarityColor(poolItem.reward.rarity),
      ));

      // 5. Forward claim event to service & parent (which triggers single-sound audio mutex lock)
      widget.onRewardTapped(poolItem.reward, tapPos);

      // 6. Schedule next gift with full empty distance delay
      _nextGift();
    }
  }

  Color _getRarityColor(String rarity) {
    switch (rarity.toLowerCase()) {
      case 'mythic':
        return const Color(0xFFFF1744);
      case 'legendary':
        return const Color(0xFFFFD700);
      case 'epic':
        return const Color(0xFFE040FB);
      case 'rare':
        return const Color(0xFF00E5FF);
      case 'uncommon':
        return const Color(0xFF00E676);
      default:
        return const Color(0xFFFFCA28);
    }
  }

  @override
  void dispose() {
    _tickerController.removeListener(_tickPhysics);
    _tickerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final width = screenSize.width;
    final height = screenSize.height;

    final service = RewardLiveService.instance;
    final cycle = service.calculateCurrentCycle();
    final poolItems = service.generateGiftRushPoolForCycle(cycle);

    // Strictly select only the SINGLE current active gift
    final activeItem = (poolItems.isNotEmpty && _currentGiftIndex < poolItems.length)
        ? poolItems[_currentGiftIndex]
        : (poolItems.isNotEmpty ? poolItems.first : null);

    // Entrance Spotlight Dynamics (Enter at center, expand huge to 1.75x, then smoothly glide into roam path)
    double entranceScale = 1.0;
    double renderX = _giftX;
    double renderY = _giftY;

    if (_giftAgeSeconds < 1.8) {
      final entryProgress = (_giftAgeSeconds / 1.8).clamp(0.0, 1.0);
      if (entryProgress < 0.38) {
        // Phase 1: Fast elastic entrance to center, expanding to 1.75x
        final t = (entryProgress / 0.38).clamp(0.0, 1.0);
        final curve = Curves.elasticOut.transform(t);
        entranceScale = 0.20 + (curve * 1.55); // 0.20 -> 1.75
        renderX = 0.50;
        renderY = 0.46;
      } else if (entryProgress < 0.68) {
        // Phase 2: Hero stance in the middle with subtle breathing pulse
        final t = ((entryProgress - 0.38) / 0.30).clamp(0.0, 1.0);
        final pulse = sin(t * pi) * 0.12;
        entranceScale = 1.65 + pulse;
        renderX = 0.50;
        renderY = 0.46;
      } else {
        // Phase 3: Smoothly shrink from 1.65 -> 1.0 and glide outwards into the screen flight path
        final t = ((entryProgress - 0.68) / 0.32).clamp(0.0, 1.0);
        final smoothT = Curves.easeInOutCubic.transform(t);
        entranceScale = 1.65 - (smoothT * 0.65); // 1.65 -> 1.0
        renderX = 0.50 + ((_giftX - 0.50) * smoothT);
        renderY = 0.46 + ((_giftY - 0.46) * smoothT);
      }
    }

    final posX = (renderX * width).clamp(70.0, width - 70.0);
    final posY = (renderY * height).clamp(110.0, height - 170.0);
    final double baseGiftSize = 135.0;
    final double effectiveVisualSize = baseGiftSize * entranceScale;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 1. STRICTLY SINGLE ACTIVE 3D ALIVE GIFT (Guaranteed 0 overlapping gifts, totally absent during transition/distance delay)
        if (widget.isClaimWindowActive &&
            !_isTransitioning &&
            activeItem != null &&
            activeItem.isAvailable)
          Positioned(
            left: posX - (effectiveVisualSize / 2),
            top: posY - (effectiveVisualSize / 2),
            width: effectiveVisualSize,
            height: effectiveVisualSize,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                _handleGiftClaimed(activeItem, details.globalPosition);
              },
              child: Gift3DVisual(
                reward: activeItem.reward,
                size: effectiveVisualSize,
                showGlow: _giftAgeSeconds < 1.4,
                isInteractive: true,
                velocityX: _vx,
                velocityY: _vy,
              ),
            ),
          ),

        // 2. Stage Animations Layer
        RewardLiveStageAnimationPlayer(
          activeAnimations: _stageAnimations,
          onAnimationsUpdated: () {},
        ),

        // 3. Floating Combo & Points Toasts
        ..._floatingToasts.map((toast) {
          final elapsed = DateTime.now().difference(toast.timestamp).inMilliseconds;
          final progress = (elapsed / 1600).clamp(0.0, 1.0);
          final y = toast.position.dy - (progress * 70);
          final opacity = (1.0 - progress).clamp(0.0, 1.0);

          return Positioned(
            left: toast.position.dx - 60,
            top: y,
            child: IgnorePointer(
              child: Opacity(
                opacity: opacity,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: toast.color, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: toast.color.withOpacity(0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Text(
                    toast.text,
                    style: TextStyle(
                      color: toast.color,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _FloatingToast {
  final Offset position;
  final String text;
  final DateTime timestamp;
  final Color color;

  _FloatingToast({
    required this.position,
    required this.text,
    required this.timestamp,
    required this.color,
  });
}
