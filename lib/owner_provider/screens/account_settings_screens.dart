import 'package:flutter/material.dart';
import '../services/device_preferences.dart';
import '../services/booking_reminder_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/booking_reminder_settings.dart';
import '../widgets/settings_section_card.dart';

export 'appearance_settings_screen.dart';

class SettingsSection extends StatelessWidget {
  const SettingsSection(
      {super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12)),
              child: Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color:
                          Theme.of(context).colorScheme.onPrimaryContainer))),
          const SizedBox(height: 8),
          Card(margin: EdgeInsets.zero, child: Column(children: children)),
        ]),
      );
}

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen(
      {super.key,
      required this.preferences,
      required this.openNotifications,
      this.reminders});
  final DevicePreferences preferences;
  final VoidCallback openNotifications;
  final BookingReminderController? reminders;
  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsState();
}

class _NotificationSettingsState extends State<NotificationSettingsScreen> {
  bool saving = false;
  String? feedback;
  bool failed = false;
  Future<void> _save(bool booking, bool value) async {
    setState(() {
      saving = true;
      feedback = null;
    });
    final ok = await widget.preferences.save(booking: booking, enabled: value);
    if (mounted)
      setState(() {
        saving = false;
        failed = !ok;
        feedback = ok ? null : 'Could not save. Try again.';
      });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.preferences,
      builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('Notifications')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            SettingsSectionCard(
                title: 'In-app indicators',
                icon: Icons.mark_chat_unread_outlined,
                children: [
                  const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text('Unread markers inside the app',
                          style: TextStyle(fontSize: 12))),
                  SwitchListTile(
                      secondary:
                          const Icon(Icons.event_note_outlined, size: 20),
                      title: const Text('Booking updates'),
                      value: widget.preferences.bookingIndicators,
                      onChanged: saving || !widget.preferences.ready
                          ? null
                          : (v) => _save(true, v)),
                  const Divider(height: 1),
                  SwitchListTile(
                      secondary:
                          const Icon(Icons.chat_bubble_outline, size: 20),
                      title: const Text('Messages'),
                      value: widget.preferences.messageIndicators,
                      onChanged: saving || !widget.preferences.ready
                          ? null
                          : (v) => _save(false, v)),
                ]),
            if (feedback != null && failed)
              Semantics(
                  liveRegion: true,
                  child: Text(feedback!,
                      style: TextStyle(
                          color: failed
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary))),
            if (widget.reminders != null)
              BookingReminderSettings(controller: widget.reminders!),
            Card(
                child: ListTile(
                    onTap: widget.openNotifications,
                    leading: const Icon(Icons.inbox_outlined),
                    title: const Text('View booking updates'),
                    trailing: const Icon(Icons.chevron_right))),
          ])));
}

class PrivacySecurityScreen extends StatelessWidget {
  const PrivacySecurityScreen({
    super.key,
    required this.email,
    required this.role,
    required this.onSignOut,
  });

  final String email;
  final String role;
  final Future<void> Function() onSignOut;

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: const Text('Reset your password?'),
        content: const Text(
          'After signing out, choose Forgot password on the sign-in screen. '
          'You’ll need access to your email.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Stay signed in'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Sign out to reset'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) await onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColors.of(context);
    final theme = Theme.of(context);
    final signInEmail = email.trim();
    final recoveryAvailable = signInEmail.isNotEmpty &&
        !signInEmail.toLowerCase().endsWith('.invalid');
    final divider =
        Divider(height: 1, indent: 16, endIndent: 16, color: colors.border);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & security')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SettingsSectionCard(
                title: 'Account security',
                icon: Icons.lock_outline,
                children: [
                  ListTile(
                    leading: const Icon(Icons.email_outlined, size: 20),
                    title: const Text('Sign-in email'),
                    subtitle: signInEmail.isEmpty
                        ? const Text('No email on file')
                        : SelectableText(signInEmail),
                  ),
                  divider,
                  ListTile(
                    leading: const Icon(Icons.badge_outlined, size: 20),
                    title: const Text('Account role'),
                    subtitle: Text(role),
                  ),
                  divider,
                  ListTile(
                    leading: Icon(
                      Icons.lock_reset,
                      size: 20,
                      color:
                          recoveryAvailable ? theme.colorScheme.primary : null,
                    ),
                    title: const Text('Reset password'),
                    subtitle: Text(
                      recoveryAvailable
                          ? 'Sign out to reset by email'
                          : 'Email recovery unavailable for this address',
                    ),
                    trailing: recoveryAvailable
                        ? const Icon(Icons.chevron_right)
                        : null,
                    onTap:
                        recoveryAvailable ? () => _confirmReset(context) : null,
                  ),
                ],
              ),
              SettingsSectionCard(
                title: 'Data & privacy',
                icon: Icons.shield_outlined,
                children: [
                  const ListTile(
                    leading: Icon(Icons.photo_library_outlined, size: 20),
                    title: Text('Bookings, photos & messages'),
                    subtitle: Text('Shared with the people on the booking.'),
                  ),
                  if (role == 'Cleaning Service Provider') ...[
                    divider,
                    const ListTile(
                      leading: Icon(Icons.phone_outlined, size: 20),
                      title: Text('Phone number sharing'),
                      subtitle: Text(
                        'Choose in Edit profile whether Owners can see your number.',
                      ),
                    ),
                  ],
                  divider,
                  const ListTile(
                    leading: Icon(Icons.logout, size: 20),
                    title: Text('Signing out'),
                    subtitle:
                        Text('Your bookings, photos and messages stay saved.'),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'In-app data export and account deletion are currently unavailable.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
