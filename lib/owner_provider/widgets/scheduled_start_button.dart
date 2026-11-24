import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// UI guidance; the database independently checks its own clock.
class ScheduledStartButton extends StatefulWidget {
  const ScheduledStartButton(
      {super.key,
      required this.start,
      required this.busy,
      required this.onStart,
      this.now});
  final DateTime? start;
  final bool busy;
  final VoidCallback onStart;
  final DateTime Function()? now;
  @override
  State<ScheduledStartButton> createState() => _ScheduledStartButtonState();
}

class _ScheduledStartButtonState extends State<ScheduledStartButton>
    with WidgetsBindingObserver {
  Timer? _timer;
  DateTime get _now => (widget.now ?? DateTime.now)().toUtc();
  bool get _due =>
      widget.start != null && !_now.isBefore(widget.start!.toUtc());
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _arm();
  }

  @override
  void didUpdateWidget(covariant ScheduledStartButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    if (widget.start == null || _due) return;
    final remaining = widget.start!.toUtc().difference(_now);
    _timer = Timer(
        remaining > const Duration(minutes: 1)
            ? const Duration(minutes: 1)
            : remaining + const Duration(milliseconds: 1), () {
      if (!mounted) return;
      setState(_arm);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(_arm);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final due = _due;
    final wall = widget.start?.toUtc().add(const Duration(hours: 8));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!due)
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                wall == null
                    ? 'Schedule unavailable. Refresh this booking before starting.'
                    : 'Available from ${DateFormat('d MMM yyyy · h:mm a').format(wall)} MYT.',
                style: Theme.of(context).textTheme.bodySmall)),
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FilledButton(
              onPressed: widget.busy || !due
                  ? null
                  : () {
                      if (!_due) {
                        setState(_arm);
                        return;
                      }
                      widget.onStart();
                    },
              child: const Text('Start cleaning'))),
    ]);
  }
}
