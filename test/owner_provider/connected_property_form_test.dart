import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/screens/connected_property_form_screen.dart';
import 'support/owner_uat_steps.dart';

void main() {
  testWidgets('requires complete property details before saving',
      (tester) async {
    var saved = false;
    await tester.pumpWidget(MaterialApp(
      home: ConnectedPropertyFormScreen(
        onSave: (_) async => saved = true,
      ),
    ));

    await tester.tap(find.text('Add property'));
    await tester.pump();

    expect(saved, isFalse);
    expect(find.text('Apartment unit (e.g. A-12-05) is required'), findsOneWidget);
    expect(find.text('Building or tower is required'), findsOneWidget);
  });

  testWidgets('passes validated details and 24-hour times to persistence',
      (tester) async {
    ConnectedPropertyInput? saved;
    await tester.pumpWidget(MaterialApp(
      home: ConnectedPropertyFormScreen(
        onSave: (input) async => saved = input,
      ),
    ));

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'A-12');
    await tester.enterText(fields.at(1), 'Menara Suria');
    await tester.enterText(fields.at(2), 'Jalan Example, Kuala Lumpur');
    await chooseBedrooms(tester, 3);
    await tester.ensureVisible(fields.last);
    await tester.enterText(fields.last, '980');
    await selectPropertyWindow(tester);
    await tester.ensureVisible(find.text('Add property'));
    await tester.tap(find.text('Add property'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.unitName, 'A-12');
    expect(saved!.buildingName, 'Menara Suria');
    expect(saved!.bedrooms, 3);
    expect(saved!.sizeSqft, 980);
    expect(saved!.cleaningWindowStart, '08:00');
    expect(saved!.cleaningWindowEnd, '18:00');
  });

  testWidgets('uncertain property save keeps fields and blocks duplicate tap',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
      home: ConnectedPropertyFormScreen(
        onSave: (_) async {
          attempts++;
          throw StateError('response lost');
        },
      ),
    ));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'A-12');
    await tester.enterText(fields.at(1), 'Menara Suria');
    await tester.enterText(fields.at(2), 'Jalan Example');
    await chooseBedrooms(tester, 3);
    await tester.ensureVisible(fields.last);
    await tester.enterText(fields.last, '980');
    await selectPropertyWindow(tester);
    await tester.ensureVisible(find.text('Add property'));
    await tester.tap(find.text('Add property'));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.text('Add property'), findsNothing);
    expect(find.text('Check My properties'), findsOneWidget);
    expect(tester.widget<TextFormField>(fields.at(0)).controller!.text, 'A-12');
    expect(find.textContaining('response lost'), findsNothing);
  });
}
