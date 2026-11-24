import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_rental_management/owner_provider/features/availability/domain/provider_setup.dart';
import 'package:smart_rental_management/owner_provider/widgets/provider_weekly_hours_editor.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';
import 'support/weekly_hours_fixture.dart';

String slotId(int n) =>
    'dddddddd-dddd-4ddd-8ddd-${n.toString().padLeft(12, '0')}';

class _Week {
  ProviderWeeklyState state = weeklyHoursFixture(slots: [
    ProviderWeeklySlotItem(
        id: slotId(1), weekday: 1, startMinute: 480, endMinute: 720),
    ProviderWeeklySlotItem(
        id: slotId(2), weekday: 1, startMinute: 840, endMinute: 1080),
    ProviderWeeklySlotItem(
        id: slotId(3), weekday: 2, startMinute: 1080, endMinute: 1320),
    ProviderWeeklySlotItem(
        id: slotId(4), weekday: 5, startMinute: 480, endMinute: 1080),
  ], required: const [
    ProviderRequiredInterval(1, 600, 720, 1),
    ProviderRequiredInterval(2, 1200, 1320, 1)
  ]);
  int reads = 0, saves = 0, nextId = 10;
  bool lostResponse = false, conflict = false;
  Completer<ProviderWeeklyState>? pendingRead;
  Map<int, List<ProviderWorkingRange>>? changed;
  String? expected;
  Future<ProviderWeeklyState> read() async {
    reads++;
    return pendingRead?.future ?? Future.value(state);
  }

  Future<ProviderWeeklyState> save(Map<int, List<ProviderWorkingRange>> days,
      ProviderWeeklyState base) async {
    saves++;
    changed = days;
    expected = base.revision;
    if (conflict)
      throw const PostgrestException(message: 'changed', code: 'PT409');
    final slots = [
      for (final slot in state.slots)
        if (!days.containsKey(slot.weekday)) slot,
      for (final entry in days.entries)
        for (final range in entry.value)
          ProviderWeeklySlotItem(
              id: slotId(nextId++),
              weekday: entry.key,
              startMinute: range.start,
              endMinute: range.end),
    ]..sort((a, b) => a.weekday != b.weekday
        ? a.weekday.compareTo(b.weekday)
        : a.startMinute.compareTo(b.startMinute));
    state = ProviderWeeklyState(
        providerId: base.providerId,
        revision: saves.toRadixString(16).padLeft(32, '0'),
        slots: slots,
        required: base.required,
        requiredServices: base.requiredServices);
    if (lostResponse) throw StateError('response lost');
    return state;
  }

  ProviderSetupData get data => ProviderSetupData(
      services: const [],
      selectedServiceIds: const {},
      slots: state.slots,
      unavailableDates: const {},
      weeklyState: state);
}

Future<void> mount(WidgetTester tester, _Week week,
    {bool dark = false, double scale = 1}) async {
  await tester.pumpWidget(MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(
          body: SingleChildScrollView(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ProviderWeeklyHoursEditor(
                      data: week.data,
                      enabled: true,
                      loadFresh: week.read,
                      save: week.save,
                      onSaved: () {},
                      onBusyChanged: (_) {}))))));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> editFirst(WidgetTester tester) async {
  await tap(tester, find.byTooltip('Edit time slot').first);
  await tap(tester, find.byKey(const ValueKey('working-start')));
  expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('time-slot-630')))
          .onPressed,
      isNull);
  await tap(tester, find.byKey(const ValueKey('time-slot-540')));
}

