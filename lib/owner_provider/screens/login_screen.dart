import 'package:flutter/material.dart';
import '../services/user_session.dart';
import '../widgets/figma_ui.dart';

/// Figma 192:606. Authentication remains explicitly local/demo only.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController(text: 'owner@example.com');
  final _passCtrl = TextEditingController(text: 'demo1234');
  UserRole _role = UserRole.owner;
  bool _submitting = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    UserSessionAccess.of(context).signIn(
        email: _emailCtrl.text.trim(),
        displayName: _role == UserRole.owner ? 'Oh Wan Ting' : 'Provider A',
        role: _role);
    setState(() => _submitting = false);
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Widget _field(String label, TextEditingController controller,
          {bool password = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style:
                FigmaUi.text(10, bold: true, color: const Color(0xFF61708A))),
        const SizedBox(height: 6),
        FigmaSurface(
            asset: 'login-field',
            child: TextFormField(
              controller: controller,
              obscureText: password,
              keyboardType: password
                  ? TextInputType.visiblePassword
                  : TextInputType.emailAddress,
              style: FigmaUi.text(12, color: const Color(0xFF25324A)),
              decoration: InputDecoration(
                  hintText: label,
                  filled: false,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 15),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: const BorderSide(color: FigmaUi.blue))),
              validator: (value) {
                if (value == null || value.trim().isEmpty)
                  return '$label is required';
                if (password && value.length < 6)
                  return 'At least 6 characters';
                if (!password && !value.contains('@'))
                  return 'Enter a valid email';
                return null;
              },
            )),
      ]);

  @override
  Widget build(BuildContext context) => Theme(
      data: FigmaUi.theme,
      child: Scaffold(
        appBar: FigmaHeader(
            title: 'Welcome Back',
            subtitle: 'Shared Authentication',
            variant: 'login',
            trailing: PopupMenuButton<UserRole>(
              tooltip: 'Choose account role',
              icon: const Icon(Icons.more_horiz, color: Colors.white, size: 20),
              onSelected: (role) => setState(() {
                _role = role;
                _emailCtrl.text = role == UserRole.owner
                    ? 'owner@example.com'
                    : 'provider@example.com';
              }),
              itemBuilder: (_) => const [
                PopupMenuItem(value: UserRole.owner, child: Text('Property Owner')),
                PopupMenuItem(
                    value: UserRole.provider, child: Text('Service Provider')),
              ],
            )),
        body: FigmaSurface(
            asset: 'login-background',
            child: SizedBox.expand(
                child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 19, 26, 24),
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: FigmaSurface(
                          asset: 'login-login-card',
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(22, 21, 22, 28),
                            child: Form(
                                key: _formKey,
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text('Welcome Back',
                                          textAlign: TextAlign.center,
                                          style: FigmaUi.text(24, bold: true)),
                                      const SizedBox(height: 10),
                                      Text(
                                          'Smart Rental Management Mobile Application',
                                          textAlign: TextAlign.center,
                                          style: FigmaUi.text(11,
                                              color: FigmaUi.muted)),
                                      const SizedBox(height: 26),
                                      _field('Email address', _emailCtrl),
                                      const SizedBox(height: 12),
                                      _field('Password', _passCtrl,
                                          password: true),
                                      Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton(
                                              style: TextButton.styleFrom(
                                                  padding: EdgeInsets.zero,
                                                  alignment:
                                                      Alignment.centerLeft),
                                              onPressed: () => _notice(
                                                  'Connect to your workspace to request password recovery.'),
                                              child: Text('Forgot password?',
                                                  style: FigmaUi.text(11,
                                                      bold: true,
                                                      color: FigmaUi.blue)))),
                                      FigmaButton(
                                          label: _submitting
                                              ? 'Signing in…'
                                              : 'Log In',
                                          onPressed:
                                              _submitting ? null : _submit),
                                      const SizedBox(height: 17),
                                      Text('or',
                                          textAlign: TextAlign.center,
                                          style: FigmaUi.text(10,
                                              color: FigmaUi.muted)),
                                      const SizedBox(height: 17),
                                      FigmaButton(
                                          label: 'Register Owner Account',
                                          outlined: true,
                                          onPressed: () => _notice(
                                              'Connect to your workspace to create an account.')),
                                      const SizedBox(height: 22),
                                      Text(
                                          'Secure access for Property Owners and\nCleaning Service Providers',
                                          textAlign: TextAlign.center,
                                          style: FigmaUi.text(11,
                                              color: FigmaUi.muted)),
                                      const SizedBox(height: 22),
                                      Text(
                                          'Offline workspace · Online sign-in unavailable',
                                          textAlign: TextAlign.center,
                                          style: FigmaUi.text(10,
                                              color: FigmaUi.muted)),
                                    ])),
                          )))),
            ))),
        bottomNavigationBar: FigmaOwnerNav(
            variant: 'login',
            onChange: (_) =>
                _notice('Please log in before opening account pages.')),
      ));
}
