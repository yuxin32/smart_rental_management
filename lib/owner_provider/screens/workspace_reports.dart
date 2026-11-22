import 'package:flutter/material.dart';
import '../models/demo_data.dart';
import '../services/backend/supabase_backend_provider.dart';
import '../services/backend/supabase_workspace_repository.dart';
import '../services/backend/earnings_snapshot.dart';
import '../services/user_session.dart';
import '../widgets/owned_workspace_page.dart';
import '../widgets/workspace_actions.dart';
import 'owner_spend_screen.dart';
import 'provider_stats_screen.dart';

class WorkspaceReports extends StatefulWidget {
  const WorkspaceReports(
      {super.key, required this.backend, required this.provider});
  final SupabaseBackendProvider backend;
  final bool provider;
  @override
  State<WorkspaceReports> createState() => _WorkspaceReportsState();
}

class _WorkspaceReportsState extends State<WorkspaceReports> {
  String period = 'allTime';
  @override
  Widget build(BuildContext context) {
    final repo = SupabaseWorkspaceRepository(widget.backend);
    return OwnedWorkspacePage(
        key: ValueKey(period),
        backend: widget.backend,
        title: widget.provider ? 'My stats' : 'Spending',
        cacheKey: widget.provider
            ? 'provider:stats:v1'
            : 'owner:spending:$period:${DateTime.now().toUtc().add(const Duration(hours: 8)).toIso8601String().substring(0, 10)}',
        load: ({before, asOf}) async {
          final row = await repo.read(
              widget.provider ? 'my_provider_statistics' : 'owner_spending',
              params: widget.provider
                  ? null
                  : {
                      'p_period': period,
                      'p_before_at': before?.timestamp,
                      'p_before_id': before?.id,
                      'p_as_of': asOf
                    });
          validateWorkspaceReport(row,
              provider: widget.provider, period: period);
          return row;
        },
        builder: (context, binding) {
          final row = binding.snapshot!;
          if (widget.provider)
            return ProviderStatsScreen(
                snapshot: row,
                onRefresh: binding.refresh,
                notice: ownedPageFooter(binding));
          return OwnerSpendScreen(
              bookings: const [],
              connectedSummary: ownerSpendSummary(row),
              periodLabel: const {
                'allTime': 'All time',
                'last30': 'Last 30 days',
                'thisMonth': 'This month'
              }[period]!,
              onSelectPeriod: (v) => setState(() => period = v),
              onRefresh: binding.refresh,
              footer: ownedPageFooter(binding),
              unpriced: row['unpriced'] as int,
              undated: row['undated'] as int,
              onOpenBooking: (id) =>
                  WorkspaceActions(widget.backend, UserRole.owner)
                      .booking(context, id));
        });
  }
}

void validateWorkspaceReport(Map<String, dynamic> row,
    {required bool provider, required String period}) {
  earningsWallTime(row['as_of'] as String);
  if (provider) {
    for (final key in [
      'total',
      'accepted',
      'completed',
      'closed_other',
      'decisions',
      'accepted_decisions',
      'repeat_jobs',
      'undated_completions'
    ]) {
      if (row[key] is! int || (row[key] as int) < 0)
        throw const FormatException('Invalid metric');
    }
    final total = row['total'] as int;
    if ((row['accepted'] as int) > total ||
        (row['completed'] as int) > total ||
        (row['accepted_decisions'] as int) > (row['decisions'] as int) ||
        (row['repeat_jobs'] as num) > (row['completed'] as int) ||
        row['response_minutes'] != null && (row['response_minutes'] as num) < 0)
      throw const FormatException('Inconsistent metrics');
    final weeks = List<Map<String, dynamic>>.from(row['weeks'] as List);
    if (weeks.length != 8 ||
        weeks.any((w) => w['jobs'] is! int || (w['jobs'] as int) < 0))
      throw const FormatException('Invalid weeks');
    for (final e in (row['ratings'] as Map).entries) {
      final rating = int.tryParse(e.key as String);
      if (rating == null ||
          rating < 1 ||
          rating > 5 ||
          e.value is! int ||
          (e.value as int) < 0) throw const FormatException('Invalid reviews');
    }
  } else {
    if (row['period'] != period || row['currency'] != 'MYR')
      throw const FormatException('Wrong report range');
    ownerSpendSummary(row);
  }
}

SpendSummary ownerSpendSummary(Map<String, dynamic> row) {
  final jobs = row['jobs'] as int, unpriced = row['unpriced'] as int;
  if (jobs < 0 ||
      unpriced < 0 ||
      unpriced > jobs ||
      (row['undated'] as int) < 0)
    throw const FormatException('Invalid spending counts');
  final gross = EarningsSnapshot.amount(row['gross']);
  final records = List<Map<String, dynamic>>.from(row['items'] as List)
      .map((r) => SpendRecord(
          bookingId: r['booking_id'] as String,
          date: earningsWallTime(r['completed_at'] as String),
          cost: r['quoted_amount'] == null
              ? 0
              : EarningsSnapshot.amount(r['quoted_amount']),
          amountAvailable: r['quoted_amount'] != null,
          serviceLabel: r['service_name'] as String,
          property: '${r['unit_name']}, ${r['building_name']}',
          providerName: r['provider_name'] as String))
      .toList();
  if (records.length > jobs)
    throw const FormatException('Invalid spending page');
  final providers = List<Map<String, dynamic>>.from(row['providers'] as List);
  if (providers.length > 10)
    throw const FormatException('Oversized provider report');
  return SpendSummary(
      totalSpent: gross,
      thisMonth: EarningsSnapshot.amount(row['this_month']),
      lastMonth: EarningsSnapshot.amount(row['last_month']),
      jobsFunded: jobs,
      avgPerJob: jobs == unpriced ? 0 : gross / (jobs - unpriced),
      records: records,
      byProvider: providers
          .map((p) => MapEntry(p['provider_name'] as String,
              EarningsSnapshot.amount(p['gross'])))
          .toList());
}
