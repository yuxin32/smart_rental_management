import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/auth/app_auth_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../admin/presentation/pages/admin_module_shell.dart';
import '../../../tenant/presentation/pages/tenant_module_shell.dart';
import 'tenant_set_password_page.dart';
import 'tenant_verification_page.dart';

class RoleLoginPage extends StatefulWidget {
  const RoleLoginPage({
    super.key,
    required this.expectedRole,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
  });

  final AppAccountType expectedRole;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;

  @override
  State<RoleLoginPage> createState() => _RoleLoginPageState();
}

class _RoleLoginPageState extends State<RoleLoginPage> {
  bool _obscurePassword = true;
  bool _isSigningIn = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String get _roleName {
    return widget.expectedRole == AppAccountType.admin
        ? 'administrator'
        : 'tenant';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Enter your email and password.');
      return;
    }

    setState(() => _isSigningIn = true);
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (!mounted) return;
      if (response.session == null) {
        _showMessage('Sign-in was not completed. Please try again.');
        return;
      }

      final profile = await AppAuthService.loadCurrentProfile();
      if (!mounted) return;
      if (profile == null) {
        await Supabase.instance.client.auth.signOut();
        _showMessage(
          'Your application account profile is not configured. Please contact the administrator.',
        );
        return;
      }
      final isPendingTenant =
          profile.accountType == AppAccountType.tenant &&
          profile.accountStatus == 'pending' &&
          (profile.invitationStatus == 'invited' ||
              profile.invitationStatus == 'accepted');

      if (!profile.isActive && !isPendingTenant) {
        await Supabase.instance.client.auth.signOut();
        _showMessage(
          'Your account is not active. Please contact the administrator.',
        );
        return;
      }
      if (profile.accountType != widget.expectedRole) {
        final actualRole = profile.accountType == AppAccountType.admin
            ? 'Administrator Login'
            : 'Tenant Login';
        await Supabase.instance.client.auth.signOut();
        _showMessage(
          'This account belongs to the $actualRole. Please use that login area.',
        );
        return;
      }

      _openModule(profile);
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Unable to sign in. Please try again.');
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  void _openModule(AppAuthProfile profile) {
    final Widget page;
    if (widget.expectedRole == AppAccountType.admin) {
      page = const AdminModuleShell();
    } else if (profile.accountStatus == 'pending' &&
        profile.invitationStatus == 'invited') {
      page = const TenantSetPasswordPage();
    } else if (profile.accountStatus == 'pending' &&
        profile.invitationStatus == 'accepted') {
      page = const TenantVerificationPage();
    } else {
      page = const TenantModuleShell();
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => page),
      (route) => false,
    );
  }

  Future<void> _showForgotPasswordDialog() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset password'),
        content: const Text(
          'A password reset link can be sent to your registered email address.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final email = _emailController.text.trim();
              if (email.isEmpty) {
                _showMessage('Enter your registered email first.');
                return;
              }

              try {
                await Supabase.instance.client.auth.resetPasswordForEmail(
                  email,
                );
                if (mounted) _showMessage('Password reset link sent.');
              } on AuthException catch (error) {
                if (mounted) _showMessage(error.message);
              } catch (_) {
                if (mounted) _showMessage('Unable to send the reset link.');
              }
            },
            child: const Text('Send link'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [widget.accentColor, AppColors.headerEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Back to role selection',
                ),
                const SizedBox(height: 12),
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(255, 255, 255, 0.18),
                    borderRadius: BorderRadius.circular(19),
                  ),
                  child: Icon(widget.icon, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 22),
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 31,
                    height: 1.12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.subtitle,
                  style: const TextStyle(
                    color: Color.fromRGBO(255, 255, 255, 0.84),
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 30),
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(
                          icon: Icons.email_outlined,
                          hint: 'Email address',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _signIn(),
                        decoration: _inputDecoration(
                          icon: Icons.lock_outline_rounded,
                          hint: 'Password',
                          suffix: IconButton(
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: const Color(0xFF9CA4B3),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _showForgotPasswordDialog,
                          child: const Text('Forgot password?'),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSigningIn ? null : _signIn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.accentColor,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: widget.accentColor
                                .withValues(alpha: 0.6),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: _isSigningIn
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Sign in as $_roleName',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Use another login area'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Only active $_roleName accounts can enter this module.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.body,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static InputDecoration _inputDecoration({
    required IconData icon,
    required String hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.primary),
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: Color(0xFFE0E4EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: Color(0xFFE0E4EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }
}
