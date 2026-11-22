// lib/screens/property_list_screen.dart
// Owner's property portfolio. A building-level statistics table summarises
// the same booking counts shown on each unit card.
//
// Round 10 polish (PL1-PL5):
//   PL1 Theme colors (sem.* + AppColors.*) throughout
//   PL2 Summary header uses AppTheme.primaryGradient
//   PL3 Mini stat tiles use the neutral owner-workspace blue palette;
//       only actual booking status feedback uses semantic status colors.
//   PL4 intl for time formatting ("14:00" via DateFormat)
//   PL5 Active-cleaning banner uses theme warning token

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../models/demo_data.dart';
import '../services/property_store.dart';
import '../theme/app_theme.dart';
import 'property_detail_screen.dart';
import 'property_form_screen.dart';

class PropertyListScreen extends StatelessWidget {
  const PropertyListScreen(
      {super.key,
      required this.bookings,
      this.embedded = false,
      this.connectedProperties,
      this.connectedCounts,
      this.totalCount,
      this.portfolio,
      this.onAddConnected,
      this.onOpenConnected,
      this.onRefreshConnected,
      this.footer});
  final List<DemoBooking> bookings;
  final List<DemoProperty>? connectedProperties;
  final Map<String, List<int>>? connectedCounts;
  final int? totalCount;
  final Map<String, dynamic>? portfolio;
  final VoidCallback? onAddConnected;
  final ValueChanged<DemoProperty>? onOpenConnected;
  final Future<void> Function()? onRefreshConnected;
  final Widget? footer;

