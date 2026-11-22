// lib/widgets/cancellation_reason_sheet.dart
// Bottom sheet that requires the user to pick a reason before cancelling.
// Returns the chosen reason via Navigator.pop. If the user dismisses
// without picking, returns null.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class CancellationReason {
  const CancellationReason(
      {required this.id,
      required this.label,
      required this.icon,
      required this.color});
  final String id;
  final String label;
  final IconData icon;
  final Color color;
}

const kCancellationReasons = <CancellationReason>[
  CancellationReason(
      id: 'changed_mind',
      label: 'Changed my mind',
      icon: Icons.replay,
      color: Color(0xFF6B7280)),
  CancellationReason(
      id: 'scheduling',
      label: 'Scheduling conflict',
      icon: Icons.event_busy,
      color: Color(0xFFFB8C00)),
  CancellationReason(
      id: 'price',
      label: 'Price too high',
      icon: Icons.payments,
      color: Color(0xFFEF4444)),
  CancellationReason(
      id: 'bad_service',
      label: 'Provider not responsive',
      icon: Icons.support_agent,
      color: Color(0xFFEF4444)),
  CancellationReason(
      id: 'no_longer_need',
      label: 'No longer needed',
      icon: Icons.check_circle,
      color: Color(0xFF2E7D32)),
  CancellationReason(
      id: 'other',
      label: 'Other (tell us more)',
      icon: Icons.edit_note,
      color: Color(0xFF315BC5)),
];

const kProviderCancellationReasons = <CancellationReason>[
  CancellationReason(
      id: 'scheduling',
      label: 'Scheduling conflict',
      icon: Icons.event_busy,
      color: Color(0xFFFB8C00)),
  CancellationReason(
      id: 'emergency',
      label: 'Personal emergency',
      icon: Icons.health_and_safety_outlined,
      color: Color(0xFFEF4444)),
  CancellationReason(
      id: 'cannot_complete',
      label: 'Unable to complete this job',
      icon: Icons.cleaning_services_outlined,
      color: Color(0xFF6B7280)),
  CancellationReason(
      id: 'other',
      label: 'Other',
      icon: Icons.edit_note,
      color: Color(0xFF315BC5)),
];

String? bookingCancellationReason(
  Map<String, String>? selection, {
  bool forProvider = false,
}) {
  if (selection == null) return null;
  final reasons =
      forProvider ? kProviderCancellationReasons : kCancellationReasons;
  final matching =
      reasons.where((reason) => reason.id == selection['reason_id']);
  if (matching.isEmpty) return null;
  final comment = (selection['comment'] ?? '').trim();
  if (matching.first.id == 'other' && comment.isEmpty) return null;
  return comment.isEmpty
      ? matching.first.label
      : '${matching.first.label}: $comment';
}

class CancellationReasonSheet extends StatefulWidget {
  const CancellationReasonSheet(
      {super.key,
      required this.bookingId,
      this.allowComment = true,
      this.forProvider = false});
  final String bookingId;
  final bool allowComment;
  final bool forProvider;

  @override
  State<CancellationReasonSheet> createState() =>
      _CancellationReasonSheetState();
}

class _CancellationReasonSheetState extends State<CancellationReasonSheet> {
  String? _selectedId;
  String? _reasonError, _commentError;
  final _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_selectedId == null) {
      setState(() => _reasonError = 'Please pick a reason');
      return;
    }
    if (_selectedId == 'other' && _commentCtrl.text.trim().isEmpty) {
      setState(() => _commentError = 'Please describe the reason.');
      return;
    }
    Navigator.of(context).pop(<String, String>{
      'reason_id': _selectedId!,
      'comment': _commentCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.cancel_outlined,
                          size: 18, color: Color(0xFFEF4444)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cancel this booking?',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: sem.textPrimary)),
                          Text('Booking ${widget.bookingId.toUpperCase()}',
                              style: TextStyle(
                                  fontSize: 12, color: sem.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('WHY ARE YOU CANCELLING?',
                    style: TextStyle(
                        fontSize: 11,
                        color: sem.textSecondary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8)),
                const SizedBox(height: 10),
                if (_reasonError != null)
                  Semantics(
                      liveRegion: true,
                      child: Text(_reasonError!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
                ...(widget.forProvider
                        ? kProviderCancellationReasons
                        : kCancellationReasons)
                    .map((r) => _reasonTile(r, sem)),
                if (widget.allowComment || _selectedId == 'other') ...[
                  const SizedBox(height: 16),
                  Text(
                      _selectedId == 'other'
                          ? 'Describe your reason (required)'
                          : 'Anything else? (optional)',
                      style: TextStyle(
                          fontSize: 11,
                          color: sem.textSecondary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _commentCtrl,
                    onChanged: (_) {
                      if (_commentError != null)
                        setState(() => _commentError = null);
                    },
                    maxLines: 3,
                    maxLength: 200,
                    decoration: InputDecoration(
                      hintText: 'Help us improve...',
                      errorText: _commentError,
                      filled: true,
                      fillColor: sem.surfaceAlt,
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: sem.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: sem.border),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                LayoutBuilder(builder: (context, constraints) {
                  final stack = constraints.maxWidth < 360 ||
                      MediaQuery.textScalerOf(context).scale(14) > 19;
                  final keep = OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Keep booking'),
                  );
                  final cancel = FilledButton.icon(
                    onPressed: _confirm,
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Cancel booking'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  );
                  return stack
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [keep, const SizedBox(height: 12), cancel])
                      : Row(children: [
                          Expanded(child: keep),
                          const SizedBox(width: 12),
                          Expanded(child: cancel)
                        ]);
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reasonTile(CancellationReason r, SemanticColors sem) {
    final selected = _selectedId == r.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
          button: true,
          selected: selected,
          child: InkWell(
            onTap: () => setState(() {
              _selectedId = r.id;
              _reasonError = null;
              _commentError = null;
            }),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected ? r.color.withOpacity(0.1) : sem.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? r.color : sem.border,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: r.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(r.icon, size: 16, color: r.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      r.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: sem.textPrimary,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle, size: 18, color: r.color),
                ],
              ),
            ),
          )),
    );
  }
}
