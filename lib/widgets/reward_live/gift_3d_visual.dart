import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/reward_live_model.dart';

/// Renders a pure freeform 4D alive gift entity with ABSOLUTELY NO BACKGROUND
/// (No circle backgrounds, no card boxes, no halos, no gradient containers).
class Gift3DVisual extends StatefulWidget {
  final RewardDefinition reward;
  final double size;
  final bool showGlow;
  final bool isInteractive;
  final double velocityX;
  final double velocityY;

  const Gift3DVisual({
    super.key,
    required this.reward,
    this.size = 125.0,
    this.showGlow = false,
    this.isInteractive = false,
    this.velocityX = 0.0,
    this.velocityY = 0.0,
  });

  @override
  State<Gift3DVisual> createState() => _Gift3DVisualState();
}

class _Gift3DVisualState extends State<Gift3DVisual>
    with SingleTickerProviderStateMixin {
  late AnimationController _aliveController;

  @override
  void initState() {
    super.initState();
    _aliveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _aliveController.dispose();
    super.dispose();
  }

  Widget _buildEntityContent(double size, double yaw, double pitch) {
    final iconStr = widget.reward.icon.isNotEmpty ? widget.reward.icon : '🎁';
    final isImage = iconStr.startsWith('http') ||
        iconStr.startsWith('assets/') ||
        iconStr.endsWith('.png') ||
        iconStr.endsWith('.jpg') ||
        iconStr.endsWith('.webp');

    if (isImage) {
      if (iconStr.startsWith('http')) {
        return CachedNetworkImage(
          imageUrl: iconStr,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorWidget: (_, __, ___) => _buildTextIcon(size, '🎁', yaw, pitch),
        );
      } else {
        return Image.asset(
          iconStr,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildTextIcon(size, '🎁', yaw, pitch),
        );
      }
    }
    return _buildTextIcon(size, iconStr, yaw, pitch);
  }

  Widget _buildTextIcon(double size, String icon, double yaw, double pitch) {
    return Text(
      icon,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: size * 0.84,
        height: 1.0,
        leadingDistribution: TextLeadingDistribution.even,
        shadows: [
          Shadow(
            color: Colors.black.withOpacity(0.40),
            blurRadius: 16,
            offset: Offset(yaw * 20, 6 + pitch * 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final animType = widget.reward.animationType.toLowerCase();
    final isAnimal = animType.contains('puppy') || widget.reward.category == 'animals';
    final isFlying = animType.contains('dragon') || animType.contains('unicorn') || widget.reward.id.contains('falcon') || widget.reward.id.contains('phoenix');
    final isVehicle = widget.reward.category == 'vehicles' || widget.reward.id.contains('car') || widget.reward.id.contains('jet') || widget.reward.id.contains('rocket');

    return AnimatedBuilder(
      animation: _aliveController,
      builder: (context, _) {
        final progress = _aliveController.value;
        final orbit = progress * 2 * pi;
        final t = sin(progress * 2 * pi); // Harmonic breathing oscillation

        // 4D Matrix Rotations
        final yaw = sin(orbit) * 0.22;
        final pitch = cos(orbit * 0.8) * 0.15;
        final roll = sin(orbit * 1.2) * 0.08;

        // Locomotion morphing
        double scaleX = 1.0;
        double scaleY = 1.0;
        double floatY = 0.0;

        if (isAnimal) {
          scaleX = 1.0 + (t.abs() * 0.12);
          scaleY = 1.0 - (t.abs() * 0.08);
          floatY = -t.abs() * 14.0;
        } else if (isFlying) {
          scaleX = 1.0 + (cos(orbit) * 0.08);
          scaleY = 1.0 + (sin(orbit) * 0.08);
          floatY = sin(orbit) * 12.0;
        } else if (isVehicle) {
          scaleX = 1.0 + (sin(orbit * 3) * 0.03);
          scaleY = 1.0 + (cos(orbit * 3) * 0.03);
          floatY = sin(orbit) * 6.0;
        } else {
          scaleX = 0.96 + (t.abs() * 0.08);
          scaleY = 0.96 + (t.abs() * 0.08);
          floatY = sin(orbit) * 8.0;
        }

        final bool isMovingLeft = widget.velocityX < -0.0001;
        final double dirScaleX = isMovingLeft ? -scaleX : scaleX;

        // 4D Perspective Matrix
        final matrix4D = Matrix4.identity()
          ..setEntry(3, 2, 0.0018) // 3D/4D Depth perspective
          ..rotateY(yaw)
          ..rotateX(pitch)
          ..rotateZ(roll);

        return SizedBox(
          width: size,
          height: size,
          child: OverflowBox(
            minWidth: 0,
            maxWidth: size * 2.5,
            minHeight: 0,
            maxHeight: size * 2.5,
            alignment: Alignment.center,
            child: Transform.translate(
              offset: Offset(0, floatY),
              child: Transform(
                alignment: Alignment.center,
                transform: matrix4D,
                child: Transform.scale(
                  scaleX: dirScaleX,
                  scaleY: scaleY,
                  child: Center(
                    // PURE ENTITY - ZERO BACKGROUND OF ANY KIND, COMPLETELY UNCROPPED
                    child: _buildEntityContent(size, yaw, pitch),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
