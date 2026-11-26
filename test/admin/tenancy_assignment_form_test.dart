import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/features/admin/data/tenant_lifecycle_service.dart';
import 'package:smart_rental_management/features/admin/presentation/pages/admin_tenants_page.dart';

TenantRegistrationRecord registration({bool assigned = true}) =>
    TenantRegistrationRecord.fromMap({
      'registration_id': 'test-registration',
      'full_name': 'Example Tenant',
      'unit_id': assigned ? 'test-unit' : null,
    });

RegisteredTenancyUnit property() => RegisteredTenancyUnit({
  'unit_id': 'test-unit',
  'unit_number': '17/3B',
  'building_name': 'Example Residence',
  'bedrooms': 6,
  'occupancy': {
    'total': 0,
    'whole': 0,
    'rooms': [0, 0, 0, 0, 0, 0],
  },
});

void main() {
  testWidgets('single-room checkbox reveals every registered bedroom', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAssignTenantPage(
          record: registration(),
          loadUnits: (_, _) async => [property()],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final checkbox = find.byType(CheckboxListTile);
    await tester.scrollUntilVisible(
      checkbox,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(tester.element(checkbox), alignment: 0.3);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(find.text('Single-room tenancy'), findsOneWidget);
    final room = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<int> &&
          w.decoration.labelText == 'Select room',
    );
    await tester.scrollUntilVisible(
      room,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(room);
    await tester.pumpAndSettle();
    final lastRoom = find.text('Room 6 · 0/2 occupied').last;
    await tester.scrollUntilVisible(
      lastRoom,
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(lastRoom);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      checkbox,
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(tester.element(checkbox), alignment: 0.3);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(find.text('Whole-unit tenancy'), findsOneWidget);
    expect(find.text('Select room'), findsNothing);
  });

  testWidgets('missing building explains the failed save in red', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAssignTenantPage(
          record: registration(assigned: false),
          loadUnits: (_, _) async => [property()],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final save = find.text('Save tenancy assignment');
    await tester.scrollUntilVisible(
      save,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    final message = find.text('Select a building or apartment first.');
    expect(message, findsOneWidget);
    expect(tester.widget<Text>(message).style?.color, const Color(0xFFB42318));
    expect(tester.takeException(), isNull);
  });
}
