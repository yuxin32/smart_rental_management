// lib/widgets/coach_mark.dart
// First-launch coach marks — overlay tooltips that highlight key UI elements
// after the main onboarding. Uses SharedPreferences to track 'seen' state per shell.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class CoachMark {
  const CoachMark({
    required this.id,
    required this.title,
    required this.body,
    required this.icon,
    required this.accent,
    this.alignment = CoachMarkAlignment.center,
  });
  final String id;
  final String title;
  final String body;
  final IconData icon;
  final Color accent;
  final CoachMarkAlignment alignment;
}

enum CoachMarkAlignment { topLeft, topRight, center, bottomCenter, bottomLeft, bottomRight }

/// Persists 'seen' state for each coach-mark set by id.
class CoachMarkService {
  static const _kPrefix = 'coachmark_seen_';

  static Future<bool> hasSeen(String setId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_kPrefix$setId') ?? false;
  }

  static Future<void> markSeen(String setId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_kPrefix$setId', true);
  }

  static Future<void> reset(String setId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_kPrefix$setId');
  }
}

/// Overlay widget that shows coach marks sequentially.
/// Wrap your screen's body with this. It shows a modal overlay
/// (semi-transparent backdrop) with the current mark's tooltip card.
class CoachMarkOverlay extends StatefulWidget {
  const CoachMarkOverlay({
    super.key,
    required this.setId,
    required this.marks,
    required this.child,
  });

  /// The set id used to persist 'seen' state.
  final String setId;
  final List<CoachMark> marks;
  final Widget child;

  @override
  State<CoachMarkOverlay> createState() => _CoachMarkOverlayState();
}

class _CoachMarkOverlayState extends State<CoachMarkOverlay> {
  bool _show = false;
  int _idx = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final seen = await CoachMarkService.hasSeen(widget.setId);
    if (mounted) {
      setState(() {
        _show = !seen && widget.marks.isNotEmpty;
        _loading = false;
      });
    }
  }

  void _next() {
    if (_idx < widget.marks.length - 1) {
      setState(() => _idx++);
    } else {
      _dismiss();
    }
  }

  void _dismiss() {
    CoachMarkService.markSeen(widget.setId);
    setState(() {
      _show = false;
      _idx = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || !_show) return widget.child;
    final sem = SemanticColors.of(context);
    final mark = widget.marks[_idx];
    return Stack(
      children: [
        widget.child,
        // Backdrop
        Positioned.fill(
          child: GestureDetector(
            onTap: _next,
            child: Container(color: Colors.black.withOpacity(0.65)),
          ),
        ),
        // Tooltip card
        Positioned(
          left: 20,
          right: 20,
          top: _alignmentTop(mark.alignment),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: sem.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 24, offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: mark.accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(mark.icon, color: mark.accent, size: 24),
                      ),
                      const Spacer(),
                      Text(
                        '${_idx + 1} of ${widget.marks.length}',
                        style: TextStyle(fontSize: 12, color: sem.textTertiary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      mark.title,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: sem.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      mark.body,
                      style: TextStyle(fontSize: 14, color: sem.textSecondary, height: 1.4),
                      softWrap: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _dismiss,
                        child: Text('Skip', style: TextStyle(color: sem.textSecondary)),
                      ),
                      const Spacer(),
                      if (_idx > 0)
                        TextButton(
                          onPressed: () => setState(() => _idx--),
                          child: const Text('Back'),
                        ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _next,
                        style: FilledButton.styleFrom(backgroundColor: mark.accent),
                        child: Text(_idx == widget.marks.length - 1 ? 'Got it' : 'Next'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        // Page indicator dots
        Positioned(
          left: 0, right: 0, bottom: 32,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.marks.length, (i) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _idx ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _idx ? mark.accent : Colors.white.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  double? _alignmentTop(CoachMarkAlignment a) {
    final h = MediaQuery.of(context).size.height;
    // Bottom-aligned marks need to clear the bottom nav (~64dp) + FAB column
    // (~96dp on owner home with AutoDemo + New request) + safe area (~30dp)
    // = ~190dp from bottom. Pull the tooltip further up to avoid overlap.
    const bottomReserved = 220.0;
    switch (a) {
      case CoachMarkAlignment.topLeft: return 80;
      case CoachMarkAlignment.topRight: return 80;
      case CoachMarkAlignment.center: return (h / 2) - 120;
      case CoachMarkAlignment.bottomCenter: return h - bottomReserved - 220;
      case CoachMarkAlignment.bottomLeft: return h - bottomReserved - 220;
      case CoachMarkAlignment.bottomRight: return h - bottomReserved - 220;
    }
  }
}
