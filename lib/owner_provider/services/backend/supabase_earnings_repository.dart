import 'package:supabase_flutter/supabase_flutter.dart';
import 'earnings_snapshot.dart';
import 'cursor_feed.dart';

class SupabaseEarningsRepository {
  const SupabaseEarningsRepository(this.client);
  final SupabaseClient client;
  Future<EarningsSnapshot> read(EarningsPeriod period,
      {PageCursor? before, String? asOf}) async {
    final actor = client.auth.currentUser?.id;
    if (actor == null) throw StateError('Sign in required.');
    if (before != null && asOf == null)
      throw ArgumentError('Snapshot required for paging.');
    final value = await client.rpc('provider_earnings', params: {
      'p_period': period.name,
      'p_before_at': before?.timestamp,
      'p_before_id': before?.id,
      'p_as_of': asOf
    });
    if (client.auth.currentUser?.id != actor)
      throw StateError('Session changed.');
    return EarningsSnapshot.parse(
        Map<String, dynamic>.from(value as Map), actor, period);
  }
}
