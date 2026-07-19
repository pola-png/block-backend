import 'package:flutter/material.dart';

/// A premium, high-performance Shimmer loader widget that applies a sliding
/// gradient mask over its child widget tree.
class ShimmerLoading extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const ShimmerLoading({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            final gradient = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [
                      Color(0xFF242424),
                      Color(0xFF383838),
                      Color(0xFF242424),
                    ]
                  : const [
                      Color(0xFFF2F2F7),
                      Color(0xFFE5E5EA),
                      Color(0xFFF2F2F7),
                    ],
              stops: const [0.1, 0.5, 0.9],
              transform: _SlidingGradientTransform(
                slidePercent: _controller.value,
              ),
            );
            return gradient.createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;

  const _SlidingGradientTransform({
    required this.slidePercent,
  });

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final double translation = bounds.width * (slidePercent - 0.5) * 2;
    return Matrix4.translationValues(translation, 0.0, 0.0);
  }
}
