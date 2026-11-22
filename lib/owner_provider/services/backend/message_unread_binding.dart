import 'dart:async';
import 'package:flutter/foundation.dart';

/// One foreground poller for all message-entry badges; no optimistic decrement.
class MessageUnreadBinding extends ChangeNotifier {
  MessageUnreadBinding(
      {required this.load,
      required this.userId,
      required this.currentUserId,
      required Stream<String?> sessions,
      this.changes}) {
    _sessions = sessions.listen((id) {
      if (id != userId) _end();
    }, onError: (Object _) {
      if (currentUserId() != userId) {
        _end();
      } else if (!_disposed && !_ended) {
        failed = true;
        notifyListeners();
      }
    });
    changes?.addListener(_changed);
  }
  final Future<int> Function() load;
  final String userId;
  final String? Function() currentUserId;
  final Listenable? changes;
  late final StreamSubscription<String?> _sessions;
  Timer? _timer;
  bool _active = false,
      _ended = false,
      _disposed = false,
      _loading = false,
      _again = false;
  int _epoch = 0;
  int? count;
  bool failed = false;
  bool get active => _active && !_ended && !_disposed;
  void _changed() {
    if (active) {
      _epoch++;
      refresh();
    }
  }

  void _end() {
    if (_disposed || _ended) return;
    _ended = true;
    _timer?.cancel();
    _epoch++;
    count = null;
    notifyListeners();
  }

  void setActive(bool value) {
    if (_disposed || _ended || value == _active) return;
    _active = value;
    _timer?.cancel();
    if (value) {
      refresh();
      _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
    }
  }

  Future<void> refresh() async {
    if (!active) return;
    if (currentUserId() != userId) {
      _end();
      return;
    }
    if (_loading) {
      _again = true;
      return;
    }
    _loading = true;
    final epoch = _epoch;
    try {
      final next = await load();
      if (!_disposed &&
          !_ended &&
          epoch == _epoch &&
          currentUserId() == userId) {
        if (next < 0) throw const FormatException('Invalid unread count');
        count = next;
        failed = false;
        notifyListeners();
      }
    } catch (_) {
      if (!_disposed && !_ended && epoch == _epoch) {
        failed = true;
        notifyListeners();
      }
    } finally {
      _loading = false;
      if (_again) {
        _again = false;
        if (active) unawaited(refresh());
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    changes?.removeListener(_changed);
    unawaited(_sessions.cancel());
    super.dispose();
  }
}

/// Acknowledges only IDs observed in the visible, resumed conversation.
class VisibleMessageReads {
  VisibleMessageReads(this.mark);
  final Future<void> Function(List<String>) mark;
  final _confirmed = <String>{}, _pending = <String>{};
  Timer? _timer;
  bool _active = false, _disposed = false, _busy = false;
  void setActive(bool value) {
    _active = value;
    if (!value) {
      _timer?.cancel();
      _timer = null;
      _pending.clear();
    }
  }

  void seen(String id) {
    if (_disposed || !_active || _confirmed.contains(id)) return;
    _pending.add(id);
    _schedule(const Duration(milliseconds: 200));
  }

  void _schedule(Duration wait) {
    if (_disposed || !_active || _busy || _pending.isEmpty || _timer != null)
      return;
    _timer = Timer(wait, () {
      _timer = null;
      _flush();
    });
  }

  Future<void> _flush() async {
    if (_disposed || !_active || _busy) return;
    final batch = _pending.take(50).toList();
    if (batch.isEmpty) return;
    _pending.removeAll(batch);
    _busy = true;
    var failed = false;
    try {
      await mark(batch);
      if (!_disposed) _confirmed.addAll(batch);
    } catch (_) {
      failed = true;
      if (!_disposed && _active) _pending.addAll(batch);
    } finally {
      _busy = false;
      _schedule(failed
          ? const Duration(seconds: 5)
          : const Duration(milliseconds: 200));
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _pending.clear();
    _confirmed.clear();
  }
}
