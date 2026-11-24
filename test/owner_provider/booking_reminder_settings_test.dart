import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_rental_management/owner_provider/screens/account_settings_screens.dart';
import 'package:smart_rental_management/owner_provider/services/device_preferences.dart';
import 'package:smart_rental_management/owner_provider/services/booking_reminder.dart';
import 'package:smart_rental_management/owner_provider/services/booking_reminder_controller.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';
import 'booking_reminder_test.dart' show FakeReminderPhone;

class _FailingPreferences extends DevicePreferences {
  bool reject = false;
  @override
  Future<bool> save({required bool booking, required bool enabled}) async =>
      reject ? false : super.save(booking: booking, enabled: enabled);
}

void main() {
  testWidgets('indicators save immediately and failed saves remain visible',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = _FailingPreferences();
    await prefs.bindAccount('owner');
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: NotificationSettingsScreen(
          preferences: prefs, openNotifications: () => opened++),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Booking updates'));
    await tester.pumpAndSettle();
    expect(prefs.bookingIndicators, false);
    expect(
        (await SharedPreferences.getInstance())
            .getBool('ui:owner:bookingIndicators'),
        false);
    expect(find.text('Saved'), findsNothing);
    prefs.reject = true;
    await tester.tap(find.widgetWithText(SwitchListTile, 'Messages'));
    await tester.pumpAndSettle();
    expect(prefs.messageIndicators, true);
    expect(find.text('Could not save. Try again.'), findsOneWidget);
    await tester.tap(find.text('View booking updates'));
    expect(opened, 1);
    await tester.pumpWidget(const SizedBox());
    prefs.dispose();
  });

  testWidgets('permission prompt follows intent and denial never schedules',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = DevicePreferences();
    await prefs.bindAccount('provider');
    final phone = FakeReminderPhone()..permission = false;
    final now = DateTime.utc(2030, 1, 1);
    final controller = BookingReminderController(
        platform: phone,
        now: () => now,
        read: (_, __) async => [
              ReminderBooking('job', now.add(const Duration(hours: 30)),
                  now.add(const Duration(hours: 32)), 'Accepted'),
            ],
        watch: (_) => const Stream.empty());
    await controller.bindAccount('provider', 'staging');
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: NotificationSettingsScreen(
            preferences: prefs,
            reminders: controller,
            openNotifications: () {})));
    await tester.pumpAndSettle();
    expect(phone.requests, 0);
    expect(find.text('Notification permission needed'), findsOneWidget);
    final master = find.widgetWithText(SwitchListTile, 'Cleaning reminders');
    final dayBefore = find.widgetWithText(SwitchListTile, 'Also 1 day before');
    await tester.tap(master);
    await tester.pumpAndSettle();
    expect(controller.enabled, false);
    expect(find.text('Allow notifications'), findsNothing);
    expect(tester.widget<SwitchListTile>(dayBefore).onChanged, isNull);
    expect(phone.plans, isEmpty);
    await tester.tap(master);
    await tester.pumpAndSettle();
    expect(phone.requests, 1);
    expect(controller.permissionGranted, false);
    expect(find.text('Notification permission needed'), findsOneWidget);
    expect(
        find.text('Enable notifications in Android Settings.'), findsOneWidget);
    expect(phone.plans, isEmpty);
    phone.permission = true;
    await tester.tap(find.text('Allow notifications'));
    await tester.pumpAndSettle();
    expect(phone.requests, 2);
    expect(phone.plans.length, 1);
    expect(find.text('Notification permission needed'), findsNothing);
    expect(
        find.text('Enable notifications in Android Settings.'), findsNothing);
    await tester.tap(dayBefore);
    await tester.pumpAndSettle();
    expect(phone.plans.length, 2);
    await tester.tap(master);
    await tester.pumpAndSettle();
    expect(phone.plans, isEmpty);
    expect(prefs.bookingIndicators, true);
    expect(prefs.messageIndicators, true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    prefs.dispose();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'Provider reminder permission and preferences fit 320px at ${scale}x text',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefs = DevicePreferences();
      await prefs.bindAccount('provider');
      final phone = FakeReminderPhone()..permission = false;
      final now = DateTime.utc(2030, 1, 1);
      final controller = BookingReminderController(
          platform: phone,
          now: () => now,
          read: (_, __) async => [
                ReminderBooking('job', now.add(const Duration(hours: 30)),
                    now.add(const Duration(hours: 32)), 'Accepted')
              ],
          watch: (_) => const Stream.empty());
      await controller.bindAccount('provider', 'staging');
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: NotificationSettingsScreen(
              preferences: prefs,
              reminders: controller,
              openNotifications: () {})));
      await tester.pumpAndSettle();
      expect(phone.requests, 0);
      await tester.scrollUntilVisible(find.text('Allow notifications'), 220,
          scrollable: find.byType(Scrollable).first);
      phone.permission = true;
      await tester.ensureVisible(find.text('Allow notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow notifications'));
      await tester.pumpAndSettle();
      expect(phone.requests, 1);
      expect(phone.plans.length, 1);
      final dayBefore =
          find.widgetWithText(SwitchListTile, 'Also 1 day before');
      await tester.ensureVisible(dayBefore);
      await tester.pumpAndSettle();
      await tester.tap(dayBefore);
      await tester.pumpAndSettle();
      expect(phone.plans.length, 2);
      final enabled = find.widgetWithText(SwitchListTile, 'Cleaning reminders');
      await tester.ensureVisible(enabled);
      await tester.pumpAndSettle();
      await tester.tap(enabled);
      await tester.pumpAndSettle();
      expect(phone.plans, isEmpty);
      expect(prefs.bookingIndicators, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      prefs.dispose();
    });
  }
}
