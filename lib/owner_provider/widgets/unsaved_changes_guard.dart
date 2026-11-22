import 'package:flutter/material.dart';

/// Always intercept system back: a rapid edit/back must not beat a rebuild.
class UnsavedChangesGuard extends StatefulWidget {
  const UnsavedChangesGuard(
      {super.key,
      required this.dirty,
      required this.busy,
      required this.child});
  final bool Function() dirty, busy;
  final Widget child;
  @override
  State<UnsavedChangesGuard> createState() => _UnsavedChangesGuardState();
}

class _UnsavedChangesGuardState extends State<UnsavedChangesGuard> {
  bool _allow = false, _asking = false;
  @override
  Widget build(BuildContext context) => PopScope(
      canPop: _allow,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _asking || widget.busy()) return;
        _asking = true;
        final discard = !widget.dirty() ||
            await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                            scrollable: true,
                            title: const Text('Discard changes?'),
                            content: const Text(
                                'Your unsaved entries will be lost.'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Keep editing')),
                              TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Discard'))
                            ])) ==
                true;
        _asking = false;
        if (!mounted || !discard) return;
        setState(() => _allow = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(result);
        });
      },
      child: widget.child);
}
