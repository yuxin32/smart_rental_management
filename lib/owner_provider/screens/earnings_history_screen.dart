// lib/screens/earnings_history_screen.dart
// Provider earnings dashboard: period total, period-aware chart and stats,
// per-job breakdown with platform fee and net.
//
// Round 8 polish (E1-E7):
//   E1 Theme gradient (AppColors.primary + primaryLight, not hardcoded emerald)
//   E2 Period filter: compact chips (Last 30 days / This month / All time)
//   E3 Theme-aware text in tiles (sem.textPrimary vs hardcoded #111827)
//   E4 intl.DateFormat for "21 Jul 2026" instead of hand-rolled month list
//   E5 Tap action on earnings tile → persistent earnings breakdown sheet
//   E6 Platform fee shown as % next to RM value
//   E7 Stats grid uses AppColors (primary / secondary / warning)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/demo_data.dart';
import '../services/backend/earnings_binding.dart';
import '../widgets/snapshot_refresh_notice.dart';
import '../services/backend/earnings_snapshot.dart';
import '../widgets/connected_state_panel.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/compact_earnings_chart.dart';
import '../widgets/section_header.dart';

/// Time range used by the period filter.
typedef _EarningsPeriod = EarningsPeriod;

class EarningsHistoryScreen extends StatefulWidget {
  const EarningsHistoryScreen(
      {super.key,
      required this.providerName,
      required this.bookings,
      this.providers,
      this.binding,
      this.bottomNavigationBar});
  final String providerName;
  final List<DemoBooking> bookings;
  final List<DemoProvider>? providers;
  final EarningsBinding? binding;
  final Widget? bottomNavigationBar;

  @override
  State<EarningsHistoryScreen> createState() => _EarningsHistoryScreenState();
}

class _EarningsHistoryScreenState extends State<EarningsHistoryScreen> {
  _EarningsPeriod _period = _EarningsPeriod.thisMonth;
  bool _showTrend = false;
  bool get _connected => widget.binding != null;
  EarningsSnapshot? get _report => widget.binding?.snapshot;
  @override
  void initState() {
    super.initState();
    widget.binding?.addListener(_changed);
  }

  @override
  void didUpdateWidget(EarningsHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.binding != widget.binding) {
      oldWidget.binding?.removeListener(_changed);
      widget.binding?.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.binding?.removeListener(_changed);
    super.dispose();
  }

  /// Filter the global summary's records by the selected period and
  /// recompute period-scoped aggregates.
  EarningsSummary _scopedSummary(
      EarningsSummary global, _EarningsPeriod period) {
    final now = DateTime.now();
    final cutoff = period.earliest(now);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final filtered = global.records
        .where((r) =>
            (cutoff == null || !r.date.isBefore(cutoff)) &&
            r.date.isBefore(tomorrow))
        .toList();
    if (filtered.isEmpty) {
      return EarningsSummary(
        providerName: global.providerName,
        totalNet: 0,
        weeklyNet: global.weeklyNet,
        monthlyNet: global.monthlyNet,
        jobsCompleted: 0,
        avgPerJob: 0,
        records: const [],
      );
    }
    final total = filtered.fold<double>(0, (a, r) => a + r.net);
    final avg = total / filtered.length;
    return EarningsSummary(
      providerName: global.providerName,
      totalNet: total,
      weeklyNet: global.weeklyNet,
      monthlyNet: global.monthlyNet,
      jobsCompleted: filtered.length,
      avgPerJob: avg,
      records: filtered,
    );
  }

