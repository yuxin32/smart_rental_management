import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/auth/app_logout_button.dart';
import '../../../../core/config/integrated_backend.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../admin/data/tenant_lifecycle_service.dart';
import 'tenant_login_page.dart';

class TenantSetPasswordPage extends StatefulWidget {
  const TenantSetPasswordPage({super.key});

  @override
  State<TenantSetPasswordPage> createState() => _TenantSetPasswordPageState();
}

class _TenantSetPasswordPageState extends State<TenantSetPasswordPage> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  bool _isSaving = false;
  bool _passwordUpdated = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    if (_isSaving) return;
    final password = _passwordController.text;
    final confirmation = _confirmPasswordController.text;

    if (password.length < 8) {
      _showMessage('Your password must contain at least 8 characters.');
      return;
    }
    if (password != confirmation) {
      _showMessage('The passwords do not match.');
      return;
    }

    setState(() => _isSaving = true);
    final navigator = Navigator.of(context);
    try {
      if (!_passwordUpdated) {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(password: password),
        );
        _passwordUpdated = true;
      }
      await TenantLifecycleService.activateCurrentTenant();
      await IntegratedBackend.instance.auth.signOut();
      // Signing out can rebuild the auth gate and dispose this form. The
      // root navigator still owns the route to the tenant sign-in screen.
      if (!navigator.mounted) return;

      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const TenantLoginPage()),
        (route) => false,
      );
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) {
        _showMessage(
          _passwordUpdated
              ? 'Your password was saved. Account setup or sign-out could not finish. Please retry.'
              : 'Unable to complete account setup. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.headerStart, AppColors.headerEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 46, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(255, 255, 255, 0.18),
                        borderRadius: BorderRadius.circular(19),
                      ),
                      child: const Icon(
                        Icons.lock_reset_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const AppLogoutButton(
                      foregroundColor: Colors.white,
                      backgroundColor: Color.fromRGBO(255, 255, 255, 0.18),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                const Text(
                  'Create your own password',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    height: 1.12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Replace the temporary password provided by the apartment administrator. After saving, sign in again with your new password.',
                  style: TextStyle(
                    color: Color.fromRGBO(255, 255, 255, 0.84),
                    fontSize: 15,
                    height: 1.4,
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
                        enabled: !_isSaving && !_passwordUpdated,
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: _inputDecoration(
                          hint: 'Create password',
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
                      const SizedBox(height: 16),
                      TextFormField(
                        enabled: !_isSaving && !_passwordUpdated,
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmation,
                        decoration: _inputDecoration(
                          hint: 'Confirm password',
                          suffix: IconButton(
                            onPressed: () => setState(
                              () =>
                                  _obscureConfirmation = !_obscureConfirmation,
                            ),
                            icon: Icon(
                              _obscureConfirmation
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: const Color(0xFF9CA4B3),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _savePassword,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _passwordUpdated
                                      ? 'Finish setup and return to login'
                                      : 'Save password and return to login',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Use at least 8 characters and do not share your password with anyone.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.body,
                          fontSize: 12.5,
                          height: 1.4,
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
    required String hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(
        Icons.lock_outline_rounded,
        color: AppColors.primary,
      ),
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
