import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/main.dart';
import 'package:smart_rental_management/owner_provider/screens/provider_edit_profile_screen.dart';
import 'package:smart_rental_management/owner_provider/services/booking_store.dart';
import 'package:smart_rental_management/owner_provider/services/message_store.dart';
import 'package:smart_rental_management/owner_provider/services/property_store.dart';
import 'package:smart_rental_management/owner_provider/services/provider_store.dart';
import 'package:smart_rental_management/owner_provider/services/review_store.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';

void main() {
  testWidgets('edit profile is readable on a narrow phone and save reacts',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final providers = ProviderStore();
    final properties = PropertyStore();
    final bookings = BookingStore(
      providerStore: providers,
      propertyStore: properties,
    );
    final provider = providers.byId('p-a')!;

    await tester.pumpWidget(AppProviders(
      themeMode: ThemeMode.light,
      onToggleTheme: () {},
      bookingStore: bookings,
      providerStore: providers,
      propertyStore: properties,
      reviewStore: ReviewStore(),
      messageStore: MessageStore(),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: ProviderEditProfileScreen(provider: provider),
      ),
    ));
    await tester.pumpAndSettle();

    final saveButton =
        find.byWidgetPredicate((widget) => widget is FilledButton);
    expect(find.text('About you'), findsOneWidget);
    final sectionColors = [
      'About you',
      'Services & rate',
      'Working hours',
      'Contact & privacy',
    ]
        .map((title) => tester
            .widget<Container>(
              find.byKey(ValueKey('profile-section-header-$title')),
            )
            .color)
        .toList();
    expect(sectionColors.toSet(), {AppColors.primaryBorder});
    expect(
      tester.widget<FilledButton>(saveButton).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);

    await tester.enterText(
        find.byType(TextFormField).first, 'Updated Provider');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(saveButton).onPressed,
      isNotNull,
    );

    await tester.scrollUntilVisible(
      find.text('Contact & privacy'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Contact & privacy'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(saveButton);
    await tester.pump(const Duration(milliseconds: 500));
    expect(providers.byId('p-a')!.name, 'Updated Provider');
  });

  testWidgets('dark edit profile keeps appearance controls optional',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final providers = ProviderStore();
    final properties = PropertyStore();
    final bookings = BookingStore(
      providerStore: providers,
      propertyStore: properties,
    );

    await tester.pumpWidget(AppProviders(
      themeMode: ThemeMode.dark,
      onToggleTheme: () {},
      bookingStore: bookings,
      providerStore: providers,
      propertyStore: properties,
      reviewStore: ReviewStore(),
      messageStore: MessageStore(),
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: ProviderEditProfileScreen(provider: providers.byId('p-a')!),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('PUBLIC PROFILE'), findsOneWidget);
    expect(
      tester
          .widget<Container>(
            find.byKey(const ValueKey('profile-section-header-About you')),
          )
          .color,
      AppColors.primarySurfaceDark,
    );
    expect(find.text('Choose an avatar color'), findsNothing);
    await tester.tap(find.text('Customize'));
    await tester.pumpAndSettle();
    expect(find.text('Choose an avatar color'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
