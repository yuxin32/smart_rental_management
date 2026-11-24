import 'dart:convert';
import 'package:crypto/crypto.dart';

String reminderDigest(String value) =>
    sha256.convert(utf8.encode(value)).toString().substring(0, 32);

class ReminderBooking {
  const ReminderBooking(this.id, this.startUtc, this.endUtc, this.status);
  final String id, status;
  final DateTime startUtc, endUtc;

  factory ReminderBooking.parse(Map<String, dynamic> row, String actor) {
    if (row['provider_id'] != actor ||
        row['booking_id'] is! String ||
        row['current_status'] is! String) {
      throw const FormatException('Unexpected reminder identity.');
    }
    final start = DateTime.parse(row['requested_start_at'] as String);
    final end = DateTime.parse(row['requested_end_at'] as String);
    if (!start.isUtc || !end.isUtc || !end.isAfter(start)) {
      throw const FormatException('Invalid reminder interval.');
    }
    return ReminderBooking(row['booking_id'] as String, start, end,
        row['current_status'] as String);
  }
}

class BookingReminderPlan {
  const BookingReminderPlan(
      {required this.id,
      required this.fireUtc,
      required this.startUtc,
      required this.payload,
      required this.dayBefore});
  final int id;
  final DateTime fireUtc, startUtc;
  final String payload;
  final bool dayBefore;
  static const kind = 'booking-reminder-v1';

  static Map<String, dynamic>? readPayload(String? value) {
    if (value == null || value.length > 512) return null;
    try {
      final row = jsonDecode(value);
      if (row is! Map<String, dynamic> ||
          row['type'] != kind ||
          row['actor'] is! String ||
          row['booking'] is! String ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(row['actor'] as String) ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(row['booking'] as String) ||
          row['start'] is! String ||
          DateTime.tryParse(row['start'] as String)?.isUtc != true ||
          ![1, 24].contains(row['hours'])) return null;
      return row;
    } catch (_) {
      return null;
    }
  }

  static List<BookingReminderPlan> build(
      {required String actorStamp,
      required Iterable<ReminderBooking> bookings,
      required DateTime now,
      required bool dayBefore}) {
    final candidates = bookings
        .where((b) => b.status == 'Accepted' && b.startUtc.isAfter(now.toUtc()))
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final ids = <int>{};
    final keys = <String>{};
    final result = <BookingReminderPlan>[];
    for (final booking in candidates) {
      for (final hours in [1, if (dayBefore) 24]) {
        final fire = booking.startUtc.subtract(Duration(hours: hours));
        if (!fire.isAfter(now.toUtc())) continue;
        final key = '$actorStamp:${booking.id}:$hours';
        if (!keys.add(key)) continue;
        var id = int.parse(reminderDigest(key).substring(0, 8), radix: 16) &
            0x7fffffff;
        if (id == 0) id = 1;
        while (!ids.add(id)) {
          id = id == 0x7fffffff ? 1 : id + 1;
        }
        result.add(BookingReminderPlan(
            id: id,
            fireUtc: fire,
            startUtc: booking.startUtc,
            dayBefore: hours == 24,
            payload: jsonEncode({
              'type': kind,
              'actor': actorStamp,
              'booking': reminderDigest(booking.id),
              'start': booking.startUtc.toIso8601String(),
              'hours': hours,
            })));
      }
    }
    return result..sort((a, b) => a.fireUtc.compareTo(b.fireUtc));
  }
}

class PendingBookingReminder {
  const PendingBookingReminder(this.id, this.payload);
  final int id;
  final String? payload;
}

abstract class BookingReminderPlatform {
  bool get supported;
  Future<void> initialize(void Function(String?) onTap);
  Future<bool> allowed();
  Future<bool> requestPermission();
  Future<List<PendingBookingReminder>> pending();
  Future<void> schedule(BookingReminderPlan plan);
  Future<void> cancel(int id);
}
