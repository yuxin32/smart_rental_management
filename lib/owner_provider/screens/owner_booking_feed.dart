import 'package:flutter/material.dart';
import '../models/demo_data.dart';
import '../services/backend/cursor_feed.dart';
import '../services/backend/supabase_backend_provider.dart';
import '../services/backend/supabase_booking_repository.dart';
import '../services/backend/workspace_binding.dart';
import '../widgets/booking_card.dart';
import '../widgets/connected_route_lifecycle.dart';

/// The inline dashboard and status destinations share the original BookingCard.
/// Each owns a bounded, server-filtered feed and stops its channel off-screen.
class OwnerBookingFeed extends StatefulWidget {
  const OwnerBookingFeed(
      {super.key,
      this.backend,
      this.feed,
      required this.group,
      required this.onBooking,
      this.inline = false})
      : assert(backend != null || feed != null);
  final SupabaseBackendProvider? backend;
  final CursorFeed<Map<String, dynamic>>? feed;
  final OwnerBookingGroup group;
  final ValueChanged<DemoBooking> onBooking;
  final bool inline;
  @override
  State<OwnerBookingFeed> createState() => OwnerBookingFeedState();
}

class OwnerBookingFeedState extends State<OwnerBookingFeed>
    with
        ConnectedRouteLifecycle<OwnerBookingFeed>,
        AutomaticKeepAliveClientMixin<OwnerBookingFeed> {
  @override
  bool get wantKeepAlive => widget.inline;
  late final feed =
      widget.feed ?? widget.backend!.bookings.openOwnerFeed(widget.group);
  int visible = 3;
  Future<void> refresh() => feed.refresh();
  @override
  void initState() {
    super.initState();
    feed.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void onConnectedRouteActivity(bool active) => feed.setActive(active);
  @override
  void dispose() {
    feed.removeListener(_changed);
    feed.dispose();
    super.dispose();
  }

  Future<void> more() async {
    if (feed.loadingMore || feed.loading) return;
    if (widget.inline && visible < feed.items.length) {
      setState(() => visible += 3);
    } else {
      await feed.loadMore();
      if (mounted && feed.moreError == null) setState(() => visible += 3);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    List<DemoBooking> bookings;
    try {
      bookings = feed.items.map(WorkspaceBinding.projectBooking).toList();
    } catch (_) {
      return _frame(
          _notice('Could not display bookings. Please refresh.', feed.refresh));
    }
    if (feed.sessionEnded)
      return _frame(const Text('Sign in again to view your bookings.'));
    final body =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (feed.loading && !feed.hasSnapshot) const LinearProgressIndicator(),
      if (feed.error != null && bookings.isEmpty)
        _notice('Could not load bookings.', feed.refresh)
      else if (!feed.loading && bookings.isEmpty)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(widget.inline
                ? widget.group == OwnerBookingGroup.pending
                    ? 'No pending requests.'
                    : 'No upcoming bookings.'
                : 'No ${widget.group.label.toLowerCase()} bookings.')),
      if (feed.refreshError != null)
        _notice('Could not refresh. Your previous bookings are still shown.',
            feed.refresh),
      if (feed.liveError != null)
        _notice('Live updates are interrupted.', feed.retryLive),
      if (widget.group == OwnerBookingGroup.active)
        const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Accepted bookings and cleaning in progress.')),
      for (final booking
          in bookings.take(widget.inline ? visible : bookings.length))
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: BookingCard(
                key: ValueKey('owner-feed-${booking.id}'),
                booking: booking,
                onTap: () => widget.onBooking(booking))),
      if (feed.moreError != null)
        const Text('Could not show more bookings. Please retry.'),
      if ((widget.inline && visible < bookings.length) ||
          feed.hasMore ||
          feed.loadingMore)
        OutlinedButton.icon(
            key: const Key('show-more-bookings'),
            onPressed: feed.loading || feed.loadingMore ? null : more,
            icon: const Icon(Icons.expand_more),
            label: Text(feed.loadingMore
                ? 'Loading…'
                : feed.moreError != null
                    ? 'Retry showing more'
                    : 'Show more bookings')),
    ]);
    return _frame(body);
  }

  Widget _frame(Widget body) {
    if (widget.inline) return body;
    return Scaffold(
        appBar: AppBar(title: Text('${widget.group.label} bookings')),
        body: RefreshIndicator(
            onRefresh: feed.refresh,
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [body])));
  }

  Widget _notice(String text, VoidCallback retry) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text),
        TextButton(onPressed: retry, child: const Text('Retry'))
      ]));
}
