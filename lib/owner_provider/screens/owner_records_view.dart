import '../presentation/workspace_text.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/backend/cursor_feed.dart';
import '../services/backend/workspace_binding.dart';
import '../theme/app_theme.dart';
import '../widgets/booking_card.dart';
import '../widgets/connected_route_lifecycle.dart';

typedef OwnerRecordFeedFactory = CursorFeed<Map<String, dynamic>> Function(
    {required bool providers,
    required String query,
    required String group,
    required bool oldest});

/// Distinct tab contents; the existing Owner shell owns AppBar and bottom menu.
class OwnerRecordsView extends StatefulWidget {
  const OwnerRecordsView(
      {super.key,
      required this.providers,
      required this.openFeed,
      this.onBooking,
      this.onProvider});
  final bool providers;
  final OwnerRecordFeedFactory openFeed;
  final ValueChanged<String>? onBooking;
  final ValueChanged<Map<String, dynamic>>? onProvider;
  @override
  State<OwnerRecordsView> createState() => _OwnerRecordsViewState();
}

class _OwnerRecordsViewState extends State<OwnerRecordsView>
    with ConnectedRouteLifecycle<OwnerRecordsView> {
  final search = TextEditingController();
  final scroll = ScrollController();
  Timer? debounce;
  String query = '', group = 'all';
  String statusTab = 'all';
  String historyGroup = 'history';
  bool oldest = false;
  String? inputError;
  late CursorFeed<Map<String, dynamic>> feed;
  @override
  void initState() {
    super.initState();
    _open();
  }

  void _open() {
    feed = widget.openFeed(
        providers: widget.providers, query: query, group: group, oldest: oldest)
      ..addListener(_changed);
    feed.setActive(connectedRouteActive);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _apply() {
    debounce?.cancel();
    if (search.text.trim().runes.length > 80) {
      setState(() => inputError = 'Use at most 80 characters in your search.');
      return;
    }
    inputError = null;
    feed.removeListener(_changed);
    feed.dispose();
    query = search.text.trim();
    _open();
    if (scroll.hasClients) scroll.jumpTo(0);
    setState(() {});
  }

  @override
  void onConnectedRouteActivity(bool active) => feed.setActive(active);
  @override
  void dispose() {
    debounce?.cancel();
    feed.removeListener(_changed);
    feed.dispose();
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColors.of(context);
    final rows = feed.items;
    final label = widget.providers ? 'providers' : 'bookings';
    if (feed.sessionEnded)
      return const Center(child: Text('Sign in again to view this page.'));
    return RefreshIndicator(
      onRefresh: feed.refresh,
      child: ListView(
        controller: scroll,
        key: ValueKey(
            'owner-${widget.providers ? 'providers' : 'bookings'}-records'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Text(
              widget.providers
                  ? 'Browse cleaning providers'
                  : 'All your bookings',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary)),
          const SizedBox(height: 6),
          Text(
              widget.providers
                  ? 'Compare services, areas and rates. Availability is checked when you request cleaning from Home.'
                  : 'Search every booking, follow current requests or review your history.',
              style: TextStyle(color: colors.textSecondary, height: 1.5)),
          const SizedBox(height: 18),
          TextField(
            key: const Key('owner-record-search'),
            controller: search,
            maxLength: 80,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              errorText: inputError,
              errorMaxLines: 3,
              labelText: widget.providers
                  ? 'Search name, area or service'
                  : 'Search unit, building or service',
              prefixIcon: const Icon(Icons.search),
              counterText: '',
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        search.clear();
                        _apply();
                      }),
            ),
            onChanged: (_) {
              debounce?.cancel();
              setState(() {});
              debounce = Timer(const Duration(milliseconds: 350), _apply);
            },
            onSubmitted: (_) {
              FocusScope.of(context).unfocus();
              _apply();
            },
          ),
          if (!widget.providers) ...[
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final entry in const {
                  'all': 'All',
                  'pending': 'Pending',
                  'ongoing': 'Ongoing',
                  'history': 'History',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: statusTab == entry.key,
                      onSelected: (_) {
                        statusTab = entry.key;
                        historyGroup = 'history';
                        group = statusTab;
                        _apply();
                      },
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: const Key('owner-booking-group'),
              value: historyGroup,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'History filter',
                helperText: statusTab == 'history'
                    ? 'Filter finished requests.'
                    : 'Select History above to use this filter.',
                helperMaxLines: 2,
              ),
              items: const {
                'history': 'All history',
                'completed': 'Completed',
                'cancelled': 'Cancelled',
                'declined': 'Declined',
              }
                  .entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: statusTab != 'history'
                  ? null
                  : (value) {
                      if (value != null) {
                        historyGroup = value;
                        group = value;
                        _apply();
                      }
                    },
            ),
            const SizedBox(height: 10),
            Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.sort),
                  label: Text(oldest ? 'Oldest first' : 'Newest first'),
                  onPressed: () {
                    oldest = !oldest;
                    _apply();
                  },
                )),
          ],
          const SizedBox(height: 16),
          if (feed.loading && !feed.hasSnapshot)
            const LinearProgressIndicator(),
          if (feed.error != null || feed.refreshError != null)
            _retry(
                'Could not ${rows.isEmpty ? 'load' : 'refresh'} $label. ${rows.isEmpty ? 'Check your connection and retry.' : 'Previously saved results are still shown.'}',
                feed.refresh),
          if (feed.liveError != null)
            _retry('Live updates are interrupted.', feed.retryLive),
          if (!feed.loading && feed.error == null && rows.isEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(children: [
                  Icon(
                      widget.providers
                          ? Icons.person_search_outlined
                          : Icons.event_note_outlined,
                      size: 42,
                      color: colors.textTertiary),
                  const SizedBox(height: 12),
                  Text(
                      query.isNotEmpty || group != 'all'
                          ? 'No matching $label'
                          : 'No $label yet',
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(
                      query.isNotEmpty || group != 'all'
                          ? 'Try another search or status.'
                          : widget.providers
                              ? 'Approved providers will appear here when available.'
                              : 'Your requests and booking history will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.textSecondary)),
                ])),
          for (final row in rows) ...[
            if (widget.providers)
              _provider(context, row)
            else
              BookingCard(
                  booking: WorkspaceBinding.projectBooking(row),
                  onTap: () =>
                      widget.onBooking?.call(row['booking_id'] as String)),
            const SizedBox(height: 12),
          ],
          if (rows.isNotEmpty)
            Text(
                '${rows.length} ${rows.length == 1 ? (widget.providers ? 'provider' : 'booking') : label} shown',
                style: TextStyle(color: colors.textSecondary)),
          if (feed.moreError != null)
            const Text('Could not load more. Your current results are kept.'),
          if (feed.hasMore || feed.loadingMore) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: feed.loadingMore ? null : feed.loadMore,
                icon: const Icon(Icons.expand_more),
                label: Text(feed.loadingMore
                    ? 'Loading…'
                    : feed.moreError != null
                        ? 'Retry loading more'
                        : 'Show more $label')),
          ],
        ],
      ),
    );
  }

  Widget _retry(String text, VoidCallback retry) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text),
        TextButton(onPressed: retry, child: const Text('Retry'))
      ]));

  Widget _provider(BuildContext context, Map<String, dynamic> row) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(Icons.cleaning_services_outlined,
                        color:
                            Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(providerDirectoryName(row),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 18),
                  const SizedBox(width: 4),
                  Expanded(child: Text(row['service_area'] as String)),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final service in providerServices(row))
                    Chip(
                        label: Text(service['name'] as String),
                        visualDensity: VisualDensity.compact),
                ]),
                const SizedBox(height: 10),
                Text(providerRateLabel(row),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(
                    '${row['rating_average'] == null ? 'No ratings yet' : '${row['rating_average']} / 5'} · ${row['completed_job_count']} completed jobs'),
                const SizedBox(height: 12),
                Text('Availability checked when you request cleaning',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                OutlinedButton(
                    onPressed: () => widget.onProvider?.call(row),
                    child: const Text('View profile')),
              ],
            )),
      );
}

