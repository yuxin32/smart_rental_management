import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/widgets/connected_workspace_components.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';

void main() {
  for (final provider in [false, true]) {
    testWidgets(
        'package booking displays saved crew, total and scope provider=$provider',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: ConnectedBookingCard(
                      row: {
                'booking_id': 'booking',
                'current_status': 'Accepted',
                'requested_start_at': '2027-01-01T01:00:00Z',
                'requested_end_at': '2027-01-01T04:00:00Z',
                'service_name': 'Standard cleaning',
                'quote_basis': 'package',
                'quoted_amount': 135.5,
                'cleaner_count': 2,
                'duration_minutes': 180,
                'package_scope': 'Saved floors and bathroom scope'
              },
                      propertyName: 'Lakeview C-301',
                      isProvider: provider,
                      busy: false,
                      onAction: (_) {},
                      onHistory: () {},
                      onMessages: () {},
                      onEvidence: () {},
                      onReview: () {},
                      onCancel: () {})))));
      await tester.pumpAndSettle();
      expect(find.text('Package total · RM 135.50'), findsOneWidget);
      expect(find.text('2 cleaners · 3 hours'), findsOneWidget);
      await tester.tap(find.text('Included cleaning'));
      await tester.pumpAndSettle();
      expect(find.text('Saved floors and bathroom scope'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
