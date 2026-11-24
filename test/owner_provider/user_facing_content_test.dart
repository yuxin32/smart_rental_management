import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/content/prototype_legal_drafts.dart';
import 'package:smart_rental_management/owner_provider/models/demo_data.dart';
import 'package:smart_rental_management/owner_provider/presentation/workspace_text.dart';
import 'package:smart_rental_management/owner_provider/screens/about_screen.dart';
import 'package:smart_rental_management/owner_provider/screens/connected_property_form_screen.dart';
import 'package:smart_rental_management/owner_provider/screens/connected_pending_edit_screen.dart';
import 'package:smart_rental_management/owner_provider/services/backend/supabase_booking_repository.dart';
import 'package:smart_rental_management/owner_provider/services/prototype_support_store.dart';
import 'support/owner_uat_steps.dart';

void main() {
  test(
      'only imported dataset annotations are formatted, ordinary messages remain exact',
      () {
    expect(workspaceText('[UAT] Maple Residence'), 'Maple Residence');
    expect(workspaceText('[UAT] A-101, [UAT] Maple Residence'),
        'A-101, Maple Residence');
    expect(
        workspaceText(
            '[UAT] Please focus on the kitchen and living area. This is a test request.'),
        'Please focus on the kitchen and living area.');
    expect(
        workspaceText(
            '[UAT] Understood. I will confirm the agreed scope before starting. Test reply only.'),
        'Understood. I will confirm the agreed scope before starting.');
    expect(
        workspaceText(
            '[UAT] Synthetic scenario 1: Completed. Test data only; no real cleaning or payment.'),
        isEmpty);
    expect(workspaceText('Please test the kitchen tap.'),
        'Please test the kitchen tap.');
    expect(workspaceText('Test Heights, Tower A'), 'Test Heights, Tower A');
    expect(workspaceText('owner@rental-test.invalid'),
        'owner@rental-test.invalid');
    expect(workspaceText('Latest update'), 'Latest update');
  });

  test(
      'user information removes development copy without claiming published policies or payments',
      () {
    for (final kind in LegalDraftKind.values) {
      final copy = PrototypeLegalDraft.forKind(kind).copyText;
      expect(
          RegExp(r'\b(test|testing|staging|prototype|demo|simulated|simulation|UAT)\b',
                  caseSensitive: false)
              .hasMatch(copy),
          isFalse);
      expect(copy, contains('DRAFT — NOT PUBLISHED'));
    }
    expect(PrototypeLegalDraft.terms.copyText, contains('not money received'));
    expect(PrototypeLegalDraft.privacy.copyText,
        contains('not end-to-end encrypted'));
  });

  testWidgets(
      'normal About contains guides, no environment badge or simulated support route',
      (tester) async {
    final store = PrototypeSupportStore(enabled: true)..bindSession('account');
    await tester.pumpWidget(MaterialApp(
        home:
            AboutScreen(environmentLabel: 'staging', prototypeSupport: store)));
    expect(find.text('Staging environment'), findsNothing);
    expect(find.text('Contact support'), findsNothing);
    await tester.tap(find.text('Account & troubleshooting'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Does signing out delete my data?'));
    await tester.pumpAndSettle();
    final text =
        tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(
        RegExp(r'\b(test|staging|prototype|demo|simulated)\b',
                caseSensitive: false)
            .hasMatch(text),
        isFalse);
    expect(text, contains('Your saved records remain in your account.'));
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets(
      'formatting existing property fields never silently renames stored records on save',
      (tester) async {
    ConnectedPropertyInput? saved;
    const initial = DemoProperty(
        id: 'p',
        unit: '[UAT] A-101',
        tower: '[UAT] Maple Residence',
        address:
            '[UAT] Fictional rental address, Kuala Lumpur. No real resident or access code.',
        bedrooms: 2,
        sizeSqft: 800,
        cleaningWindowStart: TimeOfDay(hour: 8, minute: 0),
        cleaningWindowEnd: TimeOfDay(hour: 18, minute: 0));
    await tester.pumpWidget(MaterialApp(
        home: ConnectedPropertyFormScreen(
            initial: initial, onSave: (value) async => saved = value)));
    final unit = find.widgetWithText(TextFormField, 'Apartment unit (e.g. A-12-05)');
    expect(tester.widget<TextFormField>(unit).controller!.text, 'A-101');
    expect(find.textContaining('[UAT]'), findsNothing);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(saved!.unitName, initial.unit);
    expect(saved!.buildingName, initial.tower);
    expect(saved!.address, initial.address);
  });

  testWidgets(
      'a new unit reuses the original building key rather than creating a duplicate display-name group',
      (tester) async {
    ConnectedPropertyInput? saved;
    var loads = 0;
    await tester.pumpWidget(MaterialApp(
        home: ConnectedPropertyFormScreen(
            loadBuildingOptions: () async {
              loads++;
              return [
                {
                  'building_name': '[UAT] Maple Residence',
                  'address': 'Kuala Lumpur'
                }
              ];
            },
            onSave: (value) async => saved = value)));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Apartment unit (e.g. A-12-05)'), 'A-202');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Building or tower'),
        'Maple Residence');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Property address'), 'Kuala Lumpur');
    await chooseBedrooms(tester, 2);
    final size = find.widgetWithText(TextFormField, 'Size (sqft)');
    await tester.ensureVisible(size);
    await tester.enterText(size, '800');
    await selectPropertyWindow(tester);
    await tester.tap(find.text('Add property'));
    await tester.pumpAndSettle();
    expect(saved!.unitName, 'A-202');
    expect(saved!.buildingName, '[UAT] Maple Residence');
    expect(loads, 1);
  });

  testWidgets(
      'revision display keeps imported notes hidden while unchanged save preserves original notes',
      (tester) async {
    const raw =
        '[UAT] Synthetic scenario 1: Pending. Test data only; no real cleaning or payment.';
    String? notes;
    await tester.pumpWidget(MaterialApp(
        home: ConnectedPendingEditScreen(
            row: const {
          'requested_start_at': '2027-10-28T02:00:00Z',
          'requested_end_at': '2027-10-28T04:00:00Z',
          'instructions': raw
        },
            canSave: () => true,
            save: (start, end, value) async {
              notes = value;
              return const AcceptanceOutcome(
                  accepted: false, reason: 'availability');
            })));
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        isEmpty);
    await tester.scrollUntilVisible(find.text('Save request changes'), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save request changes'));
    await tester.pumpAndSettle();
    expect(notes, raw);
  });
}
