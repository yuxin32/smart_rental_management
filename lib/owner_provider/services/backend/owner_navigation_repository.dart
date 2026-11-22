import 'dart:convert';
import 'cursor_feed.dart';
import 'session_snapshot_cache.dart';
import 'paged_realtime.dart';
import 'supabase_backend_provider.dart';
import 'supabase_booking_repository.dart';

class OwnerNavigationRepository {
  const OwnerNavigationRepository(this.backend);
  final SupabaseBackendProvider backend;

  CursorFeed<Map<String, dynamic>> open({
    required bool providers,
    String query = '',
    String group = 'all',
    bool oldest = false,
  }) {
    final client = backend.client;
    final actor = client.auth.currentUser?.id;
    if (actor == null) throw StateError('Owner sign-in required');
    final term = query.trim();
    if (term.runes.length > 80) throw ArgumentError('Search is too long');
    final key =
        'owner-navigation:${jsonEncode([providers, term, group, oldest])}';
    final time = providers ? 'listed_at' : 'created_at';
    final id = providers ? 'provider_id' : 'booking_id';
    return CursorFeed(
      active: false,
      ownerUserId: actor,
      currentUserId: () => client.auth.currentUser?.id,
      sessionChanges:
          client.auth.onAuthStateChange.map((s) => s.session?.user.id),
      preserveOnRefresh: true,
      initialPage:
          backend.snapshots.peek<CursorPage<Map<String, dynamic>>>(key)?.value,
      onSnapshotRejected: backend.snapshots.clear,
      loadPage: (cursor) async {
        final lease = backend.snapshots.lease();
        try {
          final raw = Map<String, dynamic>.from(await client.rpc(
            providers
                ? 'page_approved_provider_directory'
                : 'page_owner_booking_search',
            params: {
              'p_query': term,
              if (!providers) 'p_group': group,
              if (!providers) 'p_oldest': oldest,
              'p_limit': 20,
              'p_before_at': cursor?.timestamp,
              'p_before_id': cursor?.id,
            },
          ) as Map);
          if (client.auth.currentUser?.id != actor ||
              raw['actor_id'] != actor ||
              !backend.snapshots.valid(lease)) {
            throw StateError('Session or data changed');
          }
          final page = CursorPage.decode(
              raw, (r) => Map<String, dynamic>.unmodifiable(r));
          if (cursor == null)
            backend.snapshots.put(key, page,
                lease: lease, bytes: utf8.encode(jsonEncode(raw)).length);
          return page;
        } catch (error) {
          if (rejectsSnapshot(error)) backend.snapshots.clear();
          rethrow;
        }
      },
      idOf: (r) => r[id] as String,
      compare: (a, b) =>
          (!providers && oldest ? -1 : 1) *
          SupabaseBookingRepository.compareRows(a, b, time, id),
      // Booking edits can enter or leave a search result. Re-run the filtered
      // head instead of merging an unfiltered row into the active view.
      watchChanges: providers
          ? null
          : () => pagedRowChanges(client,
                  table: 'booking',
                  idColumn: 'booking_id',
                  filterColumn: 'owner_id',
                  filterValue: actor)
              .map((_) => const PageChange(PageChangeKind.reset)),
    );
  }
}
