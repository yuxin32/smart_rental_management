import 'dart:math';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'cursor_feed.dart';
import 'paged_realtime.dart';
import 'session_snapshot_cache.dart';

class BookingCreationOutcome {
  const BookingCreationOutcome({
    required this.bookingId,
    required this.reused,
    required this.quotedAmount,
    required this.quoteBasis,
    required this.quoteCurrency,
  });

  final String bookingId;
  final bool reused;
  final num quotedAmount;
  final String quoteBasis;
  final String quoteCurrency;

  factory BookingCreationOutcome.fromResponse(Map<String, dynamic> value) {
    if (value['created'] != true) {
      throw BookingRequestRejected(value['reason'] as String? ?? 'unknown');
    }
    return BookingCreationOutcome(
      bookingId: value['booking_id'] as String,
      reused: value['reused'] == true,
      quotedAmount: value['quoted_amount'] as num,
      quoteBasis: value['quote_basis'] as String,
      quoteCurrency: value['quote_currency'] as String,
    );
  }
}

enum OwnerBookingGroup {
  pending,
  active,
  completed,
  upcoming,
  followUp;

  String get label => switch (this) {
        pending => 'Pending',
        active => 'Ongoing',
        completed => 'Completed',
        upcoming => 'Upcoming',
        followUp => 'Bookings to follow',
      };
  List<String> get statuses => switch (this) {
        pending => const ['Pending'],
        active => const ['Accepted', 'In Progress'],
        completed => const ['Completed'],
        upcoming => const ['Accepted', 'In Progress'],
        followUp => const ['Pending', 'Accepted', 'In Progress'],
      };
}

class BookingRequestRejected implements Exception {
  const BookingRequestRejected(this.reason);
  final String reason;

  @override
  String toString() => 'Booking request rejected: $reason';
}

/// Create this once per request form and reuse it for network retries.
abstract final class BookingRequestToken {
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

class AcceptanceOutcome {
  const AcceptanceOutcome({required this.accepted, this.reason});
  final bool accepted;
  final String? reason;
}

/// Server-side functions own every status transition. The client must never
/// perform read-check-write acceptance or treat Pending as slot-blocking.
class SupabaseBookingRepository {
  const SupabaseBookingRepository(this.client, {this.snapshots});
  final SupabaseClient client;
  final SessionSnapshotCache? snapshots;

  Future<dynamic> _writeRpc(String name,
          {required Map<String, dynamic> params}) =>
      snapshots == null
          ? client.rpc(name, params: params)
          : snapshots!
              .write(() async => await client.rpc(name, params: params));

  Future<CursorPage<Map<String, dynamic>>> _snapshotPage(
      String key,
      PageCursor? cursor,
      Future<CursorPage<Map<String, dynamic>>> Function() read) async {
    final lease = snapshots?.lease();
    try {
      final value = await read();
      if (lease != null && !snapshots!.valid(lease)) {
        throw StateError(
            'Data changed during refresh. Retry to verify latest bookings.');
      }
      if (cursor == null && lease != null) {
        // Deep copy rows: presentation/realtime must not mutate the stored head.
        final json = jsonEncode(value.items);
        final rows = List<Map<String, dynamic>>.from(jsonDecode(json) as List);
        snapshots!.put(
            key,
            CursorPage<Map<String, dynamic>>(
                items: List.unmodifiable(
                    rows.map((r) => Map<String, dynamic>.unmodifiable(r))),
                next: value.next),
            lease: lease,
            bytes: utf8.encode(json).length + 256);
      }
      return value;
    } catch (e) {
      if (rejectsSnapshot(e)) snapshots?.clear();
      rethrow;
    }
  }

  String get _userId =>
      client.auth.currentUser?.id ??
      (throw StateError('Sign in before accessing bookings.'));

  Future<CursorPage<Map<String, dynamic>>> page({PageCursor? before}) async =>
      CursorPage.decode(
        await client.rpc(
          'page_my_bookings',
          params: {
            'p_limit': 20,
            'p_before_at': before?.timestamp,
            'p_before_id': before?.id,
          },
        ),
        (row) => row,
      );

