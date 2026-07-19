import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_mode_service.dart';

class TvFocusableAction extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onTvPressed;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry padding;

  const TvFocusableAction({
    super.key,
    required this.child,
    this.onPressed,
    this.onTvPressed,
    this.onLongPress,
    this.borderRadius,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<TvFocusableAction> createState() => _TvFocusableActionState();
}

class _TvFocusableActionState extends State<TvFocusableAction> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(16);
    final child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPressed,
      onLongPress: widget.onLongPress,
      child: Padding(
        padding: widget.padding,
        child: widget.child,
      ),
    );

    if (!DeviceModeService.isTv) {
      return child;
    }

    final theme = Theme.of(context);
    return FocusableActionDetector(
      autofocus: false,
      onShowFocusHighlight: (value) {
        if (_focused == value) return;
        setState(() => _focused = value);
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            (widget.onTvPressed ?? widget.onPressed)?.call();
            return null;
          },
        ),
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: _focused ? theme.colorScheme.primary : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: _focused
              ? <BoxShadow>[
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.18),
                    blurRadius: 14,
                    spreadRadius: 1.5,
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: child,
        ),
      ),
    );
  }
}
