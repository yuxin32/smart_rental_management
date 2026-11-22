import '../../presentation/workspace_text.dart';
import '../../models/message.dart';
import 'cursor_feed.dart';
import 'notification_snapshot.dart';

class BookingConversation {
  const BookingConversation(
      {required this.bookingId,
      required this.counterpart,
      required this.property,
      required this.service,
      required this.status,
      required this.preview,
      required this.timestamp,
      this.unread = 0});
  final String bookingId, counterpart, property, service, status, preview;
  final DateTime timestamp;
  final int unread;
  factory BookingConversation.parse(Map<String, dynamic> row) {
    if (!const {
          'Pending',
          'Accepted',
          'In Progress',
          'Completed',
          'Cancelled',
          'Declined'
        }.contains(row['status']) ||
        (row['counterpart_name'] as String).trim().isEmpty ||
        (row['last_message'] as String).runes.length > 160 ||
        row['unread_count'] is! int ||
        row['unread_count'] < 0) {
      throw const FormatException('Invalid conversation');
    }
    return BookingConversation(
        bookingId: row['booking_id'] as String,
        counterpart: row['counterpart_name'] as String,
        property:
            '${workspaceText(row['unit_name'] as String)}, ${workspaceText(row['building_name'] as String)}',
        service: row['service_name'] as String,
        status: row['status'] as String,
        preview: workspaceText(row['last_message'] as String),
        timestamp: BookingNotification.time(row['last_at'] as String),
        unread: row['unread_count'] as int);
  }
  // Presentation adapter only. Authentication never uses these labels.
  Conversation present(String actor) => Conversation(
      id: bookingId,
      participantA: actor,
      participantB: counterpart,
      bookingId: bookingId,
      property:
          '$property · $service${status == 'Accepted' || status == 'In Progress' ? '' : ' · Read-only'}',
      lastMessage: preview,
      lastTimestamp: timestamp,
      unreadCount: unread);
}

class ConversationPage {
  const ConversationPage(this.asOf, this.page, {this.unreadTotal = 0});
  final String asOf;
  final CursorPage<BookingConversation> page;
  final int unreadTotal;
  factory ConversationPage.parse(dynamic response, String actor, String search,
      {bool unreadOnly = false}) {
    final row = Map<String, dynamic>.from(response as Map);
    if (row['recipient_id'] != actor ||
        row['search'] != search ||
        row['has_more'] is! bool ||
        row['unread_only'] != unreadOnly ||
        row['unread_total'] is! int ||
        row['unread_total'] < 0) {
      throw const FormatException('Wrong conversation identity or query');
    }
    final asOf = row['as_of'] as String;
    final boundary = BookingNotification.time(asOf);
    final page = CursorPage.decode(row, BookingConversation.parse);
    final items = page.items;
    if (items.length > 20 ||
        items.map((e) => e.bookingId).toSet().length != items.length ||
        items.any((e) =>
            e.timestamp.isAfter(boundary) || (unreadOnly && e.unread == 0)) ||
        items.fold<int>(0, (n, e) => n + e.unread) > row['unread_total'] ||
        (row['has_more'] == false && row['next_cursor'] != null)) {
      throw const FormatException('Invalid conversation page');
    }
    for (var i = 1; i < items.length; i++) {
      final a = items[i - 1], b = items[i];
      if (a.timestamp.isBefore(b.timestamp) ||
          (a.timestamp == b.timestamp &&
              a.bookingId.compareTo(b.bookingId) <= 0)) {
        throw const FormatException('Unordered conversation page');
      }
    }
    if (page.next != null &&
        (items.isEmpty ||
            page.next!.id != items.last.bookingId ||
            BookingNotification.time(page.next!.timestamp) !=
                items.last.timestamp)) {
      throw const FormatException('Invalid conversation boundary');
    }
    return ConversationPage(asOf, page,
        unreadTotal: row['unread_total'] as int);
  }
}