  Future<Map<String, dynamic>?> readCard(String id) async {
    final rows = List<Map<String, dynamic>>.from(
      await client.rpc(
        'booking_cards_by_ids',
        params: {
          'p_ids': [id],
        },
      ) as List,
    );
    return rows.isEmpty ? null : rows.single;
  }

  /// Apply status and ordering at the database, before taking a page. A status
  /// total must never navigate to a filter of only the dashboard's first page.
  Future<CursorPage<Map<String, dynamic>>> ownerPage(OwnerBookingGroup group,
      {PageCursor? before}) async {
    final actor = _userId;
    final ascending = group == OwnerBookingGroup.followUp ||
        group == OwnerBookingGroup.upcoming;
    final time = ascending ? 'requested_start_at' : 'created_at';
    var query = client
        .from('booking')
        .select('booking_id,$time')
        .eq('owner_id', actor)
        .inFilter('current_status', group.statuses);
    if (before != null) {
      if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(before.id) ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}T[0-9:.]+(?:Z|[+-]\d{2}:\d{2})$')
              .hasMatch(before.timestamp) ||
          DateTime.tryParse(before.timestamp) == null)
        throw ArgumentError('Invalid booking cursor');
      final op = ascending ? 'gt' : 'lt';
      query = query.or(
          '$time.$op.${before.timestamp},and($time.eq.${before.timestamp},booking_id.$op.${before.id})');
    }
    final candidates = List<Map<String, dynamic>>.from(await query
        .order(time, ascending: ascending)
        .order('booking_id', ascending: ascending)
        .limit(21));
    if (_userId != actor) throw StateError('Session changed');
    final page = candidates.take(20).toList();
    if (page.isEmpty) return const CursorPage(items: []);
    final ids = page.map((r) => r['booking_id'] as String).toSet();
    final cards = List<Map<String, dynamic>>.from(await client
        .rpc('booking_cards_by_ids', params: {'p_ids': ids.toList()}));
    if (_userId != actor) throw StateError('Session changed');
    if (cards
        .any((r) => r['owner_id'] != actor || !ids.contains(r['booking_id']))) {
      throw const FormatException('Wrong owner booking');
    }
    return CursorPage(
        items: cards
            .where((r) => group.statuses.contains(r['current_status']))
            .toList(),
        next: candidates.length > 20
            ? PageCursor(
                page.last[time] as String, page.last['booking_id'] as String)
            : null);
  }

  CursorFeed<Map<String, dynamic>> openOwnerFeed(OwnerBookingGroup group,
      {bool active = false}) {
    final actor = _userId;
    final key = 'owner-bookings:${group.name}';
    final ascending = group == OwnerBookingGroup.followUp ||
        group == OwnerBookingGroup.upcoming;
    final time = ascending ? 'requested_start_at' : 'created_at';
    return CursorFeed(
      active: active,
      ownerUserId: actor,
      currentUserId: () => client.auth.currentUser?.id,
      sessionChanges:
          client.auth.onAuthStateChange.map((s) => s.session?.user.id),
      preserveOnRefresh: snapshots != null,
      onSnapshotRejected: snapshots?.clear,
      initialPage:
          snapshots?.peek<CursorPage<Map<String, dynamic>>>(key)?.value,
      recheckUnloadedUpdates: true,
      loadPage: (cursor) =>
          _snapshotPage(key, cursor, () => ownerPage(group, before: cursor)),
      idOf: (r) => r['booking_id'] as String,
      compare: (a, b) =>
          (ascending ? -1 : 1) * compareRows(a, b, time, 'booking_id'),
      readOne: (id) async {
        final row = await readCard(id);
        if (_userId != actor) throw StateError('Session changed');
        return row != null &&
                row['owner_id'] == actor &&
                group.statuses.contains(row['current_status'])
            ? row
            : null;
      },
      watchChanges: () => pagedRowChanges(client,
          table: 'booking',
          idColumn: 'booking_id',
          filterColumn: 'owner_id',
          filterValue: actor),
    );
  }

  /// Calendar pages are selected by interval overlap, NOT by the dashboard's
  /// first page of recently-created requests. Existing RLS and safe card RPC
  /// suffice; no broader grants or schema change are needed.
  Future<CursorPage<Map<String, dynamic>>> schedulePage({
    required DateTime startUtc,
    required DateTime endUtc,
    PageCursor? before,
  }) async {
    final userId = _userId;
    if (!startUtc.isUtc ||
        !endUtc.isUtc ||
        !endUtc.isAfter(startUtc) ||
        endUtc.difference(startUtc) > const Duration(days: 7)) {
      throw ArgumentError(
          'Schedule requests require a UTC interval of at most seven days.');
    }
    if (before != null &&
        (!RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')
                .hasMatch(before.id) ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}T[0-9:.]+(?:Z|[+-]\d{2}:\d{2})$')
                .hasMatch(before.timestamp) ||
            DateTime.tryParse(before.timestamp) == null)) {
      throw ArgumentError('Invalid calendar cursor.');
    }
    var query = client
        .from('booking')
        .select('booking_id,created_at')
        .lt('requested_start_at', endUtc.toIso8601String())
        .gt('requested_end_at', startUtc.toIso8601String())
        .inFilter('current_status',
            ['Pending', 'Accepted', 'In Progress', 'Completed']);
    if (before != null) {
      query = query.or(
          'created_at.lt.${before.timestamp},and(created_at.eq.${before.timestamp},booking_id.lt.${before.id})');
    }
    final candidates = List<Map<String, dynamic>>.from(await query
        .order('created_at', ascending: false)
        .order('booking_id', ascending: false)
        .limit(21));
    if (_userId != userId) throw StateError('Session changed.');
    final visible = candidates.take(20).toList();
    if (visible.isEmpty) return const CursorPage(items: []);
    final ids = visible.map((row) => row['booking_id'] as String).toSet();
    final cards = List<Map<String, dynamic>>.from(await client
        .rpc('booking_cards_by_ids', params: {'p_ids': ids.toList()}));
    if (_userId != userId) throw StateError('Session changed.');
    if (cards.any((row) =>
        !ids.contains(row['booking_id']) ||
        (row['owner_id'] != userId && row['provider_id'] != userId))) {
      throw const FormatException('Unexpected calendar card identity.');
    }
    return CursorPage(
      items: cards.where((row) => _inSchedule(row, startUtc, endUtc)).toList(),
      next: candidates.length > 20
          ? PageCursor(visible.last['created_at'] as String,
              visible.last['booking_id'] as String)
          : null,
    );
  }

  static bool _inSchedule(
          Map<String, dynamic> row, DateTime start, DateTime end) =>
      const {'Pending', 'Accepted', 'In Progress', 'Completed'}
          .contains(row['current_status']) &&
      DateTime.parse(row['requested_start_at'] as String).isBefore(end) &&
      DateTime.parse(row['requested_end_at'] as String).isAfter(start);

  CursorFeed<Map<String, dynamic>> openScheduleFeed({
    required bool provider,
    required DateTime startUtc,
    required DateTime endUtc,
    bool active = false,
  }) {
    final userId = _userId;
    final key =
        'schedule:$provider:${startUtc.toIso8601String()}:${endUtc.toIso8601String()}';
    return CursorFeed(
      preserveOnRefresh: snapshots != null,
      onSnapshotRejected: snapshots?.clear,
      initialPage:
          snapshots?.peek<CursorPage<Map<String, dynamic>>>(key)?.value,
      recheckUnloadedUpdates: true,
      active: active,
      ownerUserId: userId,
      currentUserId: () => client.auth.currentUser?.id,
      sessionChanges:
          client.auth.onAuthStateChange.map((state) => state.session?.user.id),
      loadPage: (cursor) => _snapshotPage(
          key,
          cursor,
          () =>
              schedulePage(startUtc: startUtc, endUtc: endUtc, before: cursor)),
      idOf: (row) => row['booking_id'] as String,
      compare: (a, b) => compareRows(a, b, 'created_at', 'booking_id'),
      readOne: (id) async {
        final row = await readCard(id);
        if (client.auth.currentUser?.id != userId)
          throw StateError('Session changed.');
        return row != null && _inSchedule(row, startUtc, endUtc) ? row : null;
      },
      watchChanges: () => pagedRowChanges(client,
          table: 'booking',
          idColumn: 'booking_id',
          filterColumn: provider ? 'provider_id' : 'owner_id',
          filterValue: userId),
    );
  }

  CursorFeed<Map<String, dynamic>> openFeed({
    required bool provider,
    bool active = true,
    void Function()? onServerChange,
  }) {
    final ownerId = _userId;
    final key = 'bookings:$provider';
    return CursorFeed(
      preserveOnRefresh: snapshots != null,
      onSnapshotRejected: snapshots?.clear,
      initialPage:
          snapshots?.peek<CursorPage<Map<String, dynamic>>>(key)?.value,
      active: active,
      ownerUserId: ownerId,
      currentUserId: () => client.auth.currentUser?.id,
      sessionChanges:
          client.auth.onAuthStateChange.map((state) => state.session?.user.id),
      loadPage: (cursor) =>
          _snapshotPage(key, cursor, () => page(before: cursor)),
      idOf: (row) => row['booking_id'] as String,
      compare: (a, b) => compareRows(a, b, 'created_at', 'booking_id'),
      readOne: readCard,
      watchChanges: () => pagedRowChanges(
        client,
        table: 'booking',
        idColumn: 'booking_id',
        filterColumn: provider ? 'provider_id' : 'owner_id',
        filterValue: ownerId,
      ),
      onServerChange: onServerChange,
    );
  }

  static int compareRows(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
    String time,
    String id,
  ) {
    final byTime = DateTime.parse(b[time] as String)
        .compareTo(DateTime.parse(a[time] as String));
    return byTime != 0 ? byTime : (b[id] as String).compareTo(a[id] as String);
  }

  Future<BookingCreationOutcome> createPending({
    required String clientRequestId,
    required String providerId,
    required String propertyId,
    required String serviceTypeId,
    required DateTime start,
    required DateTime end,
    required num expectedAmount,
    required String expectedBasis,
    String instructions = '',
  }) async {
    if (!end.isAfter(start)) {
      throw ArgumentError('The booking end must be after the start.');
    }
    if (expectedAmount <= 0 ||
        (expectedBasis != 'hourly' && expectedBasis != 'daily')) {
      throw ArgumentError('Select a valid server-provided quote.');
    }
    // The database function is authoritative for Owner role, property
    // ownership, approval, service, full-interval availability and conflicts.
    // A stable token prevents duplicate Pending rows on network retries.
    final response = await _writeRpc(
      'create_pending_booking',
      params: {
        'p_client_request_id': clientRequestId,
        'p_provider_id': providerId,
        'p_property_id': propertyId,
        'p_service_type_id': serviceTypeId,
        'p_start_at': start.toUtc().toIso8601String(),
        'p_end_at': end.toUtc().toIso8601String(),
        'p_expected_amount': expectedAmount,
        'p_expected_basis': expectedBasis,
        'p_instructions': instructions.trim(),
      },
    );
    return BookingCreationOutcome.fromResponse(
      Map<String, dynamic>.from(response as Map),
    );
  }

  /// Read-after-uncertain-write: RLS restricts the lookup to the Owner.
  Future<String?> createdBookingIdForToken(String clientRequestId) async {
    final row = await client
        .from('booking')
        .select('booking_id')
        .eq('owner_id', _userId)
        .eq('client_request_id', clientRequestId)
        .maybeSingle();
    return row?['booking_id'] as String?;
  }

  Future<String?> currentStatus(String bookingId) async {
    final row = await client
        .from('booking')
        .select('current_status')
        .eq('booking_id', bookingId)
        .maybeSingle();
    return row?['current_status'] as String?;
  }

  Future<AcceptanceOutcome> acceptPending(String bookingId) async {
    final response = await _writeRpc(
      'accept_pending_booking',
      params: {'p_booking_id': bookingId},
    );
    final value = Map<String, dynamic>.from(response as Map);
    return AcceptanceOutcome(
      accepted: value['accepted'] == true,
      reason: value['reason'] as String?,
    );
  }

  /// Accepted must never be requested here; it has a separate recheck RPC.
  Future<String> transition(
    String bookingId,
    String nextStatus, {
    String? reason,
  }) async {
    const allowed = {'Declined', 'Cancelled', 'In Progress', 'Completed'};
    if (!allowed.contains(nextStatus)) {
      throw ArgumentError('Use acceptPending for acceptance.');
    }
    if (nextStatus == 'Cancelled' &&
        (reason == null ||
            reason.trim().isEmpty ||
            reason.trim().length > 300)) {
      throw ArgumentError(
        'A cancellation reason of up to 300 characters is required.',
      );
    }
    final response = await _writeRpc(
      'transition_booking',
      params: {
        'p_booking_id': bookingId,
        'p_new_status': nextStatus,
        'p_reason': reason,
      },
    );
    return Map<String, dynamic>.from(response as Map)['status'] as String;
  }

  Future<AcceptanceOutcome> revisePending({
    required String bookingId,
    required DateTime start,
    required DateTime end,
    required String instructions,
  }) async {
    if (!end.isAfter(start)) {
      throw ArgumentError('The booking end must be after the start.');
    }
    final response = await _writeRpc(
      'revise_pending_booking',
      params: {
        'p_booking_id': bookingId,
        'p_start_at': start.toUtc().toIso8601String(),
        'p_end_at': end.toUtc().toIso8601String(),
        'p_instructions': instructions,
      },
    );
    final value = Map<String, dynamic>.from(response as Map);
    return AcceptanceOutcome(
      accepted: value['revised'] == true,
      reason: value['reason'] as String?,
    );
  }

  Future<CursorPage<Map<String, dynamic>>> historyPage(
    String bookingId,
    PageCursor? before,
  ) async =>
      CursorPage.decode(
        await client.rpc(
          'page_booking_history',
          params: {
            'p_booking_id': bookingId,
            'p_limit': 20,
            'p_before_at': before?.timestamp,
            'p_before_id': before?.id,
          },
        ),
        (row) => row,
      );

  CursorFeed<Map<String, dynamic>> openHistory(
    String bookingId, {
    bool active = true,
  }) {
    final ownerId = _userId;
    return CursorFeed(
      active: active,
      ownerUserId: ownerId,
      currentUserId: () => client.auth.currentUser?.id,
      sessionChanges:
          client.auth.onAuthStateChange.map((state) => state.session?.user.id),
      loadPage: (cursor) => historyPage(bookingId, cursor),
      idOf: (row) => row['status_history_id'] as String,
      compare: (a, b) => compareRows(a, b, 'changed_at', 'status_history_id'),
    );
  }

  Stream<String?> watchStatus(String bookingId) {
    final ownerId = _userId;
    return boundedLiveValue(
      read: () async {
        if (client.auth.currentUser?.id != ownerId) {
          throw StateError('Session changed.');
        }
        final status = await currentStatus(bookingId);
        if (client.auth.currentUser?.id != ownerId) {
          throw StateError('Session changed.');
        }
        return status;
      },
      changes: () => pagedRowChanges(
        client,
        table: 'booking',
        idColumn: 'booking_id',
        filterColumn: 'booking_id',
        filterValue: bookingId,
      ),
    );
  }
}
