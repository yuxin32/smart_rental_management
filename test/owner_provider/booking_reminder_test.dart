import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_rental_management/owner_provider/services/booking_reminder.dart';
import 'package:smart_rental_management/owner_provider/services/booking_reminder_controller.dart';
import 'package:smart_rental_management/owner_provider/services/backend/cursor_feed.dart';

class FakeReminderPhone implements BookingReminderPlatform {
  @override
  bool supported = true;
  bool permission = true;
  int requests = 0, schedules = 0;
  final plans = <int, BookingReminderPlan>{};
  final cancelled = <int>[];
  void Function(String?)? tap;
  @override
  Future<void> initialize(void Function(String?) onTap) async {
    tap = onTap;
  }

  @override
  Future<bool> allowed() async => permission;
  @override
  Future<bool> requestPermission() async {
    requests++;
    return permission;
  }

  @override
  Future<List<PendingBookingReminder>> pending() async =>
      plans.values.map((p) => PendingBookingReminder(p.id, p.payload)).toList();
  @override
  Future<void> schedule(BookingReminderPlan p) async {
    schedules++;
    plans[p.id] = p;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    plans.remove(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2030, 1, 1);
  ReminderBooking booking(
          {String id = 'job-a', String status = 'Accepted', int hours = 30}) =>
      ReminderBooking(id, now.add(Duration(hours: hours)),
          now.add(Duration(hours: hours + 2)), status);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a changed booking also removes its already displayed notification',
      () async {
    final phone = FakeReminderPhone();
    final changes = StreamController<PageChange>.broadcast();
    final controller = BookingReminderController(
        platform: phone,
        now: () => now,
        read: (_, __) async => [booking()],
        watch: (_) => changes.stream);
    addTearDown(() async {
      controller.dispose();
      await changes.close();
    });
    await controller.bindAccount('a', 'p');
    final id = phone.plans.values.single.id;
    phone.plans.clear();
    phone.cancelled.clear();
    changes.add(const PageChange(PageChangeKind.update, 'job-a'));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(phone.cancelled, contains(id));
  });

