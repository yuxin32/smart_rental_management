import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> chooseTimeSlot(WidgetTester tester, int minute) async {
  final part = minute >= 1080
      ? 2
      : minute >= 720
          ? 1
          : minute >= 360
              ? 0
              : 3;
  final partChip = find.byKey(ValueKey('time-part-$part'));
  if (partChip.evaluate().isNotEmpty) {
    await tester.ensureVisible(partChip);
    await tester.tap(partChip);
    await tester.pumpAndSettle();
  }
  final slot = find.byKey(ValueKey('time-slot-$minute'));
  if (slot.evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('time-slot-precision')));
    await tester.pumpAndSettle();
    final hour = find.byKey(ValueKey('time-hour-${minute ~/ 60}'));
    await tester.ensureVisible(hour);
    await tester.tap(hour);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(slot);
  await tester.tap(slot);
  await tester.pumpAndSettle();
}
