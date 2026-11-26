import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/features/admin/data/tenant_lifecycle_service.dart';
import 'package:smart_rental_management/features/communication/data/announcement_service.dart';
import 'package:smart_rental_management/features/tenant/presentation/pages/tenant_home_page.dart';
import 'package:smart_rental_management/features/tenant/presentation/pages/tenant_communication_page.dart';
import 'package:smart_rental_management/features/tenant/presentation/widgets/tenant_ui.dart';

void main() {
  testWidgets(
    'dashboard opens rental details directly without a tenancy popup',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const details = TenantRentalDetails(
        fullName: 'Example Tenant',
        email: 'test@example.invalid',
        contact_number: null,
        unitNumber: '17/3B',
        unitLocation: 'Example Residence',
        tenancyStatus: 'active',
        startDate: null,
        endDate: null,
        monthlyRentalAmount: 650,
        occupancyShare: 1,
        rentalType: 'room',
        roomNumber: 6,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TenantHomePage(loadDetails: () async => details),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Welcome,'), findsOneWidget);
      expect(find.text('Your tenancy'), findsNothing);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.text('Pay Now'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
      await tester.tap(find.text('View rental details'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Rental Details'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opening announcement persists read status and greys its card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final record = AnnouncementRecord(
      announcementId: 'notice',
      title: 'Water supply update',
      content: 'Maintenance has been completed.',
      audienceScope: 'all_tenants',
      audienceLabel: 'All tenants',
      status: 'published',
      publishedAt: DateTime(2026, 11, 27),
      expiresAt: null,
      createdAt: DateTime(2026, 11, 27),
    );
    DateTime? savedRead;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TenantAnnouncementsList(
            loadAnnouncements: () async => [
              savedRead == null ? record : record.withReadAt(savedRead!),
            ],
            markRead: (id) async {
              expect(id, 'notice');
              return savedRead = DateTime.utc(2026, 11, 27);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TenantCard>(find.byType(TenantCard)).color,
      Colors.white,
    );
    await tester.tap(find.text('View details'));
    await tester.pumpAndSettle();
    expect(savedRead, isNotNull);
    expect(tester.getSize(find.byType(BottomSheet)).width, 390);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Read · View details'), findsOneWidget);
    expect(
      tester.widget<TenantCard>(find.byType(TenantCard)).color,
      const Color(0xFFF1F3F6),
    );
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('Read · View details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
