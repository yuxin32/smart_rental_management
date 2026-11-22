// lib/widgets/app_bottom_nav.dart
// Reusable bottom navigation bar.
// Uses a fixed 4-tab layout with a "rail" design â€” Material 3 NavigationBar.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class NavTab {
  const NavTab({required this.id, required this.icon, required this.label});
  final String id;
  final IconData icon;
  final String label;
}

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.tabs,
    required this.activeId,
    required this.onChange,
  });

  final List<NavTab> tabs;
  final String activeId;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    final activeIndex = tabs.indexWhere((t) => t.id == activeId);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border:
            Border(top: BorderSide(color: SemanticColors.of(context).border)),
        boxShadow: [
          BoxShadow(
            color: SemanticColors.of(context).shadow.withOpacity(0.18),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64 +
              (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0, 3) * 24,
          child: Row(
            children: tabs.asMap().entries.map((e) {
              final tab = e.value;
              final isActive = e.key == activeIndex;
              return Expanded(
                child: Semantics(
                    key: ValueKey('nav-${tab.id}'),
                    button: true,
                    selected: isActive,
                    child: InkWell(
                      onTap: () => onChange(tab.id),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            tab.icon,
                            size: 22,
                            color: isActive
                                ? Theme.of(context).colorScheme.primary
                                : SemanticColors.of(context).textSecondary,
                          ),
                          const SizedBox(height: 4),
                          Flexible(
                            child: Text(tab.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isActive
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: isActive
                                      ? Theme.of(context).colorScheme.primary
                                      : SemanticColors.of(context)
                                          .textSecondary,
                                )),
                          ),
                        ],
                      ),
                    )),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
