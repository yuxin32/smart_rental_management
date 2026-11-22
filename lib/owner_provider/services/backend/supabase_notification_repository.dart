import 'package:supabase_flutter/supabase_flutter.dart';
import 'cursor_feed.dart';
import 'notification_snapshot.dart';

class SupabaseNotificationRepository {
  const SupabaseNotificationRepository(this.client);
  final SupabaseClient client;
  String get _actor =>
      client.auth.currentUser?.id ?? (throw StateError('Sign in required'));
  Future<NotificationSnapshot> page(NotificationFilter filter,
      {PageCursor? before, String? asOf}) async {
    final actor = _actor;
    final row = await client.rpc('page_my_notifications', params: {
      'p_filter': filter.name,
      'p_limit': 20,
      'p_before_at': before?.timestamp,
      'p_before_id': before?.id,
      'p_as_of': asOf
    });
    if (_actor != actor) throw StateError('Session changed');
    return NotificationSnapshot.parse(
        Map<String, dynamic>.from(row as Map), actor, filter);
  }

  Future<void> mark({List<String>? ids, String? throughAt}) async {
    final actor = _actor;
    if ((ids == null) == (throughAt == null) ||
        (ids != null && (ids.isEmpty || ids.length > 100)))
      throw ArgumentError('Explicit notification IDs or snapshot required');
    await client.rpc('read_my_notifications',
        params: {'p_ids': ids, 'p_through_at': throughAt});
    if (_actor != actor) throw StateError('Session changed');
  }
}
