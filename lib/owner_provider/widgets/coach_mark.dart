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
    this.targetKey,
  });
  final String id;
  final String title;
  final String body;
  final IconData icon;
  final Color accent;
  final CoachMarkAlignment alignment;
  final GlobalKey? targetKey;
}

enum CoachMarkAlignment {
  topLeft,
  topRight,
  center,
  bottomCenter,
  bottomLeft,
  bottomRight
}

/// Persists 'seen' state for each coach-mark set by id.
class CoachMarkService {
  static const _kPrefix = 'coachmark_seen_';

  static Future<bool> hasSeen(String setId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_kPrefix$setId') ?? false;
  }

  static Future<void> markSeen(String setId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool('$_kPrefix$setId', true)) {
      throw StateError('Guidance preference was not saved.');
    }
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
  RawDialogRoute<bool>? _route;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(covariant CoachMarkOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.setId != widget.setId ||
        (oldWidget.marks.isEmpty && widget.marks.isNotEmpty)) {
      _removeRoute();
      _check();
    }
  }

  Future<void> _check() async {
    final generation = ++_generation, setId = widget.setId;
    if (widget.marks.isEmpty) return;
    var seen = false;
    try {
      seen = await CoachMarkService.hasSeen(setId);
    } catch (_) {/* Allow a fresh guide. */}
    if (!mounted || generation != _generation || seen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _generation ||
          _route != null ||
          ModalRoute.of(context)?.isCurrent == false) return;
      _open(setId, List<CoachMark>.unmodifiable(widget.marks));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _open(String setId, List<CoachMark> marks) async {
    final route = RawDialogRoute<bool>(
      settings: const RouteSettings(name: 'page-guidance'),
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      barrierLabel: 'Page guidance',
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      pageBuilder: (_, __, ___) => _PageGuidance(marks: marks),
    );
    _route = route;
    final completed =
        await Navigator.of(context, rootNavigator: true).push(route);
    if (identical(_route, route)) _route = null;
    if (completed == true) {
      try {
        await CoachMarkService.markSeen(setId);
      } catch (_) {
        // Explicit dismissal still works; a failed save may show the guide again.
      }
    }
  }

  void _removeRoute() {
    final route = _route;
    _route = null;
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = route.navigator;
      if (navigator != null && navigator.mounted && route.isActive) {
        navigator.removeRoute(route);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    ++_generation;
    _removeRoute();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PageGuidance extends StatefulWidget {
  const _PageGuidance({required this.marks});
  final List<CoachMark> marks;
  @override
  State<_PageGuidance> createState() => _PageGuidanceState();
}

class _PageGuidanceState extends State<_PageGuidance> {
  final _pageKey = GlobalKey();
  int _index = 0;
  bool _moving = true, _measureQueued = false;
  Rect? _target;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _queueMeasure();
  }

  void _queueMeasure() {
    if (_measureQueued) return;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      if (!mounted) return;
      final page = _pageKey.currentContext?.findRenderObject();
      final element =
          widget.marks[_index].targetKey?.currentContext?.findRenderObject();
      Rect? target;
      if (page is RenderBox &&
          page.hasSize &&
          element is RenderBox &&
          element.hasSize) {
        final top = page.globalToLocal(element.localToGlobal(Offset.zero));
        final bottom = page.globalToLocal(element
            .localToGlobal(Offset(element.size.width, element.size.height)));
        final rect = Rect.fromPoints(top, bottom)
            .inflate(7)
            .intersect(Offset.zero & page.size);
        if (!rect.isEmpty) target = rect;
      }
      if (_target != target) setState(() => _target = target);
    });
  }

  Future<void> _reveal() async {
    try {
      final target = widget.marks[_index].targetKey?.currentContext;
      if (target != null)
        await Scrollable.ensureVisible(target,
            duration: const Duration(milliseconds: 180), alignment: 0.1);
    } catch (_) {
      /* A target may disappear while the underlying data refreshes. */
    }
    if (!mounted) return;
    setState(() => _moving = false);
    _queueMeasure();
  }

  void _step(int next) {
    if (_moving) return;
    if (next >= widget.marks.length) {
      Navigator.of(context).pop(true);
      return;
    }
    if (next < 0) return;
    setState(() {
      _index = next;
      _moving = true;
      _target = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reveal();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColors.of(context),
        scheme = Theme.of(context).colorScheme;
    final mark = widget.marks[_index];
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (!didPop) _step(_index - 1);
        },
        child: Semantics(
            scopesRoute: true,
            explicitChildNodes: true,
            namesRoute: true,
            label: 'Page guidance',
            child: Stack(key: _pageKey, fit: StackFit.expand, children: [
              Positioned.fill(
                  child: CustomPaint(
                      painter:
                          _GuideBackdrop(_target, scheme.primaryContainer))),
              Positioned.fill(
                  child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      excludeFromSemantics: true,
                      // Keep the highlighted control and the rest of the shell
                      // visible but inert until Next, Back, Skip or Done.
                      onTap: () {},
                      child: const SizedBox.expand())),
              SafeArea(child: LayoutBuilder(builder: (context, bounds) {
                final alignment = _target != null
                    ? _target!.center.dy < bounds.maxHeight / 2
                        ? Alignment.bottomCenter
                        : Alignment.topCenter
                    : switch (mark.alignment) {
                        CoachMarkAlignment.topLeft ||
                        CoachMarkAlignment.topRight =>
                          Alignment.topCenter,
                        CoachMarkAlignment.center => Alignment.center,
                        _ => Alignment.bottomCenter,
                      };
                return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                        alignment: alignment,
                        child: ConstrainedBox(
                            constraints: BoxConstraints(
                                maxWidth: 560,
                                maxHeight: (bounds.maxHeight - 32)
                                    .clamp(0, double.infinity)),
                            child: Material(
                                color: colors.surface,
                                borderRadius: BorderRadius.circular(24),
                                child: Padding(
                                    padding: const EdgeInsets.all(22),
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Semantics(
                                              liveRegion: true,
                                              child: LayoutBuilder(
                                                  builder: (context, c) {
                                                final title = Text(mark.title,
                                                    style: TextStyle(
                                                        fontSize: 19,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: colors
                                                            .textPrimary));
                                                final count = Semantics(
                                                    label:
                                                        'Step ${_index + 1} of ${widget.marks.length}',
                                                    child: Text(
                                                        '${_index + 1} / ${widget.marks.length}',
                                                        style: TextStyle(
                                                            fontSize: 13,
                                                            color: colors
                                                                .textSecondary,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600)));
                                                return scale > 1.4
                                                    ? Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                            Align(
                                                                alignment: Alignment
                                                                    .centerRight,
                                                                child: count),
                                                            const SizedBox(
                                                                height: 8),
                                                            title
                                                          ])
                                                    : Row(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                            Expanded(
                                                                child: title),
                                                            const SizedBox(
                                                                width: 16),
                                                            count
                                                          ]);
                                              })),
                                          const SizedBox(height: 14),
                                          Flexible(
                                              fit: FlexFit.loose,
                                              child: SingleChildScrollView(
                                                  child: Text(mark.body,
                                                      style: TextStyle(
                                                          fontSize: 15,
                                                          height: 1.5,
                                                          color: colors
                                                              .textSecondary)))),
                                          const SizedBox(height: 22),
                                          LayoutBuilder(builder: (context, c) {
                                            final back = TextButton(
                                                onPressed: _index == 0 ||
                                                        _moving
                                                    ? null
                                                    : () => _step(_index - 1),
                                                style: TextButton.styleFrom(
                                                    minimumSize:
                                                        const Size(64, 48)),
                                                child: const Text('Back'));
                                            final skip = TextButton(
                                                onPressed: () =>
                                                    Navigator.of(context)
                                                        .pop(true),
                                                style: TextButton.styleFrom(
                                                    minimumSize:
                                                        const Size(64, 48)),
                                                child: const Text('Skip'));
                                            final next = FilledButton(
                                                onPressed: _moving
                                                    ? null
                                                    : () => _step(_index + 1),
                                                style: FilledButton.styleFrom(
                                                    minimumSize:
                                                        const Size(80, 48),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 20,
                                                        vertical: 12)),
                                                child: Text(_index ==
                                                        widget.marks.length - 1
                                                    ? 'Done'
                                                    : 'Next'));
                                            if (scale > 1.3 || c.maxWidth < 280)
                                              return Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [
                                                    back,
                                                    skip,
                                                    SizedBox(
                                                        width: c.maxWidth,
                                                        child: next)
                                                  ]);
                                            return Row(children: [
                                              back,
                                              skip,
                                              const Spacer(),
                                              next
                                            ]);
                                          }),
                                        ]))))));
              })),
            ])));
  }
}

class _GuideBackdrop extends CustomPainter {
  const _GuideBackdrop(this.target, this.outline);
  final Rect? target;
  final Color outline;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRect(Offset.zero & size);
    final rect = target;
    if (rect != null)
      path.addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)));
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black.withOpacity(0.58));
    if (rect != null)
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(12)),
          Paint()
            ..color = outline
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(covariant _GuideBackdrop oldDelegate) =>
      oldDelegate.target != target || oldDelegate.outline != outline;
}
