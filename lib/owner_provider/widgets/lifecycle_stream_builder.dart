import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Cancellation is awaited before a replacement listener is opened. Unlike
/// StreamBuilder, pausing discards stale snapshots rather than retaining an old
/// Accepted status that could enable a write before the fresh status arrives.
class LifecycleStreamBuilder<T> extends StatefulWidget {
  const LifecycleStreamBuilder({
    super.key,
    this.active = true,
    this.activity,
    required this.open,
    required this.builder,
  });
  final bool active;
  final ValueListenable<bool>? activity;
  final Stream<T> Function() open;
  final AsyncWidgetBuilder<T> builder;

  @override
  State<LifecycleStreamBuilder<T>> createState() =>
      _LifecycleStreamBuilderState<T>();
}

class _LifecycleStreamBuilderState<T> extends State<LifecycleStreamBuilder<T>> {
  StreamSubscription<T>? _subscription;
  Future<void> _transition = Future.value();
  AsyncSnapshot<T> _snapshot = AsyncSnapshot<T>.nothing();
  int _generation = 0;
  bool get _active => widget.activity?.value ?? widget.active;

  @override
  void initState() {
    super.initState();
    widget.activity?.addListener(_activityChanged);
    _replace();
  }

  @override
  void didUpdateWidget(LifecycleStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activity != widget.activity) {
      oldWidget.activity?.removeListener(_activityChanged);
      widget.activity?.addListener(_activityChanged);
    }
    if (oldWidget.active != widget.active ||
        oldWidget.open != widget.open ||
        oldWidget.activity != widget.activity) {
      _replace();
    }
  }

  void _activityChanged() {
    if (!mounted) return;
    setState(_replace);
  }

  void _replace() {
    final generation = ++_generation;
    _snapshot = AsyncSnapshot<T>.nothing().inState(
      _active ? ConnectionState.waiting : ConnectionState.none,
    );
    _transition = _transition.then((_) async {
      final previous = _subscription;
      _subscription = null;
      await previous?.cancel();
      if (!mounted || generation != _generation || !_active) return;
      _subscription = widget.open().listen(
        (value) {
          if (!mounted || generation != _generation || !_active) return;
          setState(
            () => _snapshot =
                AsyncSnapshot.withData(ConnectionState.active, value),
          );
        },
        onError: (Object error, StackTrace stack) {
          if (!mounted || generation != _generation || !_active) return;
          setState(
            () => _snapshot =
                AsyncSnapshot.withError(ConnectionState.active, error, stack),
          );
        },
        onDone: () {
          if (!mounted || generation != _generation || !_active) return;
          _subscription = null;
          setState(() => _snapshot = _snapshot.inState(ConnectionState.done));
        },
      );
    }).catchError((Object error, StackTrace stack) {
      if (!mounted || generation != _generation) return;
      setState(
        () => _snapshot =
            AsyncSnapshot.withError(ConnectionState.active, error, stack),
      );
    });
  }

  @override
  void dispose() {
    ++_generation;
    widget.activity?.removeListener(_activityChanged);
    // Joining the chain also covers a listener whose cancellation is in flight.
    unawaited(
      _transition.then((_) async {
        await _subscription?.cancel();
        _subscription = null;
      }).catchError((Object _) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _snapshot);
}
