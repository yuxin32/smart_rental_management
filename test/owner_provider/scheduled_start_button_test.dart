import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/widgets/scheduled_start_button.dart';
import 'package:smart_rental_management/owner_provider/widgets/connected_workspace_components.dart';
import 'package:smart_rental_management/owner_provider/services/backend/connected_failure_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final start = DateTime.utc(2030, 1, 2, 2); // 10 AM MYT.
  for (final offset in [
    const Duration(days: -1),
    const Duration(seconds: -1),
    Duration.zero,
    const Duration(minutes: 1)
  ]) {
    testWidgets('agreed instant boundary $offset', (tester) async {
      var calls = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ScheduledStartButton(
                  start: start,
                  busy: false,
                  now: () => start.add(offset),
                  onStart: () => calls++))));
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      if (offset.isNegative) {
        expect(button.onPressed, isNull);
        expect(find.textContaining('2 Jan 2030 · 10:00 AM'), findsOneWidget);
      } else {
        expect(button.onPressed, isNotNull);
        await tester.tap(find.text('Start cleaning'));
        expect(calls, 1);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
      'button becomes available at the boundary and rechecks clock on tap',
      (tester) async {
    var now = start.subtract(const Duration(seconds: 1)), calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ScheduledStartButton(
                start: start,
                busy: false,
                now: () => now,
                onStart: () => calls++))));
    now = start;
    await tester.pump(const Duration(milliseconds: 1002));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    now = start.subtract(const Duration(hours: 1));
    await tester.tap(find.text('Start cleaning'));
    await tester.pump();
    expect(calls, 0);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('missing schedule fails closed and busy blocks duplicate start',
      (tester) async {
    for (final missing in [true, false]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ScheduledStartButton(
                  start: missing ? null : start,
                  busy: !missing,
                  now: () => start,
                  onStart: () => fail('started')))));
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
    }
  });
  testWidgets('connected accepted card exposes a disabled scheduled start',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: ConnectedBookingCard(
                    row: {
          'current_status': 'Accepted',
          'requested_start_at': start.toIso8601String()
        },
                    isProvider: true,
                    busy: false,
                    now: () => start.subtract(const Duration(days: 1)),
                    onAction: (_) => fail('started'),
                    onHistory: () {},
                    onMessages: () {},
                    onEvidence: () {},
                    onReview: () {},
                    onCancel: () {})))));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Start cleaning'))
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('due booking opens Before evidence instead of starting directly',
      (tester) async {
    var evidenceOpens = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ConnectedBookingCard(
            row: {'current_status': 'Accepted',
              'requested_start_at': start.toIso8601String()},
            isProvider: true,
            busy: false,
            now: () => start,
            onAction: (_) => fail('Status changed before Before photo'),
            onHistory: () {},
            onMessages: () {},
            onEvidence: () => evidenceOpens++,
            onReview: () {},
            onCancel: () {},
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Start cleaning'));
    expect(evidenceOpens, 1);
  });

  test('server refusal has fixed guidance without exposing its payload', () {
    expect(
        ConnectedFailureMessage.forWrite(
            const PostgrestException(
                code: 'PT409',
                message: 'private',
                details: 'booking_start_not_reached'),
            item: 'booking'),
        contains('scheduled start time has not been reached'));
  });
}

