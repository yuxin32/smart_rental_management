import 'package:flutter/material.dart';
import 'app_bottom_nav.dart';

/// Top-level provider destinations share the same original navigation visuals.
class ProviderBottomNav extends StatefulWidget {
  const ProviderBottomNav(
      {super.key, required this.activeId, required this.onChange});
  final String activeId;
  final Future<void> Function(String) onChange;
  @override
  State<ProviderBottomNav> createState() => _ProviderBottomNavState();
}

class _ProviderBottomNavState extends State<ProviderBottomNav> {
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
  Widget build(BuildContext context) =>
      AppBottomNav(activeId: widget.activeId, onChange: _change, tabs: const [
        NavTab(id: 'inbox', icon: Icons.inbox, label: 'Inbox'),
        NavTab(id: 'schedule', icon: Icons.calendar_today, label: 'Schedule'),
        NavTab(id: 'earnings', icon: Icons.payments, label: 'Earnings'),
        NavTab(id: 'profile', icon: Icons.person, label: 'Profile'),
      ]);
}

/// Keep one primary tab route above Inbox instead of accumulating a history of
/// Schedule/Earnings/Profile copies. Details/editors keep normal push/back.
abstract final class ProviderTabNavigation {
  static String nameFor(String id) => '/provider-tab/$id';
  static Future<void> open(
      BuildContext context, String id, WidgetBuilder builder) async {
    final navigator = Navigator.of(context);
    if (id == 'inbox') {
      navigator.popUntil((route) => route.isFirst);
      return;
    }
    final current = ModalRoute.of(context)?.settings.name;
    final target = nameFor(id);
    if (current == target) return;
    final route = MaterialPageRoute<void>(
        settings: RouteSettings(name: target), builder: builder);
    if (current?.startsWith('/provider-tab/') == true) {
      await navigator.pushReplacement<void, void>(route);
    } else {
      await navigator.push<void>(route);
    }
  }
}
