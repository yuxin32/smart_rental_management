// lib/widgets/provider_card.dart
import 'package:flutter/material.dart';
import '../models/demo_data.dart';
import '../theme/app_theme.dart';

class ProviderCard extends StatelessWidget {
  const ProviderCard({
    super.key,
    required this.provider,
    required this.rank,
    this.onViewProfile,
    this.onAssign,
    this.actionLabel = 'Assign',
  });
  final DemoProvider provider;
  final int rank;
  final VoidCallback? onViewProfile;
  final VoidCallback? onAssign;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: sem.primarySurface,
                  child: Text(
                    '#$rank',
                    style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Eligible for the full requested interval',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF7DD6B5)
                              : const Color(0xFF2E7D32),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: sem.primarySurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${(provider.score * 100).round()}%',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Tag(
                    icon: Icons.star,
                    label: provider.rating.toStringAsFixed(1),
                    color: const Color(0xFFF59E0B)),
                _Tag(
                    icon: Icons.location_on,
                    label: '${provider.distanceKm.toStringAsFixed(1)} km',
                    color: const Color(0xFF10B981)),
                _Tag(
                  icon: Icons.work,
                  label:
                      '${provider.activeBookingCount} active job${provider.activeBookingCount == 1 ? '' : 's'}',
                  color: const Color(0xFF6366F1),
                ),
                for (final t in provider.serviceTypes)
                  _Tag(
                      icon: Icons.cleaning_services,
                      label: t,
                      color: const Color(0xFF8B5CF6)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onViewProfile,
                    icon: const Icon(Icons.info_outline, size: 16),
                    label: const Text('View profile'),
                  ),
                ),
                if (onAssign != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onAssign,
                      icon: const Icon(Icons.check, size: 16),
                      label: Text(actionLabel),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final displayColor = Theme.of(context).brightness == Brightness.dark
        ? Color.lerp(color, Colors.white, 0.35)!
        : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: displayColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: displayColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: displayColor),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: displayColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
