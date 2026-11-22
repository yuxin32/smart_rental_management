// lib/widgets/reject_reason_sheet.dart
// Bottom sheet shown when a Provider taps "Reject job" on a requested booking.
//
// F1a decision: rejection reason is OPTIONAL. The user can:
//   1. Pick one of 5 quick-reason chips
//   2. Type a custom reason
//   3. Skip entirely (just submit empty)
//
// Returns the chosen reason (possibly null) via the [onSubmit] callback.

import 'package:flutter/material.dart';

class RejectReasonSheet extends StatefulWidget {
  const RejectReasonSheet({super.key, required this.onSubmit});

  /// Called when the user confirms. The reason may be null (skipped) or empty.
  final void Function(String? reason) onSubmit;

  /// Shows the bottom sheet as a modal. Wraps the StatefulWidget in a
  /// showModalBottomSheet call so the caller can invoke it with one line.
  static Future<void> show(
    BuildContext context, {
    required void Function(String? reason) onSubmit,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: RejectReasonSheet(onSubmit: (reason) {
          Navigator.of(ctx).pop();
          onSubmit(reason);
        }),
      ),
    );
  }

  @override
  State<RejectReasonSheet> createState() => _RejectReasonSheetState();
}

class _RejectReasonSheetState extends State<RejectReasonSheet> {
  final _controller = TextEditingController();
  static const _quickReasons = <String>[
    'Distance too far',
    'Schedule conflict',
    'Already have other work',
    'Personal reason',
    'Other',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pickQuick(String reason) {
    setState(() {
      // If quick reason is "Other", leave text field empty for custom input.
      if (reason == 'Other') {
        _controller.clear();
      } else {
        _controller.text = reason;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Reject this booking?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Optional: tell the owner why. The reason is recorded in the booking history.',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 16),
            // Quick-reason chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickReasons
                  .map((r) => ActionChip(
                        label: Text(r, style: const TextStyle(fontSize: 12)),
                        onPressed: () => _pickQuick(r),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            // Custom reason text field
            TextField(
              controller: _controller,
              maxLines: 3,
              maxLength: 200,
              decoration: const InputDecoration(
                hintText: 'Or type a custom reason...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => widget.onSubmit(null),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    child: const Text('Skip'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final text = _controller.text.trim();
                      widget.onSubmit(text.isEmpty ? null : text);
                    },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      backgroundColor: const Color(0xFFEF4444),
                    ),
                    child: const Text(
                      'Reject booking',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
