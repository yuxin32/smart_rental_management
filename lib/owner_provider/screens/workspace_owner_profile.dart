import 'package:flutter/material.dart';
import '../services/backend/supabase_backend_provider.dart';
import '../services/backend/supabase_workspace_repository.dart';
import '../services/user_session.dart';
import '../widgets/owned_workspace_page.dart';
import '../widgets/workspace_actions.dart';
import '../widgets/unsaved_changes_guard.dart';
import 'owner_home_screen.dart';

class WorkspaceOwnerProfile extends StatelessWidget {
  const WorkspaceOwnerProfile({super.key, required this.backend});
  final SupabaseBackendProvider backend;
  @override
  Widget build(BuildContext context) {
    final repo = SupabaseWorkspaceRepository(backend),
        actions = WorkspaceActions(backend, UserRole.owner);
    return actions.ownerDestination(
        context,
        'profile',
        OwnedWorkspacePage(
            backend: backend,
            title: 'Profile & settings',
            cacheKey: 'owner:profile:v1',
            load: repo.ownerProfile,
            builder: (context, binding) => OwnerProfileScreen(
                snapshot: binding.snapshot,
                onRefresh: binding.refresh,
                notice: ownedPageFooter(binding),
                onOpenBookings: () => actions.properties(context),
                onAction: (title) async {
                  try {
                    switch (title) {
                      case 'Edit profile':
                        final fresh = await repo.ownerProfile();
                        if (!context.mounted || !binding.valid) return;
                        await Navigator.of(context).push<void>(
                            MaterialPageRoute(
                                builder: (_) => OwnerProfileEditor(
                                    row: fresh,
                                    canSave: () => binding.valid,
                                    save: (input) => repo.saveOwner(
                                        input, fresh['revision'] as int))));
                        if (context.mounted && binding.valid) {
                          await binding.refresh();
                          if (context.mounted &&
                              binding.valid &&
                              binding.snapshot?['full_name'] is String)
                            UserSessionAccess.of(context).updateDisplayName(
                                binding.snapshot!['full_name'] as String);
                        }
                      case 'Notifications':
                        await actions.settings(context, 'notifications');
                      case 'Schedule':
                        await actions.schedule(context);
                      case 'Spending':
                        await actions.spending(context);
                      case 'Appearance':
                        await actions.settings(context, 'appearance');
                      case 'Privacy & security':
                      case 'Change password':
                        await actions.settings(context, 'privacy');
                      case 'Sign out':
                        await actions.signOut(context);
                      case 'Terms of service':
                      case 'Privacy policy':
                      case 'App version':
                      case 'About & help':
                        await actions.about(context);
                      default:
                        final message = switch (title) {
                          'Email' =>
                            'The sign-in email is read-only here. This page does not change your authentication identity.',
                          'Verification' =>
                            'Identity-document verification has not been implemented. No verified identity is claimed.',
                          'Language' =>
                            'English (Malaysia) is currently the available interface language.',
                          _ =>
                            'Use Forgot password on the sign-in screen for email recovery. Addresses ending in .invalid cannot receive email. No recovery email is sent by opening this information.'
                        };
                        if (context.mounted)
                          await showDialog<void>(
                              context: context,
                              builder: (c) => AlertDialog(
                                      scrollable: true,
                                      title: Text(title),
                                      content: Text(message),
                                      actions: [
                                        TextButton(
                                            onPressed: () => Navigator.pop(c),
                                            child: const Text('OK'))
                                      ]));
                    }
                  } catch (_) {
                    if (context.mounted)
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Could not open this action. Please try again.')));
                  }
                })));
  }
}

class OwnerProfileEditor extends StatefulWidget {
  const OwnerProfileEditor(
      {super.key,
      required this.row,
      required this.canSave,
      required this.save});
  final Map<String, dynamic> row;
  final bool Function() canSave;
  final Future<void> Function(Map<String, dynamic>) save;
  @override
  State<OwnerProfileEditor> createState() => _OwnerEditorState();
}

class _OwnerEditorState extends State<OwnerProfileEditor> {
  final _form = GlobalKey<FormState>();
  late final name =
      TextEditingController(text: widget.row['full_name'] as String? ?? '');
  late final phone = TextEditingController(
      text: widget.row['contact_number'] as String? ?? '');
  bool busy = false, verify = false;
  String? error;
  bool get dirty =>
      name.text != (widget.row['full_name'] ?? '') ||
      phone.text != (widget.row['contact_number'] ?? '');
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || verify || !_form.currentState!.validate()) return;
    if (!widget.canSave()) {
      setState(() =>
          error = 'Your session changed. Close this form and sign in again.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save({
        'full_name': name.text.trim(),
        'contact_number': phone.text.trim().isEmpty ? null : phone.text.trim()
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile changes saved.')));
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted)
        setState(() {
          verify = true;
          error =
              'Could not confirm this save, or this profile changed elsewhere. Your entries are kept. Close and reload the profile before saving again.';
        });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      dirty: () => dirty,
      busy: () => busy,
      child: Scaffold(
          appBar: AppBar(title: const Text('Edit profile')),
          body: Form(
              key: _form,
              // Keep every FormField mounted: scrolling to Save must not remove
              // an invalid earlier field from FormState.validate().
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Personal details',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        const Text(
                            'Your name and contact number are the details you provide when creating your account.'),
                        const SizedBox(height: 16),
                        TextFormField(
                            controller: name,
                            enabled: !busy,
                            maxLength: 60,
                            decoration: const InputDecoration(
                                labelText: 'Your name',
                                hintText: 'e.g. Aina Ahmad',
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.always,
                                helperText:
                                    'Used on your profile and welcome message.'),
                            validator: (v) =>
                                v == null || v.trim().runes.length < 2
                                    ? 'Enter a name of 2–60 characters'
                                    : null),
                        const SizedBox(height: 16),
                        TextFormField(
                            controller: phone,
                            enabled: !busy,
                            maxLength: 25,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                                labelText: 'Contact number (optional)',
                                hintText: '+60 12 345 6789',
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.always),
                            validator: (v) => v == null ||
                                    v.trim().isEmpty ||
                                    RegExp(r'^\+?[0-9 ()-]{7,25}$')
                                        .hasMatch(v.trim())
                                ? null
                                : 'Enter a valid contact number'),
                        const SizedBox(height: 16),
                        Text('Account details',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        InputDecorator(
                            decoration: const InputDecoration(
                                labelText: 'Sign-in email',
                                suffixIcon: Icon(Icons.lock_outline)),
                            child: SelectableText(
                                widget.row['email'] as String? ??
                                    'Unavailable')),
                        const SizedBox(height: 16),
                        const InputDecorator(
                            decoration: InputDecoration(
                                labelText: 'Account role',
                                suffixIcon: Icon(Icons.lock_outline)),
                            child: Text('Property Owner')),
                        const SizedBox(height: 12),
                        const Text(
                            'Email changes need verification. Your account role is fixed. Passwords are never displayed; use Forgot password on the sign-in screen to request a reset when available.'),
                        if (error != null)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(error!)),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed: busy || verify ? null : save,
                            child: Text(busy ? 'Saving…' : 'Save changes')),
                      ])))));
}
