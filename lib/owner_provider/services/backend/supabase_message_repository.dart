import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'cursor_feed.dart';
import 'paged_realtime.dart';
import 'booking_rate_limit.dart';
import 'conversation_page.dart';

class BookingMessage {
  const BookingMessage({
    required this.id,
    required this.bookingId,
    required this.senderUserId,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String bookingId;
  final String senderUserId;
  final String body;
  final DateTime createdAt;

  factory BookingMessage.fromMap(Map<String, dynamic> row) => BookingMessage(
        id: row['message_id'] as String,
        bookingId: row['booking_id'] as String,
        senderUserId: row['sender_user_id'] as String,
        body: row['body'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}

abstract final class ClientMessageToken {
  static String newV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

/// Reads are participant-scoped by RLS. Sends go only through the database
/// function; the client never inserts into booking_message directly.
class SupabaseMessageRepository {
  SupabaseMessageRepository(this.client);
  final SupabaseClient client;
  // Invalidates own-account badge readers after confirmed sends/receipts only.
  final changes = ValueNotifier<int>(0);

  String get currentUserId =>
      client.auth.currentUser?.id ??
      (throw StateError('Sign in before opening booking messages.'));

  Future<ConversationPage> conversations(String search,
      {PageCursor? before, String? asOf, bool unreadOnly = false}) async {
    final actor = currentUserId;
    final result = await client.rpc(
        unreadOnly ? 'page_my_unread_conversations' : 'page_my_conversations',
        params: {
          'p_limit': 20,
          'p_search': search,
          'p_before_at': before?.timestamp,
          'p_before_id': before?.id,
          'p_as_of': asOf
        });
    if (client.auth.currentUser?.id != actor)
      throw StateError('Session changed');
    return ConversationPage.parse(result, actor, search,
        unreadOnly: unreadOnly);
  }

  Future<int> unread() async {
    final actor = currentUserId;
    final row = await client.rpc('my_message_unread');
    if (client.auth.currentUser?.id != actor)
      throw StateError('Session changed');
    if (row['recipient_id'] != actor ||
        row['messages'] is! int ||
        row['threads'] is! int ||
        row['messages'] < 0 ||
        row['threads'] < 0 ||
        row['threads'] > row['messages']) {
      throw const FormatException('Invalid unread identity/count');
    }
    return row['messages'] as int;
  }

  Future<void> markRead(String bookingId, List<String> ids) async {
    final actor = currentUserId;
    if (ids.isEmpty || ids.length > 50 || ids.toSet().length != ids.length) {
      throw ArgumentError('Select up to 50 distinct received messages');
    }
    final result = await client.rpc('read_booking_messages',
        params: {'p_booking_id': bookingId, 'p_ids': ids});
    if (client.auth.currentUser?.id != actor)
      throw StateError('Session changed');
    if (result['recipient_id'] != actor ||
        result['booking_id'] != bookingId ||
        result['acknowledged'] != ids.length) {
      throw const FormatException('Read acknowledgement mismatch');
    }
    changes.value++;
  }

  Future<CursorPage<BookingMessage>> page(
    String bookingId,
    PageCursor? before,
  ) async =>
      CursorPage.decode(
        await client.rpc(
          'page_booking_messages',
          params: {
            'p_booking_id': bookingId,
            'p_limit': 20,
            'p_before_at': before?.timestamp,
            'p_before_id': before?.id,
          },
        ),
        BookingMessage.fromMap,
      );

  CursorFeed<BookingMessage> openFeed(String bookingId, {bool active = true}) {
    final ownerId = currentUserId;
    return CursorFeed(
      active: active,
      ownerUserId: ownerId,
      currentUserId: () => client.auth.currentUser?.id,
      sessionChanges:
          client.auth.onAuthStateChange.map((state) => state.session?.user.id),
      loadPage: (cursor) => page(bookingId, cursor),
      idOf: (row) => row.id,
      compare: (a, b) {
        final time = b.createdAt.compareTo(a.createdAt);
        return time != 0 ? time : b.id.compareTo(a.id);
      },
      readOne: (id) async {
        final row = await client
            .from('booking_message')
            .select('message_id,booking_id,sender_user_id,body,created_at')
            .eq('booking_id', bookingId)
            .eq('message_id', id)
            .maybeSingle();
        return row == null ? null : BookingMessage.fromMap(row);
      },
      watchChanges: () => pagedRowChanges(
        client,
        table: 'booking_message',
        idColumn: 'message_id',
        filterColumn: 'booking_id',
        filterValue: bookingId,
      ),
    );
  }

  Future<void> send({
    required String bookingId,
    required String clientMessageId,
    required String body,
  }) async {
    final actor = client.auth.currentUser?.id;
    final trimmed = body.trim();
    if (trimmed.isEmpty || trimmed.length > 2000) {
      throw ArgumentError('Enter a message of up to 2,000 characters.');
    }
    await withServerRateLimit(
      BookingLimitedAction.message,
      () => client.rpc(
        'send_booking_message',
        params: {
          'p_booking_id': bookingId,
          'p_client_message_id': clientMessageId,
          'p_body': trimmed,
        },
      ),
    );
    if (actor != null && client.auth.currentUser?.id == actor) changes.value++;
  }

  /// Verifies a lost send response using the server's idempotency token.
  Future<bool> wasSent(String bookingId, String clientMessageId) async {
    final row = await client
        .from('booking_message')
        .select('message_id')
        .eq('booking_id', bookingId)
        .eq('sender_user_id', currentUserId)
        .eq('client_message_id', clientMessageId)
        .maybeSingle();
    return row != null;
  }
}
