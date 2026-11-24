// lib/screens/provider_profile_screen.dart
// Full provider profile. Tappable from Provider Browse, Provider Inbox,
// and Active Job Detail (the "View profile" buttons all go here).
//
// Round 10 polish (PP1-PP7):
//   PP1 Theme colors throughout (sem.* + AppColors.*) instead of hardcoded hex
//   PP2 AppColors.success for "Online" pill
//   PP3 Score bars use sem.surfaceAlt background + sem.textPrimary labels
//   PP4 Stat tiles use AppColors.success / warning / primary
//   PP5 Service chip uses AppColors.primarySurface + primaryBorder
//   PP6 Contact row uses sem tokens
//   PP7 Phone number respects provider.showPhoneToOwners (Round 7 privacy)

import 'package:flutter/material.dart';
import '../models/demo_data.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';
import '../widgets/provider_working_hours_summary.dart';
import '../widgets/profile_sign_out_confirmation.dart';
import '../services/backend/provider_profile_snapshot.dart';

class ProviderProfileScreen extends StatelessWidget {
  const ProviderProfileScreen(
      {super.key,
      required this.provider,
      this.heroColor,
      this.onSelect,
      this.snapshot,
      this.onEdit,
      this.onRefresh,
      this.onManageAvailability,
      this.onSettings,
      this.refreshNotice,
      this.bottomNavigationBar});
  final DemoProvider provider;
  final Color? heroColor;
  final VoidCallback? onSelect;
  final ProviderProfileSnapshot? snapshot;
  final VoidCallback? onEdit, onRefresh, onManageAvailability;
  final Widget? bottomNavigationBar;
  final ValueChanged<String>? onSettings;
  final Widget? refreshNotice;
  bool get connected => snapshot != null;

