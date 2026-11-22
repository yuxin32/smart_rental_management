import 'package:flutter/material.dart';
import '../main.dart';
import '../services/device_preferences.dart';

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

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});
  @override
  State<AppearanceSettingsScreen> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettingsScreen> {
  String? error;
  bool saving = false;
  @override
  Widget build(BuildContext context) {
    final app = AppProviders.of(context);
    return Scaffold(
        appBar: AppBar(title: const Text('Appearance')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Make it comfortable to read',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
              'Choose a theme for this device. System follows your phone’s appearance.'),
          const SizedBox(height: 24),
          SettingsSection(title: 'Theme', children: [
            for (final mode in ThemeMode.values)
              RadioListTile<ThemeMode>(
                  value: mode,
                  groupValue: app.themeMode,
                  title: Text(switch (mode) {
                    ThemeMode.system => 'System',
                    ThemeMode.light => 'Light',
                    ThemeMode.dark => 'Dark'
                  }),
                  subtitle: Text(mode == ThemeMode.system
                      ? 'Follow device settings'
                      : mode == ThemeMode.light
                          ? 'Bright surfaces and navy accents'
                          : 'Deep surfaces and soft blue accents'),
                  secondary: Icon(mode == ThemeMode.system
                      ? Icons.brightness_auto_outlined
                      : mode == ThemeMode.light
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined),
                  onChanged: saving || app.onSetThemeMode == null
                      ? null
                      : (value) async {
                          setState(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            await app.onSetThemeMode!(value!);
                          } catch (_) {
                            if (mounted)
                              setState(() => error =
                                  'Theme applied for now, but could not be saved on this device. Try again.');
                          } finally {
                            if (mounted) setState(() => saving = false);
                          }
                        }),
          ]),
          const Text('Preview', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Your next cleaning',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        const Text(
                            'Clear details, readable text and familiar controls.'),
                        const SizedBox(height: 14),
                        FilledButton(
                            onPressed: () {},
                            child: const Text('Preview button')),
                      ]))),
          if (error != null)
            Text(error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]));
  }
}

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen(
      {super.key, required this.preferences, required this.openNotifications});
  final DevicePreferences preferences;
  final VoidCallback openNotifications;
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
        feedback = ok
            ? 'Saved on this device'
            : 'Could not save. Your previous preference is kept. Try again.';
      });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.preferences,
      builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('Notifications')),
          body: ListView(padding: const EdgeInsets.all(20), children: [
            const Text('Stay informed your way',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
                'These preferences control unread indicators for your account on this device. Updates and conversations remain available when indicators are off.'),
            const SizedBox(height: 24),
            SettingsSection(title: 'Inside the app', children: [
              SwitchListTile(
                  title: const Text('Booking updates'),
                  subtitle: const Text(
                      'Highlight unread booking updates in Notifications.'),
                  value: widget.preferences.bookingIndicators,
                  onChanged: saving || !widget.preferences.ready
                      ? null
                      : (v) => _save(true, v)),
              const Divider(height: 1),
              SwitchListTile(
                  title: const Text('Messages'),
                  subtitle: const Text(
                      'Show the unread message badge. Conversations are kept.'),
                  value: widget.preferences.messageIndicators,
                  onChanged: saving || !widget.preferences.ready
                      ? null
                      : (v) => _save(false, v)),
            ]),
            if (feedback != null)
              Semantics(
                  liveRegion: true,
                  child: Text(feedback!,
                      style: TextStyle(
                          color: failed
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary))),
            const SizedBox(height: 16),
            SettingsSection(title: 'Phone notifications', children: const [
              ListTile(
                  leading: Icon(Icons.notifications_off_outlined),
                  title: Text('Push notifications are not enabled'),
                  subtitle: Text(
                      'This build does not send alerts while the app is closed. These switches do not grant Android notification permission.')),
            ]),
            OutlinedButton.icon(
                onPressed: widget.openNotifications,
                icon: const Icon(Icons.inbox_outlined),
                label: const Text('View booking updates')),
          ])));
}

class PrivacySecurityScreen extends StatelessWidget {
  const PrivacySecurityScreen(
      {super.key,
      required this.email,
      required this.role,
      required this.onSignOut});
  final String email, role;
  final Future<void> Function() onSignOut;
  Future<void> _reset(BuildContext context) async {
    final proceed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Reset your password?'),
                content: const Text(
                    'For account security, sign out first, then choose Forgot password on the sign-in screen. You will need access to your account email. No email is sent by opening this page.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Stay signed in')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Sign out to reset'))
                ]));
    if (proceed == true && context.mounted) await onSignOut();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Privacy & security')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('You’re in control of your account',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        SettingsSection(title: 'Account access', children: [
          ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Sign-in email'),
              subtitle: SelectableText(email)),
          ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Account role'),
              subtitle: Text(role)),
          ListTile(
              leading: const Icon(Icons.lock_reset),
              title: const Text('Reset password'),
              subtitle: Text(email.endsWith('.invalid')
                  ? 'Recovery email is unavailable for this address.'
                  : 'Secure email recovery after signing out'),
              trailing: email.endsWith('.invalid')
                  ? null
                  : const Icon(Icons.chevron_right),
              onTap: email.endsWith('.invalid') ? null : () => _reset(context)),
        ]),
        const SettingsSection(title: 'Your information', children: [
          ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text('Booking, photo and message access'),
              subtitle: Text(
                  'Booking records and conversations are restricted to the participants. Providers control whether their phone number is shared with Owners in Edit profile.')),
          ListTile(
              leading: Icon(Icons.logout),
              title: Text('What signing out does'),
              subtitle: Text(
                  'Clears your session and account data from app memory. Cloud bookings, photos and messages are kept.')),
        ]),
        const SettingsSection(title: 'Account management', children: [
          ListTile(
              leading: Icon(Icons.download_outlined),
              title: Text('Export my data'),
              subtitle:
                  Text('Self-service export is not available in this build.')),
          ListTile(
              leading: Icon(Icons.person_remove_outlined),
              title: Text('Delete account'),
              subtitle: Text(
                  'Self-service deletion is not available yet. Signing out does not delete your account.')),
        ]),
      ]));
}
