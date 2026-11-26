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
        padding: EdgeInsets.all(widget.providers ? 20 : 16),
        children: [
          if (widget.providers) ...[
            Text('Browse cleaning providers',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                    color: colors.textPrimary)),
            const SizedBox(height: 6),
            Text('Compare services, areas and rates. Availability is checked when you request cleaning from Home.',
                style: TextStyle(color: colors.textSecondary, height: 1.5)),
            const SizedBox(height: 18),
            _searchField(),
          ] else
            _bookingControls(rows.length),
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
          if (widget.providers && rows.isNotEmpty)
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

  Widget _searchField({bool compact = false}) => TextField(
        key: const Key('owner-record-search'),
        controller: search,
        maxLength: 80,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          errorText: inputError,
          errorMaxLines: 3,
          labelText: compact ? null : 'Search name, area or service',
          hintText: compact ? 'Search bookings' : null,
          isDense: compact,
          contentPadding: compact
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
              : null,
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
      );

  Widget _sortMenu() {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Sort bookings. ${oldest ? 'Oldest first' : 'Newest first'}',
      child: PopupMenuButton<bool>(
        key: const Key('owner-booking-sort'),
        tooltip: 'Sort bookings',
        initialValue: oldest,
        onSelected: (value) {
          if (oldest == value) return;
          oldest = value;
          _apply();
        },
        itemBuilder: (_) => [
          CheckedPopupMenuItem(
            value: false,
            checked: !oldest,
            child: const Text('Newest first'),
          ),
          CheckedPopupMenuItem(
            value: true,
            checked: oldest,
            child: const Text('Oldest first'),
          ),
        ],
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: oldest ? scheme.primaryContainer : scheme.surface,
            border: Border.all(color: oldest ? scheme.primary : scheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.sort, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Text('Sort', style: TextStyle(color: scheme.primary)),
          ]),
        ),
      ),
    );
  }

  Widget _bookingControls(int count) {
    final theme = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < scale.scale(14) * 10 + scale.scale(14) * 5 + 24) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _searchField(compact: true),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: _sortMenu()),
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _searchField(compact: true)),
          const SizedBox(width: 8),
          _sortMenu(),
        ]);
      }),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, constraints) {
        final minWidth = scale.scale(13) * 4 + 16;
        final columns = constraints.maxWidth >= minWidth * 4 + 12 ? 4 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 4) / columns;
        return Wrap(spacing: 4, runSpacing: 4, children: [
          for (final entry in const {
            'all': 'All',
            'pending': 'Pending',
            'ongoing': 'Ongoing',
            'history': 'History',
          }.entries)
            SizedBox(
              width: width,
              child: TextButton(
                key: ValueKey('owner-booking-tab-${entry.key}'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 10),
                  textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
                  backgroundColor: statusTab == entry.key ? theme.colorScheme.primary : null,
                  foregroundColor: statusTab == entry.key
                      ? theme.colorScheme.onPrimary
                      : SemanticColors.of(context).textSecondary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  if (statusTab == entry.key) return;
                  statusTab = entry.key;
                  historyGroup = 'history';
                  group = statusTab;
                  _apply();
                },
                child: Semantics(selected: statusTab == entry.key, child: Text(entry.value)),
              ),
            ),
        ]);
      }),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, constraints) {
        final pickerWidth = (154 * scale.scale(12) / 12)
            .clamp(0.0, constraints.maxWidth).toDouble();
        final summaryLabel = feed.loading && !feed.hasSnapshot
            ? 'Checking bookings'
            : feed.error != null && !feed.hasSnapshot
                ? 'Bookings unavailable'
                : '$count ${count == 1 ? 'booking' : 'bookings'} shown';
        final summary = Text(
          '$summaryLabel · ${oldest ? 'Oldest' : 'Newest'}',
          style: theme.textTheme.bodySmall,
        );
        final picker = SizedBox(
          width: pickerWidth,
          child: Semantics(
            label: 'History filter',
            child: InputDecorator(
              decoration: InputDecoration(
                enabled: statusTab == 'history',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const Key('owner-booking-group'),
                  value: historyGroup,
                  isExpanded: true,
                  isDense: false,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface),
                  items: const {
                    'history': 'All history',
                    'completed': 'Completed',
                    'cancelled': 'Cancelled',
                    'declined': 'Declined',
                  }.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                  onChanged: statusTab != 'history' ? null : (value) {
                    if (value == null || value == historyGroup) return;
                    historyGroup = value;
                    group = value;
                    _apply();
                  },
                ),
              ),
            ),
          ),
        );
        if (pickerWidth + scale.scale(12) * 7 + 12 > constraints.maxWidth) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            summary,
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: picker),
          ]);
        }
        return Row(children: [Expanded(child: summary), const SizedBox(width: 12), picker]);
      }),
    ]);
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

