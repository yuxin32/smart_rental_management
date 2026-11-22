import '../config/integrated_backend.dart';
import 'package:flutter/material.dart';

/// A persistent sign-out action used by both role workspaces.
///
/// The named login route keeps this widget independent from the role-specific
/// pages and clears the navigation stack so a previous role cannot be reopened
/// with the system back button.
class AppLogoutButton extends StatefulWidget {
  const AppLogoutButton({
    this.foregroundColor = const Color(0xFF293042),
    this.backgroundColor = Colors.white,
    super.key,
  });

  final Color foregroundColor;
  final Color backgroundColor;

  @override
  State<AppLogoutButton> createState() => _AppLogoutButtonState();
}

class _AppLogoutButtonState extends State<AppLogoutButton> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);

    try {
      await IntegratedBackend.instance.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _signingOut = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to sign out. Please try again.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _signingOut ? null : _signOut,
      style: IconButton.styleFrom(
        backgroundColor: widget.backgroundColor,
        foregroundColor: widget.foregroundColor,
        disabledBackgroundColor: widget.backgroundColor,
      ),
      tooltip: 'Sign out',
      icon: _signingOut
          ? SizedBox(
              width: 19,
              height: 19,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: widget.foregroundColor,
              ),
            )
          : const Icon(Icons.logout_rounded),
    );
  }
}
