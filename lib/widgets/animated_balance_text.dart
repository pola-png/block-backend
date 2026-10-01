import 'package:flutter/material.dart';
import '../services/micro_job_service.dart';

class AnimatedBalanceText extends StatefulWidget {
  final double balance;
  final int decimalDigits;
  final TextStyle? style;
  final String prefix;
  final Duration duration;
  final bool enablePulse;

  const AnimatedBalanceText({
    super.key,
    required this.balance,
    this.decimalDigits = 5,
    this.style,
    this.prefix = r'$',
    this.duration = const Duration(milliseconds: 800),
    this.enablePulse = true,
  });

  @override
  State<AnimatedBalanceText> createState() => _AnimatedBalanceTextState();
}

class _AnimatedBalanceTextState extends State<AnimatedBalanceText>
    with SingleTickerProviderStateMixin {
  late double _oldBalance;
  late double _targetBalance;
  late AnimationController _controller;
  late Animation<double> _numberAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _oldBalance = widget.balance;
    _targetBalance = widget.balance;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _numberAnimation = Tween<double>(
      begin: _oldBalance,
      end: _targetBalance,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.14)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.14, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 65,
      ),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(covariant AnimatedBalanceText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.balance != widget.balance) {
      _oldBalance = _numberAnimation.value;
      _targetBalance = widget.balance;
      _numberAnimation = Tween<double>(
        begin: _oldBalance,
        end: _targetBalance,
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ));
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final val = _numberAnimation.value;
        final formattedText = '${widget.prefix}${val.toStringAsFixed(widget.decimalDigits)}';
        final scale = widget.enablePulse && _controller.isAnimating
            ? _scaleAnimation.value
            : 1.0;

        return Transform.scale(
          scale: scale,
          alignment: Alignment.centerLeft,
          child: Text(
            formattedText,
            style: widget.style,
          ),
        );
      },
    );
  }
}

/// A reactive wrapper that listens to [MicroJobService.userBalanceNotifier]
/// and renders [AnimatedBalanceText] with smooth counting animations automatically.
class ReactiveAnimatedBalance extends StatelessWidget {
  final int decimalDigits;
  final TextStyle? style;
  final String prefix;
  final Duration duration;
  final bool enablePulse;

  const ReactiveAnimatedBalance({
    super.key,
    this.decimalDigits = 5,
    this.style,
    this.prefix = r'$',
    this.duration = const Duration(milliseconds: 800),
    this.enablePulse = true,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: MicroJobService.userBalanceNotifier,
      builder: (context, balance, _) {
        return AnimatedBalanceText(
          balance: balance,
          decimalDigits: decimalDigits,
          style: style,
          prefix: prefix,
          duration: duration,
          enablePulse: enablePulse,
        );
      },
    );
  }
}
