import '../../presentation/workspace_text.dart';
import '../../models/demo_data.dart';
import 'cursor_feed.dart';

enum EarningsPeriod {
  last30('Last 30 days'),
  thisMonth('This month'),
  allTime('All time');

  const EarningsPeriod(this.label);
  final String label;
  DateTime? earliest(DateTime now) => switch (this) {
        EarningsPeriod.last30 => DateTime(now.year, now.month, now.day - 29),
        EarningsPeriod.thisMonth => DateTime(now.year, now.month, 1),
        EarningsPeriod.allTime => null,
      };
}

DateTime earningsWallTime(String raw) {
  if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(raw)) {
    throw const FormatException('Offset required.');
  }
  final t = DateTime.parse(raw).toUtc().add(const Duration(hours: 8));
  return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second,
      t.millisecond, t.microsecond);
}

class EarningsBucket {
  const EarningsBucket(
      this.start, this.end, this.jobs, this.unpriced, this.gross);
  final DateTime start, end;
  final int jobs, unpriced;
  final double gross;
}

/// Server aggregates cover the WHOLE range; records are only one bounded page.
/// The legacy presentation class is never filled from preview stores.
class EarningsSnapshot {
  EarningsSnapshot(
      {required this.period,
      required this.asOf,
      required this.start,
      required this.end,
      required this.jobs,
      required this.unpriced,
      required this.undated,
      required this.gross,
      required this.buckets,
      required this.records,
      required this.unit,
      this.next});
  final EarningsPeriod period;
  final String asOf, unit;
  final DateTime start, end;
  final int jobs, unpriced, undated;
  final double gross;
  final List<EarningsBucket> buckets;
  final List<EarningsRecord> records;
  final PageCursor? next;

  static double amount(dynamic n) {
    final value = (n as num).toDouble();
    if (!value.isFinite || value < 0)
      throw const FormatException('Invalid amount.');
    return value;
  }

  factory EarningsSnapshot.parse(
      Map<String, dynamic> row, String provider, EarningsPeriod period) {
    if (row['provider_id'] != provider ||
        row['currency'] != 'MYR' ||
        row['period'] != period.name) {
      throw const FormatException('Unexpected earnings identity.');
    }
    earningsWallTime(row['as_of'] as String);
    final items = List<Map<String, dynamic>>.from(row['items'] as List);
    if (items.length > 20)
      throw const FormatException('Oversized earnings page.');
    final records = items.map((r) {
      final known = r['quoted_amount'] != null;
      final gross = known ? amount(r['quoted_amount']) : 0.0;
      final duration = DateTime.parse(r['requested_end_at'] as String)
          .difference(DateTime.parse(r['requested_start_at'] as String));
      if (duration <= Duration.zero)
        throw const FormatException('Invalid duration.');
      return EarningsRecord(
          bookingId: r['booking_id'] as String,
          date: earningsWallTime(r['completed_at'] as String),
          hours: duration.inMinutes / 60,
          gross: gross,
          platformFee: 0,
          // Unavailable settlement fields are never shown as actual values.
          net: 0,
          serviceLabel: r['service_name'] as String,
          property: [r['unit_name'], r['building_name']]
              .whereType<String>()
              .map(workspaceText)
              .join(', '),
          amountAvailable: known,
          settlementAvailable: false);
    }).toList();
    final cursor = row['next_cursor'] as Map?;
    final buckets = (row['buckets'] as List)
        .map((dynamic b) => EarningsBucket(
            DateTime.parse(b['bucket_start'] as String),
            DateTime.parse(b['bucket_end'] as String),
            b['jobs'] as int,
            b['unpriced_jobs'] as int,
            amount(b['gross'])))
        .toList();
    final jobs = row['jobs'] as int, unpriced = row['unpriced_jobs'] as int;
    final gross = amount(row['gross']);
    if (jobs < 0 ||
        unpriced < 0 ||
        unpriced > jobs ||
        records.length > jobs ||
        buckets.fold<int>(0, (s, b) => s + b.jobs) != jobs ||
        (buckets.fold<double>(0, (s, b) => s + b.gross) - gross).abs() >
            0.005) {
      throw const FormatException('Inconsistent earnings totals.');
    }
    return EarningsSnapshot(
        period: period,
        asOf: row['as_of'] as String,
        start: DateTime.parse(row['start_day'] as String),
        end: DateTime.parse(row['end_day'] as String),
        jobs: jobs,
        unpriced: unpriced,
        undated: row['undated_jobs'] as int,
        gross: gross,
        unit: row['bucket_unit'] as String,
        buckets: buckets,
        records: records,
        next: cursor == null
            ? null
            : PageCursor(
                cursor['timestamp'] as String, cursor['id'] as String));
  }

  EarningsSummary get presentation => EarningsSummary(
      providerName: '',
      totalNet: 0,
      weeklyNet: 0,
      monthlyNet: 0,
      jobsCompleted: jobs,
      avgPerJob: 0,
      records: records);

  EarningsSnapshot append(EarningsSnapshot page) {
    if (page.period != period ||
        page.asOf != asOf ||
        page.jobs != jobs ||
        page.gross != gross ||
        page.unpriced != unpriced ||
        page.undated != undated ||
        page.records
            .any((r) => records.any((old) => old.bookingId == r.bookingId))) {
      throw const FormatException(
          'Report changed. Refresh before loading more.');
    }
    return EarningsSnapshot(
        period: period,
        asOf: asOf,
        start: start,
        end: end,
        jobs: jobs,
        unpriced: unpriced,
        undated: undated,
        gross: gross,
        unit: unit,
        buckets: buckets,
        records: [...records, ...page.records],
        next: page.next);
  }
}
