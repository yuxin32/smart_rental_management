import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import '../models/demo_data.dart';
import '../widgets/figma_ui.dart';

/// Figma 192:641, with local-store values instead of prototype counts.
class FigmaOwnerDashboard extends StatelessWidget {
  const FigmaOwnerDashboard(
      {super.key,
      required this.bookings,
      required this.onRequest,
      required this.onNavigate,
      required this.onBooking});
  final List<DemoBooking> bookings;
  final VoidCallback onRequest;
  final ValueChanged<String> onNavigate;
  final ValueChanged<DemoBooking> onBooking;

  Widget _action(
          String title, String subtitle, String accent, VoidCallback onTap) =>
      FigmaSurface(
          asset: 'dashboard-action-card',
          child: Material(
              color: Colors.transparent,
              child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(children: [
                    Positioned(
                        left: 0,
                        top: 12,
                        width: 4,
                        height: 52,
                        child: SvgPicture.asset(
                            'assets/figma/dashboard-$accent-accent.svg',
                            excludeFromSemantics: true)),
                    Container(
                        constraints: const BoxConstraints(minHeight: 76),
                        padding: const EdgeInsets.fromLTRB(16, 17, 16, 14),
                        width: double.infinity,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: FigmaUi.text(13, bold: true)),
                              const SizedBox(height: 9),
                              Text(subtitle,
                                  style:
                                      FigmaUi.text(10, color: FigmaUi.muted)),
                            ])),
                  ]))));

  @override
  Widget build(BuildContext context) {
    final open = bookings.where((b) => !b.status.isTerminal).toList();
    final current =
        open.where((b) => b.status == BookingStatus.pending).firstOrNull ??
            open.firstOrNull;
    final active = bookings.where((b) => b.status.blocksProviderSlot).length;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'morning'
        : hour < 18
            ? 'afternoon'
            : 'evening';
    return FigmaSurface(
        asset: 'dashboard-background',
        child: SizedBox.expand(
            child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(children: [
                              Expanded(
                                  child: Text('Good $greeting, Owner',
                                      style: FigmaUi.text(17, bold: true))),
                              const SizedBox(width: 8),
                              FigmaSurface(
                                  asset: 'dashboard-active-badge',
                                  child: SizedBox(
                                      width: 72,
                                      height: 24,
                                      child: Center(
                                          child: Text('$active active',
                                              style: FigmaUi.text(10,
                                                  bold: true,
                                                  color: FigmaUi.blue))))),
                            ])),
                        const SizedBox(height: 18),
                        _action(
                            current?.property ?? DemoProperty.all.first.display,
                            'Manage rental unit',
                            'cyan',
                            () => onNavigate('properties')),
                        const SizedBox(height: 10),
                        Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: FigmaButton(
                                label: 'Request Cleaning Service',
                                variant: 'dashboard',
                                onPressed: onRequest)),
                        const SizedBox(height: 8),
                        Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text('Current booking',
                                style: FigmaUi.text(13, bold: true))),
                        const SizedBox(height: 10),
                        FigmaSurface(
                            asset: 'dashboard-booking-card',
                            child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                    onTap: current == null
                                        ? onRequest
                                        : () => onBooking(current),
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                        constraints: const BoxConstraints(
                                            minHeight: 108),
                                        padding: const EdgeInsets.all(16),
                                        child: current == null
                                            ? Text(
                                                'No active booking. Request a cleaning service to get started.',
                                                style: FigmaUi.text(12))
                                            : Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                    Row(children: [
                                                      Expanded(
                                                          child: Text(
                                                              current
                                                                  .serviceType,
                                                              style: FigmaUi.text(
                                                                  14,
                                                                  bold: true))),
                                                      const SizedBox(width: 8),
                                                      if (current.status ==
                                                          BookingStatus.pending)
                                                        FigmaSurface(
                                                            asset:
                                                                'dashboard-pending-badge',
                                                            child: SizedBox(
                                                                width: 70,
                                                                height: 24,
                                                                child: Center(
                                                                    child: Text(current.status.label,
                                                                        style: FigmaUi.text(
                                                                            10,
                                                                            bold:
                                                                                true,
                                                                            color: const Color(
                                                                                0xFF9A6D00))))))
                                                      else
                                                        Text(current.status.label,
                                                            style: FigmaUi.text(
                                                                10,
                                                                bold: true,
                                                                color: current
                                                                    .status
                                                                    .color)),
                                                    ]),
                                                    const SizedBox(height: 7),
                                                    Text(
                                                        '${DateFormat('d MMM yyyy, HH:mm').format(current.scheduledStart)}–${DateFormat('HH:mm').format(current.scheduledEnd)}',
                                                        style: FigmaUi.text(11,
                                                            color: const Color(
                                                                0xFF53627A))),
                                                    const SizedBox(height: 7),
                                                    Text(
                                                        'Provider: ${current.providerName ?? 'Not selected'}',
                                                        style: FigmaUi.text(11,
                                                            color: const Color(
                                                                0xFF53627A))),
                                                  ]))))),
                        const SizedBox(height: 20),
                        Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text('Quick actions',
                                style: FigmaUi.text(13, bold: true))),
                        const SizedBox(height: 11),
                        _action('Find Providers', 'Browse profiles and ratings',
                            'blue', () => onNavigate('browse')),
                        const SizedBox(height: 8),
                        _action('Booking History', 'Track status and payments',
                            'purple', () => onNavigate('bookings')),
                        const SizedBox(height: 8),
                        _action('Messages', 'Open booking conversations',
                            'cyan', () => onNavigate('messages')),
                      ]))),
        )));
  }
}
