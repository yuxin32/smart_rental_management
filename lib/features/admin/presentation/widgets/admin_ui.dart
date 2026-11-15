import 'package:flutter/material.dart';

import '../../../../core/auth/app_logout_button.dart';
import '../../../../core/theme/app_theme.dart';

class AdminStatusPill extends StatelessWidget {
  const AdminStatusPill({
    required this.label,
    required this.foregroundColor,
    required this.backgroundColor,
    this.dot = true,
    super.key,
  });

  final String label;
  final Color foregroundColor;
  final Color backgroundColor;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: foregroundColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: foregroundColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class AdminScreenTitle extends StatelessWidget {
  const AdminScreenTitle({
    required this.title,
    this.subtitle,
    this.action,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.heading,
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(color: AppColors.body, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[action!, const SizedBox(width: 8)],
          const AppLogoutButton(
            foregroundColor: AppColors.primary,
            backgroundColor: Color(0xFFE6EBFF),
          ),
        ],
      ),
    );
  }
}

class AdminBackAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AdminBackAppBar({required this.title, this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 21),
        color: AppColors.heading,
      ),
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.heading,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: const TextStyle(color: AppColors.body, fontSize: 12),
            ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(68);
}

class AdminCard extends StatelessWidget {
  const AdminCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = Colors.white,
    this.radius = 22,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return card;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: card,
    );
  }
}

class AdminIconBox extends StatelessWidget {
  const AdminIconBox({
    required this.icon,
    required this.color,
    this.backgroundColor,
    super.key,
  });

  final IconData icon;
  final Color color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: backgroundColor ?? color.withAlpha(24),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }
}

class AdminMetricCard extends StatelessWidget {
  const AdminMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      padding: const EdgeInsets.all(14),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminIconBox(icon: icon, color: color),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.heading,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.body, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

Color adminStatusColor(String status) {
  return switch (status.toLowerCase()) {
    'active' ||
    'account active' ||
    'verified' ||
    'resolved' ||
    'published' => AppColors.success,
    'pending' ||
    'new' ||
    'draft' ||
    'ready to invite' ||
    'review required' ||
    'review needed' ||
    'resubmission needed' ||
    'assign unit' ||
    'awaiting account setup' ||
    'awaiting documents' => const Color(0xFFE8953E),
    'in progress' ||
    'invitation sent' ||
    'account created' ||
    'documents submitted' ||
    'unit assignment needed' => AppColors.primary,
    _ => AppColors.body,
  };
}

Color adminStatusBackground(String status) {
  return switch (status.toLowerCase()) {
    'active' ||
    'account active' ||
    'verified' ||
    'resolved' ||
    'published' => const Color(0xFFE2F7E9),
    'pending' ||
    'new' ||
    'draft' ||
    'ready to invite' ||
    'review required' ||
    'review needed' ||
    'resubmission needed' ||
    'assign unit' ||
    'awaiting account setup' ||
    'awaiting documents' => const Color(0xFFFFF0D7),
    'in progress' ||
    'invitation sent' ||
    'account created' ||
    'documents submitted' ||
    'unit assignment needed' => const Color(0xFFE6EBFF),
    _ => const Color(0xFFF0F2F5),
  };
}
