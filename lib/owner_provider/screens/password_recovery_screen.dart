import 'package:flutter/material.dart';

import '../services/backend/supabase_backend_provider.dart';
import '../theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/backend/auth_session_storage.dart';

/// Requests a PKCE recovery email; the app owns the trusted callback and reset UI.
class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({
    super.key,
    this.backend,
    this.initialEmail = '',
    this.sendResetEmail,
  });

  final SupabaseBackendProvider? backend;
  final String initialEmail;
  final Future<void> Function(String email)? sendResetEmail;

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController =
      TextEditingController(text: widget.initialEmail);
  bool _sending = false;
  bool _sent = false;
  String? _error;

  bool get _canSend =>
      widget.sendResetEmail != null ||
      (widget.backend != null && widget.backend!.recovery?.redirect != null);

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendLink() async {
    if (!_canSend || _sending || !_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final send =
          widget.sendResetEmail ?? widget.backend!.auth.sendPasswordResetEmail;
      await send(_emailController.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is AuthStorageException
            ? 'Unlock your device and try again. Secure recovery storage is unavailable.'
            : error is AuthException &&
                    ['over_request_rate_limit', 'over_email_send_rate_limit']
                        .contains(error.code)
                ? 'Too many reset requests. Wait a little before trying again.'
                : 'Could not send the link right now. Please try again.',);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed:
                            _sending ? null : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Back to login'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.fromLTRB(22, 25, 22, 25),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lock_reset_outlined,
                              color: AppColors.primaryLighter, size: 31,),
                          SizedBox(height: 18),
                          Text('Password recovery',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 27,
                                  fontWeight: FontWeight.w800,),),
                          SizedBox(height: 6),
                          Text('Owner and Service Provider accounts',
                              style: TextStyle(
                                  color: Color(0xFFD9E8FF),
                                  fontSize: 12,
                                  height: 1.4,),),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: _sent ? _confirmation() : _requestForm(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _requestForm() => Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Forgot your password?',
                style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,),),
            const SizedBox(height: 8),
            Text(
              'Enter the email address you used to create your account. '
              'We will send instructions to reset your password.',
              style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,),
            ),
            const SizedBox(height: 22),
            Text('Email address',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,),),
            const SizedBox(height: 7),
            TextFormField(
              controller: _emailController,
              autofocus: false,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              onFieldSubmitted: (_) => _sendLink(),
              decoration: const InputDecoration(
                hintText: 'name@example.com',
                prefixIcon: Icon(Icons.mail_outline),
                helperText: 'Use the email linked to your account.',
              ),
              validator: (value) {
                final email = (value ?? '').trim();
                if (email.isEmpty) return 'Email address is required';
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                  return 'Enter a valid email address';
                }
                return null;
              },
            ),
            if (!_canSend) ...[
              const SizedBox(height: 16),
              _message(
                Icons.info_outline,
                widget.backend == null
                    ? 'Connect to your workspace to request a password recovery email.'
                    : 'Password recovery is not configured yet. Contact support; no email will be sent from this screen.',
                Theme.of(context).colorScheme.secondaryContainer,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              _message(Icons.error_outline, _error!,
                  Theme.of(context).colorScheme.errorContainer,),
            ],
            const SizedBox(height: 22),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _canSend && !_sending ? _sendLink : null,
                icon: _sending
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined, size: 18),
                label: Text(_sending ? 'Sending…' : 'Send reset link'),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _sending ? null : () => Navigator.of(context).pop(),
              child: const Text('Back to login'),
            ),
          ],
        ),
      );

  Widget _confirmation() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.mark_email_read_outlined,
              color: Theme.of(context).colorScheme.primary, size: 42,),
          const SizedBox(height: 15),
          Text('Check your email',
              style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,),),
          const SizedBox(height: 9),
          Text(
            'If an account exists for ${_emailController.text.trim()}, '
            'you will receive a password reset link. Check your spam folder too.',
            style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,),
          ),
          const SizedBox(height: 22),
          const Text(
              'Keep this app open. On web, open the newest reset link in this same browser tab, not a different tab or device.',
              style: TextStyle(fontSize: 12, height: 1.5),),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to login'),
            ),
          ),
          const SizedBox(height: 9),
          TextButton(
            onPressed: () => setState(() => _sent = false),
            child: const Text('Use a different email'),
          ),
        ],
      );

  Widget _message(IconData icon, String text, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 9),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );
}
