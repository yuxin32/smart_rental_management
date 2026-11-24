import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'time_slot_steps.dart';

Future<void> advanceRegistration(WidgetTester tester) async {
  final name = find.byKey(const Key('registration-name'));
  await tester.ensureVisible(name);
  await tester.enterText(name, 'Synthetic User');
  final email = find.widgetWithText(TextFormField, 'name@example.com');
  await tester.ensureVisible(email);
  await tester.enterText(email, 'synthetic@rental-test.invalid');
  final password = find.widgetWithText(TextFormField, 'Password');
  await tester.ensureVisible(password);
  await tester.enterText(password, 'SyntheticPassword123!');
  final next = find.widgetWithText(FilledButton, 'Continue');
  await tester.ensureVisible(next);
  await tester.tap(next);
  await tester.pumpAndSettle();
}

Future<void> selectPropertyWindow(WidgetTester tester) async {
  for (final field in ['window-start', 'window-end']) {
    final key = find.byKey(ValueKey(field));
    await tester.ensureVisible(key);
    await tester
        .tap(find.descendant(of: key, matching: find.byType(InkWell)).first);
    await tester.pumpAndSettle();
    await chooseTimeSlot(tester, field == 'window-start' ? 480 : 1080);
  }
}

Future<void> chooseBedrooms(WidgetTester tester, int count) async {
  final dropdown = find.byKey(const Key('property-bedrooms'));
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  final label = count <= 6
      ? '$count ${count == 1 ? 'bedroom' : 'bedrooms'}'
      : 'Other (7–100)';
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
  if (count > 6) {
    final input = find.byKey(const Key('property-bedrooms-other'));
    await tester.ensureVisible(input);
    await tester.enterText(input, '$count');
  }
}