/// Owner-facing directory details. A request still uses the existing server-
/// checked form; browsing this snapshot does not select or reserve a Provider.
class OwnerProviderDetails extends StatefulWidget {
  const OwnerProviderDetails({
    super.key,
    required this.row,
    this.onRequestCleaning,
  });
  final Map<String, dynamic> row;
  final Future<void> Function()? onRequestCleaning;

  @override
  State<OwnerProviderDetails> createState() => _OwnerProviderDetailsState();
}

class _OwnerProviderDetailsState extends State<OwnerProviderDetails> {
  bool _requesting = false;

  Future<void> _request() async {
    if (_requesting || widget.onRequestCleaning == null) return;
    setState(() => _requesting = true);
    try {
      await widget.onRequestCleaning!();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open your cleaning request. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  String _amount(num amount) => amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
  );

  Widget _rate(String label, num amount, String unit) {
    final sem = SemanticColors.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: sem.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: sem.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: sem.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'RM ${_amount(amount)}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  unit,
                  style: TextStyle(color: sem.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _rates() {
    final hourly = widget.row['hourly_rate'];
    final daily = widget.row['daily_rate'];
    final cards = <Widget>[
      if (hourly is num && hourly.isFinite && hourly > 0)
        _rate('Hourly', hourly, '/ hour'),
      if (daily is num && daily.isFinite && daily > 0)
        _rate('8-hour day', daily, '/ day'),
    ];
    if (cards.isEmpty) return const Text('Rates unavailable.');
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (cards.length == 1 || constraints.maxWidth < 280 * scale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                cards[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 10),
            Expanded(child: cards[1]),
          ],
        );
      },
    );
  }

  Widget _services() {
    final services = providerServices(widget.row);
    final sem = SemanticColors.of(context);
    if (services.isEmpty) return const Text('No services listed yet.');
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: sem.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: sem.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          children: [
            for (var i = 0; i < services.length; i++) ...[
              if (i > 0) Divider(height: 1, color: sem.border),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: sem.primarySurface,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        Icons.cleaning_services_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            services[i]['name'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            (services[i]['description'] as String?)
                                        ?.trim()
                                        .isNotEmpty ==
                                    true
                                ? services[i]['description'] as String
                                : 'Confirm specific tasks with the provider before work starts.',
                            style: TextStyle(color: sem.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    final bio = widget.row['bio'] as String?;
    final completed = widget.row['completed_job_count'];
    return Scaffold(
      appBar: AppBar(title: const Text('Provider profile')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: sem.primarySurface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.auto_awesome_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      providerDirectoryName(widget.row),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          color: sem.textSecondary,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.row['service_area'] as String,
                            style: TextStyle(color: sem.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                Icons.star_border_rounded,
                size: 17,
                color: sem.textSecondary,
              ),
              Text(
                widget.row['rating_average'] == null
                    ? 'No ratings yet'
                    : '${widget.row['rating_average']} / 5',
              ),
              Text('·', style: TextStyle(color: sem.textSecondary)),
              Text(
                '$completed completed ${completed == 1 ? 'job' : 'jobs'}',
                style: TextStyle(color: sem.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _heading('Rates'),
          _rates(),
          const SizedBox(height: 8),
          Text(
            'Final quote shown before you send a request.',
            style: TextStyle(color: sem.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 20),
          _heading('Services'),
          _services(),
          if (bio?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 14),
            Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              color: sem.surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: sem.border),
              ),
              child: ExpansionTile(
                title: const Text(
                  'About this provider',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                shape: const Border(),
                collapsedShape: const Border(),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      bio!,
                      style: TextStyle(color: sem.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _requesting || widget.onRequestCleaning == null
                      ? null
                      : _request,
                  icon: _requesting
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.event_available_outlined, size: 18),
                  label: const Text('Request cleaning'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Availability checked for your unit and selected time.',
                textAlign: TextAlign.center,
                style: TextStyle(color: sem.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
