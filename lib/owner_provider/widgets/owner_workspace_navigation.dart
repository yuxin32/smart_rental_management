import 'package:flutter/material.dart';
import '../screens/owner_workspace_dashboard.dart';

/// Carries the existing Owner root's Home/Bookings selection across pushed tabs.
/// It contains no backend state and never creates another Owner home instance.
class OwnerRootNavigation extends InheritedWidget {
  const OwnerRootNavigation(
      {super.key, required this.select, required super.child});
  final ValueChanged<String> select;

  static OwnerRootNavigation? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<OwnerRootNavigation>();

  static Widget inherit(BuildContext source, Widget child) {
    final root = maybeOf(source);
    return root == null
        ? child
        : OwnerRootNavigation(select: root.select, child: child);
  }

  @override
  bool updateShouldNotify(OwnerRootNavigation oldWidget) =>
      select != oldWidget.select;
}

class OwnerDestinationFrame extends StatefulWidget {
  const OwnerDestinationFrame(
      {super.key,
      required this.activeId,
      required this.onChange,
      required this.child});
  final String activeId;
  final Future<void> Function(String) onChange;
  final Widget child;
  @override
  State<OwnerDestinationFrame> createState() => _OwnerDestinationFrameState();
}

class _OwnerDestinationFrameState extends State<OwnerDestinationFrame> {
  bool _navigating = false;
  Future<void> _change(String id) async {
    if (_navigating || id == widget.activeId) return;
    _navigating = true;
    try {
      await widget.onChange(id);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open this page. Please try again.')));
    } finally {
      _navigating = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        // Inner original screen owns keyboard avoidance, AppBar and any sticky CTA.
        resizeToAvoidBottomInset: false,
        body: widget.child,
        bottomNavigationBar:
            OwnerWorkspaceNav(activeId: widget.activeId, onChange: _change),
      );
}

abstract final class OwnerTabNavigation {
  static String nameFor(String id) => '/owner-tab/$id';
  static Future<void> open(
      BuildContext context, String id, WidgetBuilder builder) async {
    final navigator = Navigator.of(context);
    final root = OwnerRootNavigation.maybeOf(context);
    if (id == 'home' || id == 'bookings') {
      navigator.popUntil((route) => route.isFirst);
      root?.select(id);
      return;
    }
    final target = nameFor(id);
    // Detail pages above a primary tab are read-only. Return to that primary
    // route before switching, rather than piling another copy on top of it.
    Route<dynamic>? current;
    navigator.popUntil((route) {
      current = route;
      return route.isFirst ||
          route.settings.name?.startsWith('/owner-tab/') == true;
    });
    if (current?.settings.name == target) return;
    final route = MaterialPageRoute<void>(
        settings: RouteSettings(name: target),
        builder: (context) => root == null
            ? builder(context)
            : OwnerRootNavigation(
                select: root.select, child: Builder(builder: builder)));
    if (current?.settings.name?.startsWith('/owner-tab/') == true) {
      await navigator.pushReplacement<void, void>(route);
    } else {
      await navigator.push<void>(route);
    }
  }
}
