import '../../presentation/workspace_text.dart';
import 'cursor_feed.dart';

enum NotificationFilter { all, unread, action }

class BookingNotification {
  const BookingNotification(
      {required this.id,
      required this.bookingId,
      required this.status,
      required this.timestamp,
      required this.unit,
      required this.building,
      required this.service,
      required this.read,
      required this.actionable});
  final String id, bookingId, status, unit, building, service;
  final DateTime timestamp;
  final bool read, actionable;
  static DateTime time(String raw) {
    if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(raw))
      throw const FormatException('Offset required');
    return DateTime.parse(raw).toUtc();
  }

  factory BookingNotification.parse(Map<String, dynamic> row) {
    if (!const {
          'Pending',
          'Accepted',
          'Declined',
          'Cancelled',
          'In Progress',
          'Completed'
        }.contains(row['event_status']) ||
        row['is_read'] is! bool ||
        row['actionable'] is! bool)
      throw const FormatException('Invalid notification');
    return BookingNotification(
        id: row['id'] as String,
        bookingId: row['booking_id'] as String,
        status: row['event_status'] as String,
        timestamp: time(row['happened_at'] as String),
        unit: workspaceText(row['unit_name'] as String),
        building: workspaceText(row['building_name'] as String),
        service: row['service_name'] as String,
        read: row['is_read'] as bool,
        actionable: row['actionable'] as bool);
  }
}

class NotificationSnapshot {
  const NotificationSnapshot(
      {required this.asOf,
      required this.filter,
      required this.total,
      required this.unread,
      required this.actions,
      required this.items,
      this.next});
  final String asOf;
  final NotificationFilter filter;
  final int total, unread, actions;
  final List<BookingNotification> items;
  final PageCursor? next;
  factory NotificationSnapshot.parse(
      Map<String, dynamic> row, String actor, NotificationFilter filter) {
    if (row['recipient_id'] != actor || row['filter'] != filter.name)
      throw const FormatException('Wrong notification identity');
    final asOf = row['as_of'] as String;
    BookingNotification.time(asOf);
    final total = row['total_count'] as int,
        unread = row['unread_count'] as int,
        actions = row['action_count'] as int;
    final items = List<Map<String, dynamic>>.from(row['items'] as List)
        .map(BookingNotification.parse)
        .toList();
    if (total < 0 ||
        unread < 0 ||
        actions < 0 ||
        unread > total ||
        actions > total ||
        items.length > 20 ||
        items.map((n) => n.id).toSet().length != items.length ||
        items.any((n) =>
            filter == NotificationFilter.unread && n.read ||
            filter == NotificationFilter.action && !n.actionable)) {
      throw const FormatException('Inconsistent notification page');
    }
    final cursor = row['next_cursor'] as Map?;
    return NotificationSnapshot(
        asOf: asOf,
        filter: filter,
        total: total,
        unread: unread,
        actions: actions,
        items: List.unmodifiable(items),
        next: cursor == null
            ? null
            : PageCursor(
                cursor['timestamp'] as String, cursor['id'] as String));
  }
  NotificationSnapshot append(NotificationSnapshot page) {
    if (page.filter != filter ||
        page.asOf != asOf ||
        page.items.any((n) => items.any((old) => old.id == n.id)) ||
        (page.next != null &&
            page.next!.id == next?.id &&
            page.next!.timestamp == next?.timestamp)) {
      throw const FormatException('Notification page changed; refresh');
    }
    return NotificationSnapshot(
        asOf: asOf,
        filter: filter,
        total: page.total,
        unread: page.unread,
        actions: page.actions,
        items: List.unmodifiable([...items, ...page.items]),
        next: page.next);
  }
}
