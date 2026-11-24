import 'package:flutter/material.dart';

Future<void> confirmProfileSignOut(
  BuildContext context,
  VoidCallback onConfirmed,
) async {
  if (ModalRoute.of(context)?.isCurrent == false) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      scrollable: true,
      title: const Text('Sign out?'),
      content: const Text(
        'You’ll need to log in again. Your saved bookings and messages '
        'will stay in your account.',
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(dialog).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialog).pop(true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) onConfirmed();
}