  test(
      'one-hour/day-before plans use real UTC instants and omit past/closed jobs',
      () {
    final plans = BookingReminderPlan.build(
        actorStamp: reminderDigest('project:actor-a'),
        bookings: [
          booking(),
          booking(id: 'pending', status: 'Pending'),
          booking(id: 'done', status: 'Completed'),
          booking(id: 'started', status: 'In Progress'),
          booking(id: 'cancelled', status: 'Cancelled')
        ],
        now: now,
        dayBefore: true);
    expect(plans.length, 2);
    expect(
        plans.map((p) => p.fireUtc),
        containsAll([
          now.add(const Duration(hours: 6)),
          now.add(const Duration(hours: 29))
        ]));
    expect(plans.map((p) => p.id).toSet().length, 2);
    expect(plans.first.payload, isNot(contains('job-a')));
    expect(plans.first.payload, isNot(contains('actor-a')));
    final soon = BookingReminderPlan.build(
        actorStamp: reminderDigest('a'),
        bookings: [booking(hours: 1)],
        now: now,
        dayBefore: true);
    expect(soon, isEmpty); // Never replay an elapsed reminder immediately.
  });
  test('reminder source rejects foreign identities and non-UTC timestamps', () {
    final row = {
      'booking_id': 'job',
      'provider_id': 'foreign',
      'current_status': 'Accepted',
      'requested_start_at': '2030-01-02T10:00:00Z',
      'requested_end_at': '2030-01-02T12:00:00Z'
    };
    expect(() => ReminderBooking.parse(row, 'mine'), throwsFormatException);
    row['provider_id'] = 'mine';
    row['requested_start_at'] = '2030-01-02T10:00:00';
    expect(() => ReminderBooking.parse(row, 'mine'), throwsFormatException);
  });
  test('permission is requested only from an explicit user action', () async {
    final phone = FakeReminderPhone()..permission = false;
    var reads = 0;
    final controller = BookingReminderController(
        platform: phone,
        now: () => now,
        read: (_, __) async {
          reads++;
          return [booking()];
        },
        watch: (_) => const Stream.empty());
    addTearDown(controller.dispose);
    await controller.bindAccount('a', 'p');
    expect(phone.requests, 0);
    expect(reads, 0);
    expect(phone.plans, isEmpty);
    expect(await controller.allowNotifications(), false);
    expect(phone.requests, 1);
    expect(reads, 0);
    phone.permission = true;
    expect(await controller.allowNotifications(), true);
    expect(phone.plans.length, 1);
  });
  test(
      'fresh sync replaces rescheduled jobs, removes terminal jobs, and is idempotent',
      () async {
    final phone = FakeReminderPhone();
    var records = [booking()];
    final controller = BookingReminderController(
        platform: phone,
        now: () => now,
        read: (_, __) async => records,
        watch: (_) => const Stream.empty());
    addTearDown(controller.dispose);
    await controller.bindAccount('a', 'p');
    expect(phone.plans.length, 1);
    final original = phone.plans.values.single;
    await controller.refresh();
    expect(phone.schedules, 1);
    records = [booking(hours: 40)];
    await controller.refresh();
    expect(
        phone.plans.values.single.fireUtc, now.add(const Duration(hours: 39)));
    expect(phone.plans.values.single.id, original.id);
    expect(phone.schedules, 2);
    records = [booking(status: 'Cancelled')];
    await controller.refresh();
    expect(phone.plans, isEmpty);
  });
  test(
      'preferences are scoped by account/project, and logout cancels pending alarms',
      () async {
    final phone = FakeReminderPhone();
    final controller = BookingReminderController(
        platform: phone,
        now: () => now,
        read: (_, __) async => [booking()],
        watch: (_) => const Stream.empty());
    addTearDown(controller.dispose);
    await controller.bindAccount('a', 'p');
    expect(await controller.save(oneDayBefore: true), true);
    expect(phone.plans.length, 2);
    expect(await controller.save(enable: false), true);
    expect(phone.plans, isEmpty);
    await controller.bindAccount('b', 'p');
    expect(controller.enabled, true);
    expect(controller.dayBefore, false);
    expect(phone.plans.length, 1);
    await controller.bindAccount('a', 'p');
    expect(controller.enabled, false);
    expect(controller.dayBefore, true);
    expect(phone.plans, isEmpty);
    await controller.bindAccount('a', 'different-project');
    expect(controller.enabled, true);
    await controller.bindAccount(null, 'different-project');
    expect(phone.plans, isEmpty);
  });
  test('ordinary controller disposal preserves confirmed device alarms',
      () async {
    final phone = FakeReminderPhone();
    final controller = BookingReminderController(
        platform: phone,
        now: () => now,
        read: (_, __) async => [booking()],
        watch: (_) => const Stream.empty());
    await controller.bindAccount('a', 'p');
    controller.dispose();
    expect(phone.plans.length, 1);
  });
  test(
      'an old account response cannot schedule after switching to another account',
      () async {
    final phone = FakeReminderPhone(), old = Completer<List<ReminderBooking>>();
    final controller = BookingReminderController(
        platform: phone,
        now: () => now,
        read: (actor, _) async =>
            actor == 'a' ? old.future : [booking(id: 'b')],
        watch: (_) => const Stream.empty());
    addTearDown(controller.dispose);
    final first = controller.bindAccount('a', 'p');
    await Future<void>.delayed(Duration.zero);
    await controller.bindAccount('b', 'p');
    old.complete([booking(id: 'a')]);
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(phone.plans.length, 1);
    final payload =
        BookingReminderPlan.readPayload(phone.plans.values.single.payload)!;
    expect(payload['actor'], reminderDigest('p:b'));
    expect(payload['booking'], reminderDigest('b'));
  });
  test(
      'tap opens the matching account calendar date in MYT, never another account',
      () async {
    final phone = FakeReminderPhone();
    final controller = BookingReminderController(
        platform: phone,
        now: () => now,
        read: (_, __) async => [booking(hours: 30)],
        watch: (_) => const Stream.empty());
    addTearDown(controller.dispose);
    await controller.bindAccount('a', 'p');
    phone.tap!(phone.plans.values.single.payload);
    expect(controller.takeOpenRequest(), DateTime.utc(2030, 1, 2));
    expect(controller.takeOpenRequest(), null);
    final payload = phone.plans.values.single.payload;
    await controller.bindAccount('b', 'p');
    phone.tap!(payload);
    expect(controller.takeOpenRequest(), null);
  });
  test('known booking changes cancel old alarms even if the next read fails',
      () async {
    final phone = FakeReminderPhone(),
        changes = StreamController<PageChange>.broadcast();
    var offline = false;
    final controller = BookingReminderController(
        platform: phone,
        now: () => now,
        read: (_, __) async {
          if (offline) throw StateError('offline');
          return [booking()];
        },
        watch: (_) => changes.stream);
    addTearDown(() async {
      controller.dispose();
      await changes.close();
    });
    await controller.bindAccount('a', 'p');
    expect(phone.plans.length, 1);
    offline = true;
    changes.add(const PageChange(PageChangeKind.update, 'job-a'));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(phone.plans, isEmpty);
    expect(controller.failed, true);
  });
  test(
      'scheduling is bounded to the nearest 100 bookings and indicates the cap',
      () async {
    final phone = FakeReminderPhone();
    final controller = BookingReminderController(
        platform: phone,
        now: () => now,
        read: (_, __) async =>
            List.generate(101, (i) => booking(id: 'job-$i', hours: 30 + i)),
        watch: (_) => const Stream.empty());
    addTearDown(controller.dispose);
    await controller.bindAccount('a', 'p');
    expect(controller.limited, true);
    expect(phone.plans.length, 100);
  });
}
