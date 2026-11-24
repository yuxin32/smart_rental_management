import 'package:flutter/material.dart';
import '../services/booking_reminder_controller.dart';
import 'settings_section_card.dart';

class BookingReminderSettings extends StatefulWidget {
  const BookingReminderSettings({super.key, required this.controller});
  final BookingReminderController controller;
  @override
  State<BookingReminderSettings> createState() =>
      _BookingReminderSettingsState();
}

class _BookingReminderSettingsState extends State<BookingReminderSettings> {
  bool _busy = false;
  String? _feedback;
  Future<void> _save({bool? enable, bool? dayBefore}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    final controller = widget.controller;
    final saved =
        await controller.save(enable: enable, oneDayBefore: dayBefore);
    if (saved && enable == true && !controller.permissionGranted)
      await controller.allowNotifications();
    if (mounted)
      setState(() {
        _busy = false;
        _feedback = !saved
            ? 'Changes not confirmed. Try again.'
            : controller.enabled && !controller.permissionGranted
                ? 'Enable notifications in Android Settings.'
                : null;
      });
  }

  Future<void> _allow() async {
    if (_busy) return;
    setState(() => _busy = true);
    final allowed = await widget.controller.allowNotifications();
    if (mounted)
      setState(() {
        _busy = false;
        _feedback =
            allowed ? null : 'Enable notifications in Android Settings.';
      });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        if (!controller.supported)
          return const SettingsSectionCard(
              title: 'Booking reminders',
              icon: Icons.notifications_active_outlined,
              children: [
                ListTile(
                    leading: Icon(Icons.notifications_outlined),
                    title: Text('Available in the Android app'))
              ]);
        return SettingsSectionCard(
            title: 'Booking reminders',
            icon: Icons.notifications_active_outlined,
            children: [
              if (controller.enabled && !controller.permissionGranted)
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.notifications_off_outlined),
                              title: Text('Notification permission needed')),
                          const SizedBox(height: 8),
                          OutlinedButton(
                              onPressed: _busy ? null : _allow,
                              child: const Text('Allow notifications')),
                        ])),
              SwitchListTile(
                  title: const Text('Cleaning reminders'),
                  subtitle: const Text('About 1 hour before'),
                  value: controller.enabled,
                  onChanged: _busy || !controller.ready
                      ? null
                      : (v) => _save(enable: v)),
              const Divider(height: 1),
              SwitchListTile(
                  title: const Text('Also 1 day before'),
                  value: controller.dayBefore,
                  onChanged: _busy || !controller.ready || !controller.enabled
                      ? null
                      : (v) => _save(dayBefore: v)),
              if (controller.failed || !controller.ready)
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Could not sync reminders')),
                          OutlinedButton(
                              onPressed: _busy ? null : controller.retry,
                              child: const Text('Retry'))
                        ])),
              if (_feedback != null)
                Padding(
                    padding: const EdgeInsets.all(12),
                    child:
                        Semantics(liveRegion: true, child: Text(_feedback!))),
              const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text('This device · next 31 days',
                      style: TextStyle(fontSize: 12))),
              if (controller.limited)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Reminders cover the next 100 bookings.',
                        style: TextStyle(fontSize: 12))),
            ]);
      });
}
