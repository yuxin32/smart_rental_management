// lib/widgets/animated_counter.dart
// Tweens from 0 to a target value over [duration] when mounted.
// Used in hero numbers like "RM 540" / "12" / "75%".

import 'package:flutter/material.dart';

class AnimatedCounter extends StatefulWidget {
  const AnimatedCounter({
    super.key,
    required this.value,
    this.duration = const Duration(milliseconds: 900),
    this.prefix = '',
    this.suffix = '',
    this.decimals = 0,
    this.style,
  });

  final double value;
  final Duration duration;
  final String prefix;
  final String suffix;
  final int decimals;
  final TextStyle? style;

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctl;
  late Animation<double> _anim;
  double _displayed = 0;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(vsync: this, duration: widget.duration);
    _anim = Tween<double>(begin: 0, end: widget.value).animate(
      CurvedAnimation(parent: _ctl, curve: Curves.easeOutCubic),
    )..addListener(() => setState(() => _displayed = _anim.value));
    _ctl.forward();
  }

  @override
  void didUpdateWidget(AnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _anim = Tween<double>(begin: _displayed, end: widget.value).animate(
        CurvedAnimation(parent: _ctl, curve: Curves.easeOutCubic),
      );
      _ctl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formatted = _displayed.toStringAsFixed(widget.decimals);
    return Text(
      '${widget.prefix}$formatted${widget.suffix}',
      style: widget.style,
    );
  }
}
