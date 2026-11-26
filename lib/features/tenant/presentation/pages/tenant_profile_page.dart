import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../admin/data/tenant_lifecycle_service.dart';
import '../widgets/tenant_ui.dart';

class TenantProfilePage extends StatefulWidget {
  const TenantProfilePage({super.key});

  @override
  State<TenantProfilePage> createState() => _TenantProfilePageState();
}

class _TenantProfilePageState extends State<TenantProfilePage> {
  late Future<TenantRentalDetails?> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  void _loadDetails() {
    _detailsFuture = TenantLifecycleService.fetchCurrentTenantDetails();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: const TenantBackAppBar(title: 'Rental Details'),
      body: FutureBuilder<TenantRentalDetails?>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || snapshot.data == null) {
            return _UnavailableDetails(onRetry: () => setState(_loadDetails));
          }

          return _TenantDetailsContent(details: snapshot.data!);
        },
      ),
    );
  }
}

class _TenantDetailsContent extends StatelessWidget {
  const _TenantDetailsContent({required this.details});

  final TenantRentalDetails details;

  @override
  Widget build(BuildContext context) {
    final status = switch (details.tenancyStatus) {
      'active' => 'Active tenancy',
      'unassigned' => 'Unit assignment pending',
      _ => 'Pending tenancy',
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
      children: [
        TenantCard(
          child: Row(
            children: [
              const CircleAvatar(
                radius: 31,
                backgroundColor: Color(0xFFDDE8FF),
                child: Icon(
                  Icons.person_rounded,
                  color: AppColors.primary,
                  size: 34,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      details.fullName,
                      style: const TextStyle(
                        color: AppColors.heading,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      details.email,
                      style: const TextStyle(
                        color: AppColors.body,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TenantStatusPill(
                      label: status,
                      foregroundColor: details.tenancyStatus == 'active'
                          ? AppColors.success
                          : const Color(0xFFE8953E),
                      backgroundColor: details.tenancyStatus == 'active'
                          ? const Color(0xFFE0F7E7)
                          : const Color(0xFFFFF0D7),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Tenancy Information',
          style: TextStyle(
            color: AppColors.heading,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        TenantCard(
          child: Column(
            children: [
              _ProfileLine(
                label: 'Apartment',
                value: details.hasTenancy
                    ? details.apartmentName
                    : 'Not assigned',
                icon: Icons.apartment_outlined,
              ),
              _ProfileLine(
                label: 'Unit number',
                value: details.hasTenancy ? details.unitNumber : 'Not assigned',
                icon: Icons.meeting_room_outlined,
              ),
              _ProfileLine(
                label: 'Monthly rent',
                value: details.hasTenancy
                    ? 'RM ${details.monthlyRentalAmount.toStringAsFixed(2)}'
                    : 'Not configured',
                icon: Icons.payments_outlined,
              ),
              _ProfileLine(
                label: 'Tenancy period',
                value: _dateRange(details.startDate, details.endDate),
                icon: Icons.date_range_outlined,
              ),
              _ProfileLine(
                label: 'Rental space',
                value: !details.hasTenancy
                    ? 'Not assigned'
                    : details.rentalType == 'room'
                    ? 'Room ${details.roomNumber}'
                    : 'Whole unit',
                icon: Icons.bed_outlined,
              ),
              _ProfileLine(
                label: 'Number of occupants',
                value: details.hasTenancy
                    ? '${details.occupantCount}'
                    : 'Not assigned',
                icon: Icons.people_outline,
                last: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TenantCard(
          color: const Color(0xFFF0F5FF),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: AppColors.primary,
                size: 22,
              ),
              SizedBox(width: 11),
              Expanded(
                child: Text(
                  'The rental information shown here is entered and maintained by the apartment administrator. Contact the administrator if any detail is incorrect.',
                  style: TextStyle(
                    color: Color(0xFF5D75B4),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UnavailableDetails extends StatelessWidget {
  const _UnavailableDetails({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: TenantCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.home_work_outlined,
                color: AppColors.primary,
                size: 38,
              ),
              const SizedBox(height: 12),
              const Text(
                'Rental details are not available yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.heading,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Your administrator has not completed the active unit assignment, or the information is temporarily unavailable.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.body,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileLine extends StatelessWidget {
  const _ProfileLine({
    required this.label,
    required this.value,
    required this.icon,
    this.last = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFECEFF3))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.body,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.heading,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

String _dateRange(DateTime? start, DateTime? end) {
  if (start == null) return 'Not configured';
  return end == null
      ? 'From ${_formatDate(start)}\nNo end date'
      : 'From ${_formatDate(start)}\nUntil ${_formatDate(end)}';
}