  /// When true, skip the inner Scaffold/AppBar so the parent (e.g. owner shell)
  /// can own the AppBar and avoid a duplicate title.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    if (connectedProperties != null) return _buildContents(context, null);
    final app = AppProviders.of(context);
    final store = app.propertyStore;
    return AnimatedBuilder(
      animation: Listenable.merge([store, app.bookingStore]),
      builder: (context, _) => _buildContents(context, store),
    );
  }

  Widget _buildContents(BuildContext context, PropertyStore? store) {
    final properties = connectedProperties ?? store!.properties;
    final currentBookings = connectedProperties != null
        ? bookings
        : AppProviders.of(context).bookingStore.bookings;
    // Group only names, never merge unit records. Pagination stays with the
    // portfolio feed; a group count describes the units currently shown.
    final buildings = <String, List<DemoProperty>>{};
    for (final property in properties) {
      final key =
          property.tower.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      buildings.putIfAbsent(key, () => []).add(property);
    }
    final body = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _buildSummaryHeader(properties),
        const SizedBox(height: 12),
        _PropertyStatisticsTable(
          properties: properties,
          bookings: currentBookings,
          connectedCounts: connectedCounts,
          portfolio: portfolio,
        ),
        for (final units in buildings.values) ...[
          const SizedBox(height: 20),
          Row(children: [
            const Icon(Icons.apartment_outlined, size: 22),
            const SizedBox(width: 8),
            Expanded(
                child: Text(units.first.tower,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700))),
            Text('${units.length} shown',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
          const SizedBox(height: 10),
          for (final property in units) ...[
            _PropertyCard(
              property: property,
              bookings: _bookingsFor(property, currentBookings),
              connectedCounts: connectedCounts?[property.id],
              onTap: () {
                if (onOpenConnected != null) {
                  onOpenConnected!(property);
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PropertyDetailScreen(
                      property: property,
                      bookings: _bookingsFor(property, currentBookings),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ],
        footer ?? const SizedBox.shrink(),
      ],
    );
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My properties'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add property',
            onPressed: () => _openAdd(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: onRefreshConnected == null
          ? body
          : RefreshIndicator(onRefresh: onRefreshConnected!, child: body),
    );
  }

  Future<void> _openAdd(BuildContext context) async {
    if (onAddConnected != null) {
      onAddConnected!();
      return;
    }
    final app = AppProviders.of(context);
    await Navigator.of(context).push<DemoProperty>(MaterialPageRoute(
      builder: (_) => PropertyFormScreen(
        store: app.propertyStore,
        bookings: app.bookingStore.bookings,
      ),
    ));
  }

  List<DemoBooking> _bookingsFor(DemoProperty p, List<DemoBooking> all) {
    return all.where((b) => b.property == p.display).toList()
      ..sort((a, b) => b.scheduledStart.compareTo(a.scheduledStart));
  }

  // PL2: themed summary header
  Widget _buildSummaryHeader(List<DemoProperty> properties) {
    final count =
        portfolio?['property_count'] ?? totalCount ?? properties.length;
    final towers = portfolio?['building_count'] ??
        properties.map((item) => item.tower).toSet().length;
    final area = portfolio?['size_sqft'] ??
        properties.fold<int>(0, (sum, item) => sum + item.sizeSqft);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.apartment, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Portfolio',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '$count properties',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  connectedProperties == null || portfolio != null
                      ? 'Across $towers buildings · $area sqft total'
                      : '${properties.length} properties shown · $towers buildings · $area sqft shown',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Counts are shared by the portfolio table and the individual unit cards so
/// their figures cannot quietly diverge as booking statuses change.
class _BookingCounts {
  const _BookingCounts({
    required this.open,
    required this.done,
    required this.total,
  });

  factory _BookingCounts.from(Iterable<DemoBooking> source) {
    final bookings = source.toList();
    return _BookingCounts(
      open: bookings
          .where((b) =>
              b.status == BookingStatus.pending ||
              b.status == BookingStatus.accepted ||
              b.status == BookingStatus.inProgress)
          .length,
      done: bookings.where((b) => b.status == BookingStatus.completed).length,
      total: bookings.length,
    );
  }

  final int open;
  final int done;
  final int total;
  _BookingCounts plus(_BookingCounts other) => _BookingCounts(
      open: open + other.open,
      done: done + other.done,
      total: total + other.total);
  factory _BookingCounts.server(List<int> row) =>
      _BookingCounts(open: row[0], done: row[1], total: row[2]);
}

class _PropertyStatisticsTable extends StatelessWidget {
  const _PropertyStatisticsTable({
    required this.properties,
    required this.bookings,
    this.connectedCounts,
    this.portfolio,
  });

  final List<DemoProperty> properties;
  final List<DemoBooking> bookings;
  final Map<String, List<int>>? connectedCounts;
  final Map<String, dynamic>? portfolio;

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    final byBuilding = <String, List<DemoBooking>>{};
    for (final property in properties) {
      byBuilding.putIfAbsent(property.tower, () => []).addAll(
            bookings.where((booking) => booking.property == property.display),
          );
    }
    final buildings = byBuilding.keys.toList()..sort();
    final counts = <String, _BookingCounts>{};
    for (final property in properties) {
      final row = connectedCounts == null
          ? _BookingCounts.from(
              bookings.where((b) => b.property == property.display))
          : _BookingCounts.server(connectedCounts![property.id]!);
      counts[property.tower] = (counts[property.tower] ??
              const _BookingCounts(open: 0, done: 0, total: 0))
          .plus(row);
    }
    final shown = counts.values.fold(
        const _BookingCounts(open: 0, done: 0, total: 0), (a, b) => a.plus(b));
    final overall = portfolio == null
        ? shown
        : _BookingCounts(
            open: portfolio!['open'] as int,
            done: portfolio!['done'] as int,
            total: portfolio!['total'] as int);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sem.surface,
        border: Border.all(color: sem.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cleaning statistics',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: sem.textPrimary)),
          const SizedBox(height: 4),
          Text(
              connectedCounts == null
                  ? 'Bookings across your registered properties'
                  : portfolio == null
                      ? 'Bookings for properties shown below'
                      : 'Building rows cover the properties shown below. The total covers all your properties.',
              style: TextStyle(fontSize: 11, color: sem.textSecondary)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: sem.primarySurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _row(context, 'Building', null, heading: true),
          ),
          for (final building in buildings) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              child: _row(
                context,
                building,
                counts[building]!,
                key: Key('property-stats-$building'),
              ),
            ),
            Divider(height: 1, color: sem.border),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 2),
            child: _row(
              context,
              connectedCounts == null || portfolio != null
                  ? 'All properties'
                  : 'Properties shown',
              overall,
              key: const Key('property-stats-total'),
              total: true,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Open: Pending, Accepted or In Progress. Total also includes Declined and Cancelled.',
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: sem.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    _BookingCounts? counts, {
    Key? key,
    bool heading = false,
    bool total = false,
  }) {
    final sem = SemanticColors.of(context);
    final color =
        heading ? Theme.of(context).colorScheme.primary : sem.textPrimary;
    final weight = heading || total ? FontWeight.w700 : FontWeight.w500;
    return Row(
      key: key,
      children: [
        Expanded(
          flex: 4,
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: heading ? 11 : 13,
                  fontWeight: weight,
                  color: color)),
        ),
        _numberCell(
            heading ? 'Open' : '${counts!.open}', 2, color, weight, heading),
        _numberCell(
            heading ? 'Done' : '${counts!.done}', 1, color, weight, heading),
        _numberCell(
            heading ? 'Total' : '${counts!.total}', 1, color, weight, heading),
      ],
    );
  }

  Widget _numberCell(
      String text, int flex, Color color, FontWeight weight, bool heading) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.right,
        maxLines: 1,
        style: TextStyle(
            fontSize: heading ? 11 : 13, fontWeight: weight, color: color),
      ),
    );
  }
}