  @override
  Widget build(BuildContext context) {
    final heroColorFinal = heroColor ??
        (Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF244966)
            : AppColors.primary);
    return Scaffold(
      bottomNavigationBar: bottomNavigationBar,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: (connected ? 160 : 200) +
                (MediaQuery.textScalerOf(context).scale(1) - 1) *
                    (connected ? 180 : 260),
            pinned: true,
            backgroundColor: heroColorFinal,
            foregroundColor: Colors.white,
            actions: connected
                ? [
                    IconButton(
                        onPressed: onRefresh,
                        tooltip: 'Refresh profile',
                        icon: const Icon(Icons.refresh)),
                  ]
                : null,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: Theme.of(context).brightness == Brightness.dark &&
                            heroColor == null
                        ? AppTheme.darkHeroGradient.colors
                        : [heroColorFinal, heroColorFinal.withOpacity(0.7)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: connected
                        ? const EdgeInsets.fromLTRB(16, 64, 16, 12)
                        : const EdgeInsets.fromLTRB(20, 16, 20, 56),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: connected ? 48 : 56,
                              height: connected ? 48 : 56,
                              decoration: BoxDecoration(
                                color: connected
                                    ? const [
                                        AppColors.primary,
                                        AppColors.secondary,
                                        Color(0xFF6366F1),
                                        Color(0xFFFB8C00),
                                        Color(0xFFEF4444),
                                        Color(0xFF8B5CF6)
                                      ][snapshot!.avatar]
                                    : Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.4),
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  _initials(provider.name),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 22,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    provider.name.isEmpty && connected
                                        ? 'Your provider profile'
                                        : provider.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Cleaning Service Provider',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.85),
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (connected) ...[
                                    const SizedBox(height: 6),
                                    Text(snapshot!.approvalLabel,
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                  ],
                                ],
                              ),
                            ),
                            // PP2: quiet online indicator shared with Inbox
                            if (!connected)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.14),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.pill),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.circle,
                                        color: connected
                                            ? Colors.white70
                                            : AppColors.onlineDot,
                                        size: 7),
                                    const SizedBox(width: 6),
                                    Text(
                                        connected
                                            ? snapshot!.approvalLabel
                                            : 'Online',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        if (!connected) ...[
                          const Spacer(),
                          Row(
                            children: [
                              _heroStat(
                                label: 'Rating',
                                value: connected
                                    ? (snapshot!.rating?.toStringAsFixed(1) ??
                                        '—')
                                    : provider.rating.toStringAsFixed(1),
                                sub: '/ 5.0',
                              ),
                              const SizedBox(width: 12),
                              _heroStat(
                                label: connected ? 'Jobs done' : 'Distance',
                                value: connected
                                    ? '${snapshot!.completed}'
                                    : provider.distanceKm.toStringAsFixed(1),
                                sub: connected ? 'completed' : 'km away',
                              ),
                              const SizedBox(width: 12),
                              _heroStat(
                                label: provider.hasRankingBreakdown
                                    ? 'Match'
                                    : 'Rate',
                                value: connected
                                    ? (snapshot!.hourly != null
                                        ? 'RM ${snapshot!.hourly!.toStringAsFixed(2)}'
                                        : snapshot!.daily != null
                                            ? 'RM ${snapshot!.daily!.toStringAsFixed(2)}'
                                            : '—')
                                    : provider.hasRankingBreakdown
                                        ? '${(provider.score * 100).round()}%'
                                        : 'RM ${provider.hourlyRate.toStringAsFixed(0)}',
                                sub: connected
                                    ? (snapshot!.hourly != null
                                        ? '/ hour'
                                        : '/ 8 hours')
                                    : provider.hasRankingBreakdown
                                        ? 'request score'
                                        : '/ hour',
                                highlight: provider.hasRankingBreakdown,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (refreshNotice != null)
            SliverToBoxAdapter(
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: refreshNotice)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (connected) ...[
                    _buildProfileActions(),
                    const SizedBox(height: 16),
                  ],
                  connected
                      ? _buildServiceProfileCard(context)
                      : _buildMatchCard(context),
                  const SizedBox(height: 16),
                  _buildStatsCard(context),
                  const SizedBox(height: 16),
                  if (!connected) ...[
                    _buildServicesCard(context),
                    const SizedBox(height: 16),
                  ],
                  _buildWorkloadCard(context),
                  const SizedBox(height: 16),
                  _buildContactCard(context),
                  if (!connected) const SizedBox(height: 24),
                  if (!connected)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: connected
                                ? onManageAvailability
                                : () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Messaging opens after a booking is accepted.'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                            icon: Icon(
                                connected
                                    ? Icons.schedule
                                    : Icons.chat_bubble_outline,
                                size: 16),
                            label: Text(connected ? 'Availability' : 'Message'),
                          ),
                        ),
                        if (onSelect != null || connected) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: connected ? onEdit : onSelect,
                              icon: Icon(
                                  connected ? Icons.edit_outlined : Icons.check,
                                  size: 16),
                              label: Text(connected
                                  ? 'Edit profile'
                                  : 'Select provider'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  if (onSettings != null) ...[
                    if (!connected) ...[
                      const SizedBox(height: 24),
                      const SectionHeader(title: 'Personal details'),
                      Card(
                          child: ListTile(
                              leading: const Icon(Icons.person_outline),
                              title: const Text('Edit profile'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => onSettings!('edit_profile'))),
                    ],
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Preferences'),
                    Card(
                        child: Column(children: [
                      ListTile(
                          leading: const Icon(Icons.notifications_outlined),
                          title: const Text('Notifications'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => onSettings!('notifications')),
                      const Divider(height: 1),
                      ListTile(
                          leading: const Icon(Icons.brightness_auto_outlined),
                          title: const Text('Appearance'),
                          subtitle: const Text('System, Light or Dark'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => onSettings!('appearance')),
                    ])),
                    const SizedBox(height: 16),
                    const SectionHeader(title: 'Activity & reports'),
                    Card(
                        child: ListTile(
                            leading: const Icon(Icons.insights_outlined),
                            title: const Text('My statistics'),
                            subtitle:
                                const Text('Completed jobs and work trends'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => onSettings!('stats'))),
                    const SizedBox(height: 16),
                    const SectionHeader(title: 'Account & help'),
                    Card(
                        child: Column(children: [
                      ListTile(
                          leading: const Icon(Icons.shield_outlined),
                          title: const Text('Privacy & security'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => onSettings!('privacy')),
                      const Divider(height: 1),
                      ListTile(
                          leading: const Icon(Icons.help_outline),
                          title: const Text('About & help'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => onSettings!('about')),
                      const Divider(height: 1),
                      ListTile(
                          leading: Icon(Icons.logout,
                              color: Theme.of(context).colorScheme.error),
                          title: Text('Sign out',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                          onTap: () => confirmProfileSignOut(
                                context,
                                () => onSettings!('sign-out'),
                              )),
                    ])),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileDetailRow(
      BuildContext context, String label, String value) {
    final sem = SemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            flex: 2,
            child: Text(label, style: TextStyle(color: sem.textSecondary))),
        const SizedBox(width: 12),
        Expanded(
            flex: 3,
            child: Text(value,
                style: TextStyle(
                    color: sem.textPrimary, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _buildServiceProfileCard(BuildContext context) {
    final sem = SemanticColors.of(context);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Service profile'),
                const SizedBox(height: 10),
                Text(
                    snapshot!.bio.isEmpty
                        ? 'No introduction added yet.'
                        : snapshot!.bio,
                    style: TextStyle(color: sem.textPrimary)),
                const SizedBox(height: 10),
                _buildProfileDetailRow(context, 'Service area', snapshot!.area),
                _buildProfileDetailRow(
                    context,
                    'Hourly rate',
                    snapshot!.hourly == null
                        ? 'Not offered'
                        : 'RM ${snapshot!.hourly!.toStringAsFixed(2)} / hour'),
                _buildProfileDetailRow(
                    context,
                    'Daily rate',
                    snapshot!.daily == null
                        ? 'Not offered'
                        : 'RM ${snapshot!.daily!.toStringAsFixed(2)} / 8 hours'),
                const Divider(height: 24),
                Text('Services offered',
                    style: TextStyle(color: sem.textSecondary)),
                const SizedBox(height: 8),
                if (provider.serviceTypes.isEmpty)
                  Text('No services selected yet.',
                      style: TextStyle(color: sem.textSecondary)),
                Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: provider.serviceTypes
                        .map((service) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                  color: sem.primarySurface,
                                  borderRadius: BorderRadius.circular(6)),
                              child: Text(_serviceLabel(service),
                                  style: TextStyle(
                                      color: sem.textPrimary, fontSize: 12)),
                            ))
                        .toList()),
              ],
            )));
  }

  Widget _buildProfileActions() => Row(children: [
        Expanded(
            child: FilledButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit profile'))),
        const SizedBox(width: 8),
        Expanded(
            child: OutlinedButton.icon(
                onPressed: onManageAvailability,
                icon: const Icon(Icons.schedule, size: 16),
                label: const Text('Availability'))),
      ]);

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  Widget _heroStat({
    required String label,
    required String value,
    required String sub,
    bool highlight = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: highlight ? Colors.white : Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: highlight
                    ? SemanticColors.lightTokens.textSecondary
                    : Colors.white70,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: highlight ? AppColors.primary : Colors.white,
                  ),
                )),
            Text(
              sub,
              style: TextStyle(
                fontSize: 10,
                color: highlight
                    ? SemanticColors.lightTokens.textSecondary
                    : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchCard(BuildContext context) {
    final sem = SemanticColors.of(context);
    if (connected)
      return Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'About your service'),
                    const SizedBox(height: 12),
                    Text(
                        snapshot!.bio.isEmpty
                            ? 'No introduction added yet.'
                            : snapshot!.bio,
                        style: TextStyle(color: sem.textPrimary)),
                    const SizedBox(height: 12),
                    Text('Service area: ${snapshot!.area}',
                        style: TextStyle(color: sem.textSecondary)),
                    const SizedBox(height: 8),
                    Text(
                        'Hourly: ${snapshot!.hourly == null ? 'Not offered' : 'RM ${snapshot!.hourly!.toStringAsFixed(2)} / hour'}',
                        style: TextStyle(color: sem.textSecondary)),
                    Text(
                        'Daily: ${snapshot!.daily == null ? 'Not offered' : 'RM ${snapshot!.daily!.toStringAsFixed(2)} / 8 hours'}',
                        style: TextStyle(color: sem.textSecondary)),
                  ])));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Two-stage match analysis',
              subtitle: provider.hasRankingBreakdown
                  ? 'Mandatory eligibility first, then equal-weight ranking'
                  : 'A score is calculated for a specific service request',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.positive.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.positive.withOpacity(0.24),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_outlined,
                    size: 16,
                    color: AppColors.positive,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      provider.hasRankingBreakdown
                          ? 'Passed service, full-interval availability, rental-window, and conflict checks.'
                          : 'Eligibility is checked when an owner submits a service request.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF7DD6B5)
                            : AppColors.positive,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (provider.hasRankingBreakdown) ...[
              const SizedBox(height: 12),
              _scoreBar(
                'Distance',
                provider.distanceSuitability,
                '1/3 weight',
                color: Theme.of(context).colorScheme.primary,
                sem: sem,
              ),
              const SizedBox(height: 8),
              _scoreBar(
                'Rating',
                provider.ratingSuitability,
                '1/3 weight',
                color: Theme.of(context).colorScheme.secondary,
                sem: sem,
              ),
              const SizedBox(height: 8),
              _scoreBar(
                'Workload',
                provider.workloadSuitability,
                '1/3 weight',
                color: Theme.of(context).colorScheme.primary,
                sem: sem,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // PP3: themed score bar
  Widget _scoreBar(
    String label,
    double value,
    String weight, {
    required Color color,
    required SemanticColors sem,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: sem.textPrimary),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value.clamp(0, 1),
              minHeight: 8,
              backgroundColor: sem.surfaceAlt,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: Text(
            weight,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: sem.textSecondary),
          ),
        ),
      ],
    );
  }

  // PP4: themed stat tiles
  Widget _buildStatsCard(BuildContext context) {
    final sem = SemanticColors.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: connected ? 'Work summary' : 'Lifetime stats'),
            const SizedBox(height: 12),
            Row(
              children: [
                _statTile(
                    connected ? '${snapshot!.completed}' : '128',
                    'Jobs done',
                    Icons.check_circle_outline,
                    Theme.of(context).colorScheme.primary,
                    sem),
                const SizedBox(width: 8),
                _statTile(
                    connected
                        ? (snapshot!.rating?.toStringAsFixed(1) ?? '—')
                        : '4.8',
                    'Avg rating',
                    Icons.star,
                    Theme.of(context).colorScheme.secondary,
                    sem),
                if (!connected) ...[
                  const SizedBox(width: 8),
                  _statTile('96%', 'On time', Icons.access_time,
                      Theme.of(context).colorScheme.primary, sem),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(
    String v,
    String l,
    IconData icon,
    Color color,
    SemanticColors sem,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 6),
            Text(
              v,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: sem.textPrimary,
              ),
            ),
            Text(l, style: TextStyle(fontSize: 11, color: sem.textSecondary)),
          ],
        ),
      ),
    );
  }

  // PP5: themed service chip
  Widget _buildServicesCard(BuildContext context) {
    final sem = SemanticColors.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
                title: 'Services offered',
                subtitle: connected
                    ? 'Saved cleaning capabilities'
                    : 'Tap to filter jobs'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: provider.serviceTypes.map((s) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: sem.primarySurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: sem.primaryBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cleaning_services,
                        size: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                          child: Text(
                        _serviceLabel(s),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: sem.textPrimary,
                        ),
                      )),
                    ],
                  ),
                );
              }).toList(),
            ),
            if (connected && provider.serviceTypes.isEmpty)
              const Text('No services selected yet.'),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkloadCard(BuildContext context) {
    final sem = SemanticColors.of(context);
    if (connected)
      return Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Current workload'),
                    const SizedBox(height: 12),
                    Text(
                        '${snapshot!.active} active job${snapshot!.active == 1 ? '' : 's'} · next 7 days',
                        style: TextStyle(color: sem.textPrimary)),
                    const SizedBox(height: 8),
                    Text('Working hours (MYT)',
                        style: TextStyle(color: sem.textSecondary)),
                    const SizedBox(height: 8),
                    ProviderWorkingHoursSummary(
                        key: ValueKey(snapshot!.id), slots: snapshot!.slots),
                  ])));
    // PP4: themed workload color
    final color = provider.workload == 'Low'
        ? AppColors.success
        : provider.workload == 'Medium'
            ? AppColors.warning
            : AppColors.error;
    final percent = provider.workload == 'Low'
        ? 0.3
        : provider.workload == 'Medium'
            ? 0.6
            : 0.9;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Current workload',
              action: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  provider.workload,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent,
                minHeight: 10,
                backgroundColor: sem.surfaceAlt,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              provider.hasRankingBreakdown
                  ? '${provider.activeBookingCount} Accepted or In Progress '
                      'booking${provider.activeBookingCount == 1 ? '' : 's'} '
                      'overlap the seven-day workload window.'
                  : provider.workload == 'Low'
                      ? 'Plenty of room. Will accept new jobs quickly.'
                      : provider.workload == 'Medium'
                          ? 'Some jobs in progress. New jobs may take 1-2 days.'
                          : 'Heavily booked. Best for non-urgent jobs.',
              style: TextStyle(
                fontSize: 12,
                color: sem.textSecondary,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // PP6 + PP7: themed contact rows + phone privacy
  Widget _buildContactCard(BuildContext context) {
    if (connected)
      return Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Contact & privacy'),
                    const SizedBox(height: 12),
                    _contactRow(Icons.phone, 'Your phone',
                        snapshot!.contact ?? 'Not provided'),
                    const Divider(height: 16),
                    _contactRow(Icons.email, 'Sign-in email', snapshot!.email),
                    const SizedBox(height: 12),
                    Text(snapshot!.sharePhone
                        ? 'Phone shared only with owners of accepted or ongoing bookings.'
                        : 'Phone hidden from owners.'),
                  ])));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Contact'),
            const SizedBox(height: 12),
            // PP7: only show phone if provider opted in
            if (provider.showPhoneToOwners)
              _contactRow(Icons.phone, 'Call', provider.phone)
            else
              _contactRow(
                Icons.lock_outline,
                'Call',
                'Hidden by provider — message instead',
              ),
            const Divider(height: 16),
            _contactRow(Icons.email, 'Email', provider.email),
            const Divider(height: 16),
            if (provider.showPhoneToOwners)
              _contactRow(Icons.chat, 'WhatsApp', provider.phone)
            else
              _contactRow(
                Icons.chat_bubble_outline,
                'WhatsApp',
                'Hidden by provider — message instead',
              ),
          ],
        ),
      ),
    );
  }

  Widget _contactRow(IconData icon, String label, String value) {
    return Builder(builder: (ctx) {
      final sem = SemanticColors.of(ctx);
      return Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: sem.primarySurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                Icon(icon, size: 16, color: Theme.of(ctx).colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: sem.textSecondary),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: sem.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (!connected)
            IconButton(
              icon: Icon(
                Icons.arrow_forward_ios,
                size: 12,
                color: sem.textTertiary,
              ),
              onPressed: () {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text('Use the contact details in your phone app.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
        ],
      );
    });
  }

  String _serviceLabel(String id) {
    const map = {
      'standard': 'Standard cleaning',
      'deep': 'Deep cleaning',
      'window': 'Window cleaning',
      'move-in': 'Move-in cleaning',
      'move-out': 'Move-out cleaning',
    };
    return map[id] ?? id;
  }
}
