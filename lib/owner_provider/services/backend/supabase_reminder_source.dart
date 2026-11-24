import 'package:supabase_flutter/supabase_flutter.dart';
import '../booking_reminder.dart';
import 'paged_realtime.dart';
import 'cursor_feed.dart';

/// Read fresh, earliest Accepted jobs; never schedule from a dashboard cache.
class SupabaseReminderSource {
  const SupabaseReminderSource(this.client);
  final SupabaseClient client;
  Future<List<ReminderBooking>> read(String actor, DateTime now) async {
    if (client.auth.currentUser?.id != actor)
      throw StateError('Session changed.');
    final raw = List<Map<String, dynamic>>.from(await client
        .from('booking')
        .select(
            'booking_id,provider_id,current_status,requested_start_at,requested_end_at')
        .eq('provider_id', actor)
        .eq('current_status', 'Accepted')
        .gt('requested_start_at', now.toUtc().toIso8601String())
        .lt('requested_start_at',
            now.toUtc().add(const Duration(days: 31)).toIso8601String())
        .order('requested_start_at')
        .order('booking_id')
        .limit(101));
    if (client.auth.currentUser?.id != actor)
      throw StateError('Session changed.');
    return raw.map((row) => ReminderBooking.parse(row, actor)).toList();
  }

  Stream<PageChange> watch(String actor) => pagedRowChanges(client,
      table: 'booking',
      idColumn: 'booking_id',
      filterColumn: 'provider_id',
      filterValue: actor);
}
