import 'package:flutter_test/flutter_test.dart';

import 'package:smart_rental_management/main.dart';

void main() {
  testWidgets('Role selection opens separate login interfaces', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SmartRentalApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome to'), findsOneWidget);
    expect(find.text('Smart Rental Management'), findsOneWidget);
    expect(find.text('Tenant Login'), findsOneWidget);
    expect(find.text('Administrator Login'), findsOneWidget);

    await tester.tap(find.text('Tenant Login').first);
    await tester.pumpAndSettle();

    expect(find.text('Tenant Login'), findsOneWidget);
    expect(find.text('Sign in as tenant'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to role selection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Administrator Login').first);
    await tester.pumpAndSettle();

    expect(find.text('Administrator Login'), findsOneWidget);
    expect(find.text('Sign in as administrator'), findsOneWidget);
  });
}
