import 'package:flutter/material.dart';

class VerificationBadge extends StatelessWidget {
  final double size;
  final bool isPremium;

  const VerificationBadge({
    super.key,
    this.size = 16,
    this.isPremium = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = isPremium
        ? [const Color(0xFFFFD700), const Color(0xFFFFA500), const Color(0xFFFF8C00)]
        : [const Color(0xFF00C9FF), const Color(0xFF92FE9D)]; // Electric cyan to green

    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      child: Icon(
        Icons.verified_rounded,
        size: size,
        color: Colors.white,
      ),
    );
  }
}
