import 'package:smart_rental_management/owner_provider/services/backend/earnings_snapshot.dart';

const earningsActor = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
Map<String, dynamic> earningsFixture(
        {EarningsPeriod period = EarningsPeriod.thisMonth,
        int jobs = 24,
        int count = 20,
        int offset = 0,
        bool more = true,
        int unpriced = 0}) =>
    {
      'provider_id': earningsActor,
      'currency': 'MYR',
      'period': period.name,
      'as_of': '2026-10-23T12:00:00.123456+00:00',
      'start_day': '2026-10-01',
      'end_day': '2026-10-23',
      'jobs': jobs,
      'unpriced_jobs': unpriced,
      'undated_jobs': 0,
      'gross': jobs * 100.01,
      'bucket_unit': period == EarningsPeriod.allTime ? 'month' : 'week',
      'buckets': [
        {
          'bucket_start': '2026-10-01',
          'bucket_end': '2026-10-12',
          'jobs': jobs ~/ 2,
          'unpriced_jobs': 0,
          'gross': (jobs ~/ 2) * 100.01
        },
        {
          'bucket_start': '2026-10-12',
          'bucket_end': '2026-10-24',
          'jobs': jobs - jobs ~/ 2,
          'unpriced_jobs': unpriced,
          'gross': (jobs - jobs ~/ 2) * 100.01
        },
      ],
      'items': List<Map<String, dynamic>>.generate(
          count,
          (i) => {
                'booking_id':
                    'bbbbbbbb-bbbb-4bbb-8bbb-${(i + offset).toString().padLeft(12, '0')}',
                'completed_at': '2026-10-23T02:00:00.123456Z',
                'requested_start_at': '2026-10-21T02:00:00Z',
                'requested_end_at': '2026-10-21T04:00:00Z',
                'quoted_amount': 100.01,
                'quote_basis': 'hourly',
                'quoted_rate': 50.005,
                'quoted_duration_minutes': 120,
                'unit_name': 'Unit A-12',
                'building_name': 'Test Building',
                'service_name': 'Standard cleaning',
              }),
      'next_cursor': more
          ? {
              'timestamp': '2026-10-23T02:00:00.123456+00:00',
              'id':
                  'bbbbbbbb-bbbb-4bbb-8bbb-${(offset + count - 1).toString().padLeft(12, '0')}'
            }
          : null,
    };
EarningsSnapshot earningsReport(
        {EarningsPeriod period = EarningsPeriod.thisMonth,
        int jobs = 24,
        int count = 20,
        int offset = 0,
        bool more = true}) =>
    EarningsSnapshot.parse(
        earningsFixture(
            period: period,
            jobs: jobs,
            count: count,
            offset: offset,
            more: more),
        earningsActor,
        period);
