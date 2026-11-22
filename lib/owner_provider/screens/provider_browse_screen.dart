import 'package:flutter/material.dart';

import '../main.dart';
import '../models/demo_data.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';

// General browsing never implies that a provider is eligible for a specific
// booking. Request-specific hard filtering and ranking live in results screen.
enum _DirectorySort {
  rating('Top rated'),
  price('Lowest hourly rate'),
  name('Name');

  const _DirectorySort(this.label);
  final String label;
}

class ProviderBrowseScreen extends StatefulWidget {
  const ProviderBrowseScreen({
    super.key,
    this.onViewProfile,
    this.onAssign,
    this.onCreateRequest,
  });

  final void Function(DemoProvider)? onViewProfile;
  final void Function(DemoProvider)? onAssign;
  final VoidCallback? onCreateRequest;

  @override
  State<ProviderBrowseScreen> createState() => _ProviderBrowseScreenState();
}

class _ProviderBrowseScreenState extends State<ProviderBrowseScreen> {
  _DirectorySort _sort = _DirectorySort.rating;
  String _serviceType = 'all';

  @override
  Widget build(BuildContext context) {
    final app = AppProviders.of(context);
    return AnimatedBuilder(
      animation: app.providerStore,
      builder: (context, _) => _buildContent(context, app),
    );
  }

  Widget _buildContent(BuildContext context, AppProviders app) {
    final sem = SemanticColors.of(context);
    final visible = app.providerStore.providers
        .where((p) =>
            _serviceType == 'all' || p.serviceTypes.contains(_serviceType))
        .toList();
    switch (_sort) {
      case _DirectorySort.rating:
        visible.sort((a, b) {
          final byRating = b.rating.compareTo(a.rating);
          return byRating != 0 ? byRating : a.name.compareTo(b.name);
        });
      case _DirectorySort.price:
        visible.sort((a, b) {
          final byPrice = a.hourlyRate.compareTo(b.hourlyRate);
          return byPrice != 0 ? byPrice : a.name.compareTo(b.name);
        });
      case _DirectorySort.name:
        visible.sort((a, b) => a.name.compareTo(b.name));
    }

    return ListView(
      key: const Key('provider-directory'),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: sem.primarySurface,
            border: Border.all(color: sem.primaryBorder),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Find a cleaning provider',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: sem.textPrimary,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Compare services, ratings and rates. Choose a time when you make a request.',
                style: TextStyle(
                    fontSize: 13, height: 1.4, color: sem.textSecondary),
              ),
              if (widget.onCreateRequest != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: widget.onCreateRequest,
                    icon: const Icon(Icons.event_available_outlined),
                    label: const Text('Find available providers'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Service type',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: sem.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        _serviceFilters(sem),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: Text(
                '${visible.length} provider${visible.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: sem.textPrimary,
                ),
              ),
            ),
            PopupMenuButton<_DirectorySort>(
              key: const Key('directory-sort'),
              initialValue: _sort,
              position: PopupMenuPosition.under,
              onSelected: (value) => setState(() => _sort = value),
              itemBuilder: (_) => [
                for (final choice in _DirectorySort.values)
                  PopupMenuItem(value: choice, child: Text(choice.label)),
              ],
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: sem.surface,
                  border: Border.all(color: sem.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sort, size: 18, color: sem.textSecondary),
                    const SizedBox(width: 5),
                    Text(
                      _sort.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: sem.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_drop_down,
                        size: 18, color: sem.textSecondary),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Profiles shown here are not yet checked for your date or rental unit.',
          style: TextStyle(fontSize: 12, color: sem.textSecondary),
        ),
        const SizedBox(height: 14),
        if (visible.isEmpty)
          EmptyState(
            icon: Icons.person_search_outlined,
            title: 'No provider for this service',
            subtitle: 'Try another service type.',
            action: OutlinedButton(
              onPressed: () => setState(() => _serviceType = 'all'),
              child: const Text('Show all providers'),
            ),
          )
        else
          for (final provider in visible) ...[
            _DirectoryProviderCard(
              provider: provider,
              onViewProfile: () => _handleViewProfile(context, provider),
              onAssign: widget.onAssign == null
                  ? null
                  : () => widget.onAssign!(provider),
            ),
            const SizedBox(height: 12),
          ],
        Text(
          'Compare services, rates and areas. Availability is checked for your selected request.',
          style: TextStyle(fontSize: 11, height: 1.4, color: sem.textSecondary),
        ),
      ],
    );
  }

  Widget _serviceFilters(SemanticColors sem) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedColor =
        isDark ? AppColors.primaryLighter : AppColors.primary;
    final options = <(String, String)>[
      ('all', 'All services'),
      for (final service in ServiceTypeOption.all)
        (service.id, service.label),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (id, label) in options)
          ChoiceChip(
            key: Key('service-filter-$id'),
            label: Text(label),
            selected: _serviceType == id,
            onSelected: (_) => setState(() => _serviceType = id),
            selectedColor: selectedColor,
            backgroundColor: sem.surface,
            side: BorderSide(
              color: _serviceType == id ? selectedColor : sem.border,
            ),
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _serviceType == id
                  ? (isDark ? AppColors.primaryDark : Colors.white)
                  : sem.textPrimary,
            ),
            showCheckmark: false,
          ),
      ],
    );
  }

  void _handleViewProfile(BuildContext context, DemoProvider provider) {
    if (widget.onViewProfile != null) {
      widget.onViewProfile!(provider);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('View ${provider.name} profile')),
      );
    }
  }
}

class _DirectoryProviderCard extends StatelessWidget {
  const _DirectoryProviderCard({
    required this.provider,
    required this.onViewProfile,
    this.onAssign,
  });

  final DemoProvider provider;
  final VoidCallback onViewProfile;
  final VoidCallback? onAssign;

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: sem.primarySurface,
                  child: Icon(Icons.person_outline,
                      color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    provider.name,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: sem.textPrimary,
                    ),
                  ),
                ),
                Text(
                  'RM ${provider.hourlyRate.toStringAsFixed(0)}/hr',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: sem.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.star_rounded,
                    size: 20, color: Color(0xFFE59A24)),
                const SizedBox(width: 4),
                Text(
                  '${provider.rating.toStringAsFixed(1)} / 5',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: sem.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Services offered',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: sem.textSecondary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              provider.serviceTypes.map(_serviceName).join(' · '),
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: sem.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onViewProfile,
                icon: const Icon(Icons.person_outline, size: 18),
                label: const Text('View profile'),
              ),
            ),
            if (onAssign != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onAssign,
                  child: const Text('Select provider'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _serviceName(String id) {
    for (final service in ServiceTypeOption.all) {
      if (service.id == id) return service.label;
    }
    return id;
  }
}