class _PropertyCard extends StatelessWidget {
  const _PropertyCard(
      {required this.property,
      required this.bookings,
      required this.onTap,
      this.connectedCounts});
  final DemoProperty property;
  final List<DemoBooking> bookings;
  final VoidCallback onTap;
  final List<int>? connectedCounts;

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    final counts = connectedCounts == null
        ? _BookingCounts.from(bookings)
        : _BookingCounts.server(connectedCounts!);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: sem.primarySurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.apartment,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          property.display,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: sem.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${property.bedrooms} bedrooms  ·  ${property.sizeSqft} sqft',
                          style: TextStyle(
                            fontSize: 12,
                            color: sem.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: sem.textTertiary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Aggregate counts are neutral; status colors are reserved for
              // booking-state feedback such as the in-progress notice below.
              Row(
                children: [
                  _miniStat(context, 'Open', '${counts.open}',
                      Icons.pending_actions, sem),
                  const SizedBox(width: 8),
                  _miniStat(
                      context, 'Done', '${counts.done}', Icons.task_alt, sem),
                  const SizedBox(width: 8),
                  _miniStat(context, 'Total', '${counts.total}',
                      Icons.receipt_long_outlined, sem,
                      emphasized: true),
                ],
              ),
              if (counts.total == 0) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: sem.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'No bookings yet. Schedule a cleaning to get started.',
                        style:
                            TextStyle(fontSize: 12, color: sem.textSecondary),
                      ),
                    ),
                  ],
                ),
              ] else if (bookings.isNotEmpty &&
                  bookings.first.status == BookingStatus.inProgress) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                // PL5: themed active-cleaning banner
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.warning,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Cleaning in progress · ends ${_formatTime(bookings.first.scheduledEnd)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.warning,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(BuildContext context, String label, String value,
      IconData icon, SemanticColors sem,
      {bool emphasized = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: emphasized ? sem.surface : sem.primarySurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: sem.primaryBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    size: 13, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: sem.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: sem.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // PL4: intl time format
  String _formatTime(DateTime d) => DateFormat('HH:mm').format(d);
}
