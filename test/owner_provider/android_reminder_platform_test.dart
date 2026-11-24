import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/services/android_booking_reminder_platform.dart';
import 'package:smart_rental_management/owner_provider/services/booking_reminder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  var notificationsAllowed = true, channelMuted = false;
  setUp(() {
    calls.clear();
    notificationsAllowed = true;
    channelMuted = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getNotificationAppLaunchDetails':
          return null;
        case 'areNotificationsEnabled':
          return notificationsAllowed;
        case 'requestNotificationsPermission':
          return notificationsAllowed;
        case 'pendingNotificationRequests':
          return <dynamic>[];
        case 'getNotificationChannels':
          return channelMuted
              ? [
                  {
                    'id': 'cleaning_reminders_v1',
                    'name': 'Cleaning reminders',
                    'importance': 0,
                    'playSound': false,
                    'enableVibration': false,
                    'showBadge': true,
                    'enableLights': false,
                    'ledColor': 0,
                    'audioAttributesUsage': 5
                  }
                ]
              : <dynamic>[];
        default:
          return null;
      }
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  test(
      'actual plugin receives UTC, inexact alarms, private content and the scoped payload',
      () async {
    final platform = AndroidBookingReminderPlatform();
    await platform.initialize((_) {});
    expect(await platform.allowed(), true);
    final now = DateTime.utc(2030, 1, 1);
    final plan = BookingReminderPlan.build(
            actorStamp: reminderDigest('staging:a'),
            bookings: [
              ReminderBooking('booking-a', now.add(const Duration(hours: 30)),
                  now.add(const Duration(hours: 32)), 'Accepted')
            ],
            now: now,
            dayBefore: false)
        .single;
    await platform.schedule(plan);
    final args = Map<String, dynamic>.from(
        calls.singleWhere((c) => c.method == 'zonedSchedule').arguments as Map);
    expect(args['timeZoneName'], 'UTC');
    expect(args['payload'], plan.payload);
    final specifics =
        Map<String, dynamic>.from(args['platformSpecifics'] as Map);
    expect(specifics['scheduleMode'], 'inexactAllowWhileIdle');
    expect(specifics['visibility'], 0);
    expect(args['body'], contains('2 Jan, 2:00 PM MYT'));
    expect(jsonEncode(args), isNot(contains('booking-a')));
    expect(calls.where((c) => c.method == 'requestExactAlarmsPermission'),
        isEmpty);
    expect(calls.where((c) => c.method == 'requestNotificationsPermission'),
        isEmpty);
  });
  test('both app-wide and channel-level notification blocks are respected',
      () async {
    final platform = AndroidBookingReminderPlatform();
    await platform.initialize((_) {});
    notificationsAllowed = false;
    expect(await platform.allowed(), false);
    notificationsAllowed = true;
    channelMuted = true;
    expect(await platform.allowed(), false);
    expect(await platform.requestPermission(), false);
  });
}
