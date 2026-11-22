import 'package:flutter/material.dart';
import '../services/backend/password_recovery_controller.dart';

/// Dedicated recovery destination. Never shows account data or auto-signs in.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.controller});
  final PasswordRecoveryController controller;
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _hidePassword = true;
  bool _hideConfirm = true;
  PasswordRecoveryController get recovery => widget.controller;

  @override
  void initState() {
    super.initState();
    recovery.addListener(_clearSensitiveFields);
  }

  void _clearSensitiveFields() {
    if (![RecoveryPhase.ready, RecoveryPhase.saving].contains(recovery.phase)) {
      _password.clear();
      _confirm.clear();
    }
  }

  @override
  void dispose() {
    recovery.removeListener(_clearSensitiveFields);
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (recovery.phase != RecoveryPhase.ready ||
        !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await recovery.updatePassword(_password.text);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: recovery,
        builder: (context, _) {
          final colors = Theme.of(context).colorScheme;
          final formVisible = [RecoveryPhase.ready, RecoveryPhase.saving]
              .contains(recovery.phase);
          final (title, body, icon) = switch (recovery.phase) {
            RecoveryPhase.complete => (
                'Password updated',
                'Sign in again using your new password. You have not been signed into the workspace automatically.',
                Icons.check_circle_outline
              ),
            RecoveryPhase.invalid => (
                'Request a new link',
                'This link is invalid, expired, already used, or recovery was interrupted. Return to login and choose Forgot password. Open the newest link in the same app or browser tab that requested it.',
                Icons.link_off
              ),
            RecoveryPhase.uncertain => (
                'Check your sign-in',
                'The connection did not confirm the update. Your password may have changed. Try signing in with your new password; if it does not work, request a new reset link. Do not submit this link again.',
                Icons.wifi_off_outlined
              ),
            RecoveryPhase.cleanupRequired => (
                'Secure cleanup needed',
                'We could not finish clearing the temporary session. Unlock your device and retry. The workspace stays closed until cleanup finishes.',
                Icons.lock_outline
              ),
            _ => (
                'Choose a new password',
                'Use at least 8 characters. A longer, unique passphrase is easier to remember and harder to guess.',
                Icons.lock_reset_outlined
              ),
          };
          return PopScope(
            canPop: false,
            child: Scaffold(
              body: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: AutofillGroup(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                    color: colors.primaryContainer,
                                    borderRadius: BorderRadius.circular(24),),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(icon,
                                          size: 36,
                                          color: colors.onPrimaryContainer,),
                                      const SizedBox(height: 20),
                                      Text(title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineSmall
                                              ?.copyWith(
                                                  color:
                                                      colors.onPrimaryContainer,
                                                  fontWeight: FontWeight.w700,),),
                                      const SizedBox(height: 12),
                                      Text(body,
                                          style: TextStyle(
                                              color: colors.onPrimaryContainer,
                                              height: 1.5,),),
                                    ],),
                              ),
                              const SizedBox(height: 24),
                              if (formVisible)
                                Form(
                                    key: _form,
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          TextFormField(
                                            key: const ValueKey(
                                                'recovery-password',),
                                            controller: _password,
                                            enabled: !recovery.busy,
                                            obscureText: _hidePassword,
                                            autocorrect: false,
                                            enableSuggestions: false,
                                            autofillHints: const [
                                              AutofillHints.newPassword,
                                            ],
                                            textInputAction:
                                                TextInputAction.next,
                                            decoration: InputDecoration(
                                                labelText: 'New password',
                                                suffixIcon: IconButton(
                                                    tooltip: _hidePassword
                                                        ? 'Show new password'
                                                        : 'Hide new password',
                                                    onPressed: () => setState(
                                                        () => _hidePassword =
                                                            !_hidePassword,),
                                                    icon: Icon(_hidePassword
                                                        ? Icons
                                                            .visibility_outlined
                                                        : Icons
                                                            .visibility_off_outlined,),),),
                                            validator: (value) => value ==
                                                        null ||
                                                    value.length < 8
                                                ? 'Use at least 8 characters'
                                                : null,
                                          ),
                                          const SizedBox(height: 20),
                                          TextFormField(
                                            key: const ValueKey(
                                                'recovery-confirm',),
                                            controller: _confirm,
                                            enabled: !recovery.busy,
                                            obscureText: _hideConfirm,
                                            autocorrect: false,
                                            enableSuggestions: false,
                                            autofillHints: const [
                                              AutofillHints.newPassword,
                                            ],
                                            textInputAction:
                                                TextInputAction.done,
                                            onFieldSubmitted: (_) => _save(),
                                            decoration: InputDecoration(
                                                labelText:
                                                    'Confirm new password',
                                                suffixIcon: IconButton(
                                                    tooltip: _hideConfirm
                                                        ? 'Show confirmation'
                                                        : 'Hide confirmation',
                                                    onPressed: () => setState(
                                                        () => _hideConfirm =
                                                            !_hideConfirm,),
                                                    icon: Icon(_hideConfirm
                                                        ? Icons
                                                            .visibility_outlined
                                                        : Icons
                                                            .visibility_off_outlined,),),),
                                            validator: (value) =>
                                                value != _password.text ||
                                                        (value ?? '').isEmpty
                                                    ? 'Passwords do not match'
                                                    : null,
                                          ),
                                          if (recovery.message != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 16,),
                                              child: Semantics(
                                                  liveRegion: true,
                                                  child: Text(recovery.message!,
                                                      style: TextStyle(
                                                          color:
                                                              colors.error,),),),
                                            ),
                                          const SizedBox(height: 24),
                                          FilledButton(
                                              onPressed:
                                                  recovery.busy ? null : _save,
                                              child: Text(recovery.busy
                                                  ? 'Updating password…'
                                                  : 'Update password',),),
                                        ],),),
                              if (recovery.phase == RecoveryPhase.checking)
                                const Center(
                                    child: CircularProgressIndicator(),),
                              if (recovery.phase ==
                                  RecoveryPhase.cleanupRequired)
                                FilledButton(
                                    onPressed: recovery.retryCleanup,
                                    child: const Text('Retry secure cleanup'),),
                              const SizedBox(height: 12),
                              TextButton(
                                  onPressed:
                                      recovery.busy ? null : recovery.leave,
                                  child: Text(formVisible
                                      ? 'Cancel and return to login'
                                      : 'Back to login',),),
                            ],),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}
