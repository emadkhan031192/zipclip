import 'package:flutter/material.dart';

/// Press feedback used across the app: scales to 0.96 over 80 ms while
/// pressed. Honors the system "reduce motion" setting (no scaling then).
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.enabled = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final bool enabled;
  final BorderRadius borderRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 80),
    lowerBound: 0.96,
    upperBound: 1.0,
    value: 1.0,
  );

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _down(TapDownDetails _) {
    if (!widget.enabled || _reduceMotion) return;
    _controller.animateTo(0.96);
  }

  void _up([TapUpDetails? _]) {
    if (!widget.enabled || _reduceMotion) return;
    _controller.animateTo(1.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tappable = widget.enabled && widget.onTap != null;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      enabled: widget.enabled,
      child: GestureDetector(
        onTapDown: _down,
        onTapUp: _up,
        onTapCancel: _up,
        onTap: tappable ? widget.onTap : null,
        onLongPress: widget.onLongPress,
        child: ScaleTransition(
          scale: _controller,
          child: Opacity(
            opacity: widget.enabled ? 1.0 : 0.55,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
