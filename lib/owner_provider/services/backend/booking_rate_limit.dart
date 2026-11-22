import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum BookingLimitedAction { message, evidence }

/// Only known, definite database rejections enter the cooldown UI. A generic
/// network error/HTTP 429 must not be misreported as proof a write was rejected.
class ServerActionLimit implements Exception {
  const ServerActionLimit(this.action, this.retryAfterSeconds)
      : assert(retryAfterSeconds >= 1 && retryAfterSeconds <= 86400);
  final BookingLimitedAction action;
  final int retryAfterSeconds;

  static ServerActionLimit? from(Object error, BookingLimitedAction action) {
    if (error is! PostgrestException ||
        error.code != 'PT429' ||
        error.message !=
            (action == BookingLimitedAction.message
                ? 'CHAT_RATE_LIMITED'
                : 'EVIDENCE_RATE_LIMITED')) return null;
    final detail = error.details;
    final match = detail is String
        ? RegExp(r'^retry_after_seconds=([0-9]{1,5})$').firstMatch(detail)
        : null;
    final seconds = match == null ? null : int.tryParse(match.group(1)!);
    return ServerActionLimit(action,
        seconds == null || seconds < 1 || seconds > 86400 ? 60 : seconds,);
  }

  String get waitLabel => retryAfterSeconds >= 3600
      ? '${(retryAfterSeconds / 3600).ceil()} ${(retryAfterSeconds / 3600).ceil() == 1 ? 'hour' : 'hours'}'
      : retryAfterSeconds < 60
          ? '$retryAfterSeconds ${retryAfterSeconds == 1 ? 'second' : 'seconds'}'
          : '${(retryAfterSeconds / 60).ceil()} ${(retryAfterSeconds / 60).ceil() == 1 ? 'minute' : 'minutes'}';

  @override
  String toString() => 'The server temporarily limited this action.';
}

Future<T> withServerRateLimit<T>(
    BookingLimitedAction action, Future<T> Function() operation,) async {
  try {
    return await operation();
  } catch (error) {
    final limit = ServerActionLimit.from(error, action);
    if (limit != null) throw limit;
    rethrow;
  }
}

/// Convenience only: the server remains authoritative after navigation,
/// restarts, multiple devices or a modified client. Never auto-retries a write.
class ActionRatePause extends ChangeNotifier {
  Timer? _timer;
  ServerActionLimit? _limit;
  ServerActionLimit? get limit => _limit;
  bool get active => _limit != null;

  void start(ServerActionLimit limit) {
    _timer?.cancel();
    _limit = limit;
    _timer = Timer(Duration(seconds: limit.retryAfterSeconds), () {
      _limit = null;
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
