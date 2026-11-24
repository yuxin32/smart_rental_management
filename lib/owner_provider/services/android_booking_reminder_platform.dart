import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'booking_reminder.dart';

/// Android-only local reminders. No Firebase, exact-alarm access or GPS.
class AndroidBookingReminderPlatform implements BookingReminderPlatform {
  final _plugin = FlutterLocalNotificationsPlugin();
  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  @override
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  Future<void> initialize(void Function(String?) onTap) async {
    if (!supported) return;
    final ok = await _plugin.initialize(
        const InitializationSettings(
            android: AndroidInitializationSettings('ic_booking_reminder')),
        onDidReceiveNotificationResponse: (response) =>
            onTap(response.payload));
    if (ok != true) throw StateError('Notification setup unavailable.');
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      onTap(launch?.notificationResponse?.payload);
    }
  }

  @override
  Future<bool> allowed() async {
    if (await _android?.areNotificationsEnabled() != true) return false;
    final channels = await _android?.getNotificationChannels();
    final channel =
        channels?.where((c) => c.id == 'cleaning_reminders_v1').firstOrNull;
    return channel?.importance != Importance.none;
  }

  @override
  Future<bool> requestPermission() async {
    await _android?.requestNotificationsPermission();
    return allowed();
  }

  @override
  Future<List<PendingBookingReminder>> pending() async =>
      (await _plugin.pendingNotificationRequests())
          .map((row) => PendingBookingReminder(row.id, row.payload))
          .toList();
  @override
  Future<void> cancel(int id) => _plugin.cancel(id);
  @override
  Future<void> schedule(BookingReminderPlan plan) async {
    final wall = plan.startUtc.add(const Duration(hours: 8));
    final time = DateFormat('d MMM, h:mm a').format(wall);
    await _plugin.zonedSchedule(
        plan.id,
        'Cleaning reminder',
        'Cleaning is scheduled for $time MYT. Open Schedule to check the latest details.',
        tz.TZDateTime.from(plan.fireUtc, tz.UTC),
        const NotificationDetails(
            android: AndroidNotificationDetails(
                'cleaning_reminders_v1', 'Cleaning reminders',
                channelDescription: 'Reminders for accepted cleaning bookings',
                importance: Importance.high,
                priority: Priority.high,
                visibility: NotificationVisibility.private,
                icon: 'ic_booking_reminder',
                category: AndroidNotificationCategory.reminder)),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: plan.payload);
  }
}