  String _periodDateRange(EarningsSummary summary, DateTime now) {
    if (_report case final report?) {
      return '${DateFormat('d MMM yyyy').format(report.start)} – ${DateFormat('d MMM yyyy').format(report.end)} · MYT';
    }
    final today = DateTime(now.year, now.month, now.day);
    final DateTime start;
    switch (_period) {
      case _EarningsPeriod.last30:
        start = DateTime(today.year, today.month, today.day - 29);
      case _EarningsPeriod.thisMonth:
        start = DateTime(today.year, today.month, 1);
      case _EarningsPeriod.allTime:
        if (summary.records.isEmpty) return 'No completed jobs yet';
        final earliest = summary.records
            .map((record) => record.date)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        start = DateTime(earliest.year, earliest.month, earliest.day);
    }
    if (start.isAtSameMomentAs(today)) {
      return DateFormat('d MMM yyyy').format(today);
    }
    if (start.year == today.year && start.month == today.month) {
      return '${start.day}–${DateFormat('d MMM yyyy').format(today)}';
    }
    if (start.year == today.year) {
      return '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM yyyy').format(today)}';
    }
    return '${DateFormat('d MMM yyyy').format(start)} – ${DateFormat('d MMM yyyy').format(today)}';
  }

  @override
  Widget build(BuildContext context) {
    final binding = widget.binding;
    if (binding != null) _period = binding.period;
    if (binding != null && (binding.error != null || _report == null)) {
      return Scaffold(
          bottomNavigationBar: widget.bottomNavigationBar,
          appBar: AppBar(title: const Text('Earnings')),
          body: ConnectedStatePanel(
              state: binding.loading
                  ? ConnectedViewState.loading
                  : ConnectedViewState.error,
              title: binding.sessionEnded
                  ? 'Sign in again'
                  : binding.loading
                      ? 'Loading earnings'
                      : 'Could not load earnings',
              message: binding.sessionEnded
                  ? 'Your session changed. Return to sign in.'
                  : binding.loading
                      ? 'Checking your completed jobs.'
                      : 'Check your connection and try again. No sample amounts are shown.',
              actionLabel:
                  binding.loading || binding.sessionEnded ? null : 'Retry',
              onAction: binding.refresh));
    }
    final summary = _report?.presentation ??
        earningsFor(
          widget.providerName,
          widget.bookings,
          providers: widget.providers,
        );
    final scoped = _connected ? summary : _scopedSummary(summary, _period);
    final sem = SemanticColors.of(context);

    if (!_connected && summary.jobsCompleted == 0) {
      return Scaffold(
        appBar: AppBar(title: const Text('Earnings')),
        body: const EmptyState(
          icon: Icons.payments_outlined,
          title: 'No earnings yet',
          subtitle: 'Complete a job to see your earnings here.',
        ),
      );
    }

    return Scaffold(
      bottomNavigationBar: widget.bottomNavigationBar,
      appBar: AppBar(
        title: const Text('Earnings'),
        actions: [
          if (binding != null)
            IconButton(
                onPressed: binding.refresh,
                tooltip: 'Refresh earnings',
                icon: const Icon(Icons.refresh)),
          if (!_connected)
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              tooltip: 'Export statement',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Export is unavailable.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (binding != null)
            SnapshotRefreshNotice(
                refreshing: binding.refreshing,
                failed: binding.refreshError != null,
                onRetry: binding.refresh),
          _buildPeriodFilter(),
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 14, color: sem.textSecondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _periodDateRange(scoped, DateTime.now()),
                  key: const ValueKey('earnings-period-range'),
                  style: TextStyle(color: sem.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildHero(context, scoped),
          if (_report case final report?) ...[
            const SizedBox(height: 8),
            Text(
                'Based on locked booking quotes and completion dates (MYT). '
                'Platform fees and payouts are not connected; this is not a payment confirmation.',
                style: TextStyle(color: sem.textSecondary, fontSize: 12)),
            if (report.unpriced > 0)
              Text(
                  '${report.unpriced} completed jobs have no saved quote. '
                  'Their amounts are excluded, not treated as free.',
                  style: TextStyle(color: sem.textSecondary)),
            if (report.undated > 0)
              Text(
                  '${report.undated} completed jobs have no completion date and are excluded from date totals.',
                  style: TextStyle(color: sem.textSecondary)),
            if (binding!.liveError != null) ...[
              const SizedBox(height: 8),
              const Text(
                  'Live updates interrupted. Figures may be out of date.'),
              TextButton(
                  onPressed: binding.retryLive, child: const Text('Reconnect')),
            ],
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('earnings-trend-toggle'),
              onPressed: () => setState(() => _showTrend = !_showTrend),
              icon: Icon(
                _showTrend ? Icons.expand_less : Icons.bar_chart_rounded,
                size: 18,
              ),
              label: Text(
                _showTrend ? 'Hide earnings trend' : 'View earnings trend',
              ),
            ),
          ),
          if (_showTrend) ...[
            const SizedBox(height: 10),
            _buildPeriodChart(context, scoped),
          ],
          const SizedBox(height: 18),
          SectionHeader(
            title: 'Earnings history',
            subtitle: scoped.records.isEmpty
                ? 'No jobs in this period'
                : _connected
                    ? 'Showing ${scoped.records.length} of ${scoped.jobsCompleted} completed jobs'
                    : 'Tap a job for the earnings breakdown',
          ),
          const SizedBox(height: 8),
          if (scoped.records.isEmpty)
            const _NoRecordsInPeriod()
          else
            ...scoped.records.map((r) => _EarningsTile(record: r)),
          if (binding?.moreError != null)
            const Text(
                'Could not load more jobs. Refresh if the report changed.'),
          if (_report?.next != null)
            OutlinedButton(
                key: const ValueKey('earnings-load-more'),
                onPressed: binding!.loadingMore ? null : binding.loadMore,
                child: Text(binding.loadingMore
                    ? 'Loading…'
                    : binding.moreError != null
                        ? 'Retry loading more'
                        : 'Load more jobs')),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context, EarningsSummary s) {
    final gross = s.records.fold<double>(0, (sum, r) => sum + r.gross);
    final fee = s.records.fold<double>(0, (sum, r) => sum + r.platformFee);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // E1: Theme gradient
        gradient: AppTheme.heroGradient(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: SemanticColors.of(context).shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.account_balance_wallet,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _connected ? 'Completed job value' : 'Net earnings',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _connected
                          ? 'Before fees · not confirmed paid'
                          : 'Calculated from completed jobs',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'RM ${(_report?.gross ?? s.totalNet).toStringAsFixed(_connected ? 2 : 0)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.task_alt, size: 14, color: Colors.white70),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _connected
                      ? '${s.jobsCompleted} completed ${s.jobsCompleted == 1 ? 'job' : 'jobs'}'
                      : s.jobsCompleted == 1
                          ? '1 completed job'
                          : '${s.jobsCompleted} completed jobs  ·  avg RM ${s.avgPerJob.toStringAsFixed(0)}/job',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  softWrap: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: Colors.white24),
          const SizedBox(height: 10),
          Text(
            _connected
                ? 'Platform fee —  ·  Net payout —'
                : 'Gross RM ${gross.toStringAsFixed(0)}  −  Platform fee RM ${fee.toStringAsFixed(0)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// Compact period filter that does not stretch across a wide screen.
  Widget _buildPeriodFilter() {
    final sem = SemanticColors.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return SingleChildScrollView(
      key: const ValueKey('earnings-period-filter'),
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final period in _EarningsPeriod.values) ...[
            ChoiceChip(
              label: Text(period.label),
              selected: _period == period,
              showCheckmark: false,
              onSelected: (_) {
                if (widget.binding case final binding?) {
                  binding.select(period);
                } else {
                  setState(() => _period = period);
                }
              },
              selectedColor: sem.primarySurface,
              backgroundColor: sem.surface,
              side: BorderSide(
                color: _period == period ? accent : sem.border,
              ),
              labelStyle: TextStyle(
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                color: _period == period ? accent : sem.textSecondary,
                fontWeight:
                    _period == period ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              ),
            ),
            if (period != _EarningsPeriod.values.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  List<_EarningsChartBucket> _chartBuckets(EarningsSummary s, DateTime now) {
    if (_report case final report?) {
      return report.buckets
          .map((b) => _EarningsChartBucket(
              label: DateFormat(report.unit == 'year'
                      ? 'yyyy'
                      : report.unit == 'month'
                          ? 'MMM yyyy'
                          : 'd MMM')
                  .format(b.start),
              range:
                  '${DateFormat('d MMM').format(b.start)}–${DateFormat('d MMM yyyy').format(b.end.subtract(const Duration(days: 1)))}',
              total: b.gross,
              jobCount: b.jobs,
              records: const []))
          .toList();
    }
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(today.year, today.month, today.day + 1);
    final buckets = <_EarningsChartBucket>[];
    DateTime start;
    if (_period == _EarningsPeriod.last30) {
      start = DateTime(today.year, today.month, today.day - 29);
    } else if (_period == _EarningsPeriod.thisMonth) {
      start = DateTime(today.year, today.month, 1);
    } else {
      final oldest = s.records.isEmpty
          ? today
          : s.records.map((r) => r.date).reduce(
                (a, b) => a.isBefore(b) ? a : b,
              );
      start = DateTime(oldest.year, oldest.month, 1);
    }

    while (start.isBefore(end)) {
      final next = _period == _EarningsPeriod.allTime
          ? DateTime(start.year, start.month + 1, 1)
          : _period == _EarningsPeriod.thisMonth
              ? DateTime(start.year, start.month, start.day + 8 - start.weekday)
              : DateTime(start.year, start.month, start.day + 7);
      final bucketEnd = next.isBefore(end) ? next : end;
      final records = s.records
          .where((r) => !r.date.isBefore(start) && r.date.isBefore(bucketEnd))
          .toList();
      final endDay =
          DateTime(bucketEnd.year, bucketEnd.month, bucketEnd.day - 1);
      final label = _period == _EarningsPeriod.allTime
          ? DateFormat('MMM yyyy').format(start)
          : DateFormat('d MMM').format(start);
      final range = _period == _EarningsPeriod.allTime
          ? DateFormat('MMMM yyyy').format(start)
          : '${DateFormat('d MMM').format(start)}–${DateFormat('d MMM yyyy').format(endDay)}';
      buckets.add(_EarningsChartBucket(
        label: label,
        range: range,
        total: records.fold<double>(0, (sum, r) => sum + r.net),
        jobCount: records.length,
        records: records,
      ));
      start = bucketEnd;
    }
    return buckets;
  }

  Widget _buildPeriodChart(BuildContext context, EarningsSummary s) {
    final buckets = _chartBuckets(s, DateTime.now());
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader(
            title: 'Earnings trend',
            subtitle: _connected
                ? 'Completed job value by ${_report!.unit == 'sevenDays' ? '7-day period' : _report!.unit} · before fees'
                : _period == _EarningsPeriod.allTime
                    ? 'Monthly net earnings'
                    : 'Weekly net earnings'),
        const SizedBox(height: 18),
        CompactEarningsChart(
          key: ValueKey('chart-${_period.name}'),
          points: buckets
              .map((b) =>
                  EarningsChartPoint(b.label, b.range, b.total, b.jobCount))
              .toList(),
          onDetails: _connected
              ? null
              : (index) => _showBucketDetails(context, buckets[index]),
        ),
      ]),
    ));
  }

  void _showBucketDetails(BuildContext context, _EarningsChartBucket bucket) {
    final sem = SemanticColors.of(context);
    final records = [...bucket.records]
      ..sort((a, b) => b.date.compareTo(a.date));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: sem.surface,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      bucket.range,
                      style: TextStyle(
                        color: sem.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close monthly details',
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${bucket.jobCount} completed ${bucket.jobCount == 1 ? 'job' : 'jobs'} · RM ${bucket.total.toStringAsFixed(2)} earned',
                style: TextStyle(color: sem.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 18),
              if (records.isEmpty)
                Text(
                  'No completed jobs in this period.',
                  style: TextStyle(color: sem.textSecondary),
                )
              else
                ...records.map(
                  (record) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: sem.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: sem.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  DateFormat('d MMM yyyy').format(record.date),
                                  style: TextStyle(
                                    color: sem.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${record.serviceLabel} · ${record.property}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: sem.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'RM ${record.net.toStringAsFixed(0)}',
                            style: TextStyle(
                              color: sem.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// E3: Theme-aware earnings tile with tap action + E6 fee %.
class _EarningsTile extends StatelessWidget {
  const _EarningsTile({required this.record});
  final EarningsRecord record;

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: ValueKey('earning-${record.bookingId}'),
        onTap: () {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            backgroundColor: sem.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (_) => _EarningsDetailsSheet(record: record),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: sem.primarySurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.cleaning_services,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.serviceLabel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: sem.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${record.property}  ·  ${record.hours.toStringAsFixed(1)} hours',
                          style: TextStyle(
                            fontSize: 11,
                            color: sem.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 18, color: sem.textTertiary),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: Text(
                    DateFormat('d MMM y').format(record.date),
                    style: TextStyle(fontSize: 11, color: sem.textTertiary),
                  )),
                  const SizedBox(width: 8),
                  Flexible(
                      child: Text(
                    !record.amountAvailable
                        ? 'Quote unavailable'
                        : !record.settlementAvailable
                            ? 'Value RM ${record.gross.toStringAsFixed(2)}'
                            : 'Net RM ${record.net.toStringAsFixed(0)}',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EarningsDetailsSheet extends StatelessWidget {
  const _EarningsDetailsSheet({required this.record});

  final EarningsRecord record;

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final feePercent =
        record.gross == 0 ? 0.0 : record.platformFee / record.gross * 100;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Earnings details',
                        style: TextStyle(
                          color: sem.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: 'Close details',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  record.serviceLabel,
                  style: TextStyle(
                    color: sem.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  record.property,
                  style: TextStyle(color: sem.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                _detailRow(
                    context,
                    record.settlementAvailable
                        ? 'Service date'
                        : 'Completed on (MYT)',
                    DateFormat('d MMM y, h:mm a').format(record.date)),
                const SizedBox(height: 10),
                _detailRow(context, 'Booked duration',
                    '${record.hours.toStringAsFixed(1)} hours'),
                const SizedBox(height: 10),
                _detailRow(
                    context, 'Booking ID', record.bookingId.toUpperCase()),
                const SizedBox(height: 16),
                Divider(color: sem.border),
                const SizedBox(height: 12),
                _detailRow(
                    context,
                    'Service amount',
                    record.amountAvailable
                        ? 'RM ${record.gross.toStringAsFixed(2)}'
                        : 'Quote unavailable'),
                const SizedBox(height: 12),
                _detailRow(
                  context,
                  record.settlementAvailable
                      ? 'Platform fee (${feePercent.toStringAsFixed(0)}%)'
                      : 'Platform fee',
                  record.settlementAvailable
                      ? '− RM ${record.platformFee.toStringAsFixed(2)}'
                      : 'Not available',
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: sem.primarySurface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          record.settlementAvailable
                              ? 'Calculated earnings'
                              : 'Net payout',
                          style: TextStyle(
                            color: sem.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        record.settlementAvailable
                            ? 'RM ${record.net.toStringAsFixed(2)}'
                            : '—',
                        style: TextStyle(
                          color: primary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  record.settlementAvailable
                      ? 'Calculated from the booked duration. This is not a payment confirmation.'
                      : 'Service amount is the locked booking quote, not today’s provider rate. '
                          'Fees and payments are not recorded yet; no payout is confirmed.',
                  style: TextStyle(
                    color: sem.textTertiary,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    final sem = SemanticColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: sem.textSecondary, fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: sem.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _EarningsChartBucket {
  const _EarningsChartBucket({
    required this.label,
    required this.range,
    required this.total,
    required this.jobCount,
    required this.records,
  });
  final String label;
  final String range;
  final double total;
  final int jobCount;
  final List<EarningsRecord> records;
}

/// Subtle inline empty state for the records list when a period has no jobs.
class _NoRecordsInPeriod extends StatelessWidget {
  const _NoRecordsInPeriod();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Icon(
              Icons.event_busy_outlined,
              size: 28,
              color: SemanticColors.of(context).textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No completed jobs in this period. '
                'Try a wider date range.',
                style: TextStyle(
                  fontSize: 12,
                  color: SemanticColors.of(context).textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