void main() {
  test('whole confirmed intervals, minimum duration and touching boundaries',
      () {
    final state = weeklyHoursFixture(
        required: const [ProviderRequiredInterval(1, 600, 720, 1)]);
    expect(
        state.validateDay(1, const [
          ProviderWorkingRange(480, 600),
          ProviderWorkingRange(600, 720)
        ]),
        isNull);
    expect(state.validateDay(1, const []), contains('10:00–12:00'));
    expect(state.validateDay(1, const [ProviderWorkingRange(600, 660)]),
        contains('at least 2 hours'));
    expect(
        state.validateDay(1, const [
          ProviderWorkingRange(480, 720),
          ProviderWorkingRange(660, 840)
        ]),
        contains('overlap'));
    final crossing = weeklyHoursFixture(
        required: const [ProviderRequiredInterval(1, 540, 660, 1)]);
    expect(
        crossing.validateDay(1, const [
          ProviderWorkingRange(480, 600),
          ProviderWorkingRange(600, 720)
        ]),
        contains('confirmed job'));
  });
  test('parser refuses another actor, missing fields and duplicate slot IDs',
      () {
    final row = <String, dynamic>{
      'provider_id': 'actor',
      'revision': '0' * 32,
      'slots': <Map<String, dynamic>>[],
      'required_intervals': <Map<String, dynamic>>[],
      'required_service_ids': <String>[]
    };
    expect(ProviderWeeklyState.parse(row, 'actor').slots, isEmpty);
    expect(
        () => ProviderWeeklyState.parse(row, 'other'), throwsFormatException);
    expect(
        () => ProviderWeeklyState.parse(
            {...row, 'required_intervals': null}, 'actor'),
        throwsFormatException);
    final slot = {
      'slot_id': slotId(1),
      'weekday': 1,
      'start_minute': 480,
      'end_minute': 600
    };
    expect(
        () => ProviderWeeklyState.parse({
              ...row,
              'slots': [slot, slot]
            }, 'actor'),
        throwsFormatException);
    expect(
        () => ProviderWeeklyState.parse({
              ...row,
              'required_intervals': [
                {
                  'weekday': 1,
                  'start_minute': 720,
                  'end_minute': 600,
                  'booking_count': 1
                }
              ]
            }, 'actor'),
        throwsFormatException);
  });
  testWidgets(
      'selecting weekdays changes only the visible day without a backend read',
      (tester) async {
    final week = _Week();
    await mount(tester, week);
    expect(find.text('08:00 – 12:00'), findsOneWidget);
    expect(find.text('18:00 – 22:00'), findsNothing);
    await tap(tester, find.byKey(const ValueKey('working-weekday-2')));
    expect(find.text('18:00 – 22:00'), findsOneWidget);
    expect(find.text('08:00 – 12:00'), findsNothing);
    expect(week.reads, 0);
    expect(week.saves, 0);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
  });
  testWidgets('edit disables conflicts and sends one revision-protected update',
      (tester) async {
    final week = _Week();
    await mount(tester, week);
    final revision = week.state.revision;
    await editFirst(tester);
    await tap(tester, find.text('Save hours'));
    expect(week.reads, 1);
    expect(week.saves, 1);
    expect(week.expected, revision);
    expect(week.changed!.keys, [1]);
    expect(week.changed![1]!.map((range) => range.start),
        unorderedEquals([540, 840]));
    expect(find.text('09:00 – 12:00'), findsOneWidget);
    expect(find.text('Working hours saved.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('time slot opens only through its edit control', (tester) async {
    final week = _Week();
    await mount(tester, week);
    await tester.tap(find.text('08:00 – 12:00'));
    await tester.pumpAndSettle();
    expect(week.reads, 0);
    expect(find.byType(AlertDialog), findsNothing);
    await tap(tester, find.byTooltip('Edit time slot').first);
    expect(week.reads, 1);
    expect(week.saves, 0);
    expect(find.text('Save hours'), findsOneWidget);
  });
  testWidgets(
      'copy disables incompatible targets and confirms multiple days in one call',
      (tester) async {
    final week = _Week();
    await mount(tester, week);
    await tap(tester, find.text('Copy'));
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('copy-weekday-2')))
            .onChanged,
        isNull);
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('copy-weekday-1')))
            .onChanged,
        isNull);
    await tap(tester, find.byKey(const ValueKey('copy-weekday-3')));
    await tap(tester, find.byKey(const ValueKey('copy-weekday-4')));
    expect(week.saves, 0);
    await tap(tester, find.text('Copy to 2 days'));
    expect(week.saves, 1);
    expect(week.changed!.keys, unorderedEquals([3, 4]));
    expect(week.changed![3]!.length, 2);
    expect(week.changed![4]!.length, 2);
    expect(find.text('Working hours copied to 2 days.'), findsOneWidget);
  });
  testWidgets('enable an empty weekday; turning it off requires confirmation',
      (tester) async {
    final week = _Week();
    await mount(tester, week);
    await tap(tester, find.byKey(const ValueKey('working-weekday-3')));
    await tap(tester, find.byType(Switch));
    await tap(tester, find.text('Save hours'));
    expect(week.state.rangesFor(3).single.start, 480);
    await tap(tester, find.byType(Switch));
    await tap(tester, find.text('Cancel'));
    expect(week.saves, 1);
    await tap(tester, find.byType(Switch));
    await tap(tester, find.text('Set not working'));
    expect(week.saves, 2);
    expect(week.state.rangesFor(3), isEmpty);
    expect(find.text('Not working on this weekday.'), findsOneWidget);
  });
  testWidgets('protected removal is disabled; an allowed removal is confirmed',
      (tester) async {
    final week = _Week();
    await mount(tester, week);
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate((widget) =>
                widget is IconButton &&
                widget.tooltip == 'Required by confirmed jobs'))
            .onPressed,
        isNull);
    await tap(tester, find.byTooltip('Remove time slot'));
    expect(week.saves, 0);
    await tap(tester, find.text('Remove'));
    expect(week.saves, 1);
    expect(week.state.rangesFor(1).length, 1);
  });
  testWidgets('fresh preflight catches a newly confirmed job before removal',
      (tester) async {
    final week = _Week();
    week.state = ProviderWeeklyState(
        providerId: week.state.providerId,
        revision: week.state.revision,
        slots: week.state.slots,
        required: const [],
        requiredServices: const {});
    await mount(tester, week);
    week.state = ProviderWeeklyState(
        providerId: week.state.providerId,
        revision: week.state.revision,
        slots: week.state.slots,
        required: const [ProviderRequiredInterval(1, 600, 720, 1)],
        requiredServices: const {});
    await tap(tester, find.byTooltip('Remove time slot').first);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Keep 10:00–12:00 available for a confirmed job.'),
        findsOneWidget);
    expect(week.saves, 0);
  });
  testWidgets(
      'lost acknowledgement reads back the result without retrying the write',
      (tester) async {
    final week = _Week()..lostResponse = true;
    await mount(tester, week);
    await editFirst(tester);
    await tap(tester, find.text('Save hours'));
    expect(week.saves, 1);
    expect(find.text('Check saved hours'), findsOneWidget);
    await tap(tester, find.text('Check saved hours'));
    expect(week.saves, 1);
    expect(week.reads, 2);
    expect(find.text('Your saved hours match this change.'), findsOneWidget);
    expect(find.text('09:00 – 12:00'), findsOneWidget);
  });
  testWidgets(
      'a server conflict blocks writes until the latest state is checked',
      (tester) async {
    final week = _Week()..conflict = true;
    await mount(tester, week);
    await editFirst(tester);
    await tap(tester, find.text('Save hours'));
    expect(week.saves, 1);
    expect(find.text('Check saved hours'), findsOneWidget);
    await tap(tester, find.text('Check saved hours'));
    expect(week.saves, 1);
    expect(
        find.text(
            'Saved hours checked. Review them before making another change.'),
        findsOneWidget);
  });
  testWidgets('failed preflight never opens an editor or sends a write',
      (tester) async {
    final week = _Week();
    await mount(tester, week);
    week.pendingRead = Completer<ProviderWeeklyState>();
    await tester.tap(find.byTooltip('Edit time slot').first);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    week.pendingRead!.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(week.saves, 0);
    expect(find.text('Check saved hours'), findsOneWidget);
  });
  for (final dark in [false, true]) {
    testWidgets('320px and 200% text: ' + (dark ? 'dark' : 'light'),
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final week = _Week();
      await mount(tester, week, dark: dark, scale: 2);
      await tap(tester, find.byTooltip('Edit time slot').first);
      expect(tester.takeException(), isNull);
      await tap(tester, find.text('Cancel'));
      await tap(tester, find.text('Copy'));
      expect(tester.takeException(), isNull);
      await tap(tester, find.text('Cancel'));
    });
  }
}