String providerDirectoryName(Map<String, dynamic> row) =>
    (row['full_name'] as String?)?.trim().isNotEmpty == true
        ? workspaceText(row['full_name'] as String)
        : 'Cleaning provider';
List<Map<String, dynamic>> providerServices(Map<String, dynamic> row) =>
    List<Map<String, dynamic>>.from(row['services'] as List);
String providerRateLabel(Map<String, dynamic> row) => [
      if (row['hourly_rate'] is num)
        'RM ${(row['hourly_rate'] as num).toStringAsFixed(2)}/hour',
      if (row['daily_rate'] is num)
        'RM ${(row['daily_rate'] as num).toStringAsFixed(2)}/8-hour day',
    ].join(' · ');

class OwnerProviderDetails extends StatelessWidget {
  const OwnerProviderDetails({super.key, required this.row});
  final Map<String, dynamic> row;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Provider profile')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Text(providerDirectoryName(row),
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(row['service_area'] as String),
          if ((row['bio'] as String?)?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 16),
            Text(row['bio'] as String),
          ],
          const SizedBox(height: 20),
          Text(providerRateLabel(row),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
              '${row['rating_average'] == null ? 'No ratings yet' : '${row['rating_average']} / 5'} · ${row['completed_job_count']} completed jobs'),
          const SizedBox(height: 24),
          const Text('Services',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          for (final service in providerServices(row)) ...[
            const SizedBox(height: 14),
            Text(service['name'] as String,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            Text((service['description'] as String?)?.trim().isNotEmpty == true
                ? service['description'] as String
                : 'Confirm specific tasks with the provider before work starts.'),
          ],
          const SizedBox(height: 24),
          const Text(
              'This profile shows the latest information loaded in the directory. Rates are not a booking quote. Use Request cleaning on Home to choose your rental unit, service and time and check available providers.'),
        ]),
      );
}
