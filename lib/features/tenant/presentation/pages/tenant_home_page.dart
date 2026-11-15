import 'package:flutter/material.dart';

import '../../../../core/auth/app_logout_button.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../admin/data/tenant_lifecycle_service.dart';
import '../../data/tenant_preview_data.dart';
import '../widgets/tenant_ui.dart';
import 'tenant_payment_page.dart';
import 'tenant_profile_page.dart';

class TenantHomePage extends StatefulWidget {
  const TenantHomePage({this.onNavigateToTab, super.key});

  final ValueChanged<int>? onNavigateToTab;

  @override
  State<TenantHomePage> createState() => TenantHomePageState();
}

class TenantHomePageState extends State<TenantHomePage> {
  late Future<TenantRentalDetails?> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  void _loadDetails() {
    _detailsFuture = TenantLifecycleService.fetchCurrentTenantDetails();
  }

  Future<void> refresh() async {
    setState(_loadDetails);
    await _detailsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TenantRentalDetails?>(
      future: _detailsFuture,
      builder: (context, snapshot) {
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _TenantHeader(
                details: snapshot.data,
                loading: snapshot.connectionState != ConnectionState.done,
                hasError: snapshot.hasError,
                onRetry: refresh,
                onNotificationTap: () {
                  if (widget.onNavigateToTab != null) {
                    widget.onNavigateToTab!(4);
                  } else {
                    _showMessage(
                      context,
                      'Notifications will be connected soon.',
                    );
                  }
                },
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              sliver: SliverToBoxAdapter(
                child: _OutstandingBillCard(
                  onPayNow: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TenantPaymentPage(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TenantHeader extends StatelessWidget {
  const _TenantHeader({
    required this.details,
    required this.loading,
    required this.hasError,
    required this.onRetry,
    required this.onNotificationTap,
  });

  final TenantRentalDetails? details;
  final bool loading;
  final bool hasError;
  final VoidCallback onRetry;
  final VoidCallback onNotificationTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.headerStart, AppColors.headerEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Good morning,',
                      style: TextStyle(
                        color: Color.fromRGBO(255, 255, 255, 0.82),
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      loading
                          ? 'Loading your details…'
                          : hasError
                          ? 'Tenant'
                          : (details?.fullName.trim().isNotEmpty ?? false)
                          ? details!.fullName.trim()
                          : 'Tenant',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const AppLogoutButton(
                foregroundColor: Colors.white,
                backgroundColor: Color.fromRGBO(255, 255, 255, 0.18),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: 'View notifications',
                child: InkWell(
                  onTap: onNotificationTap,
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(255, 255, 255, 0.18),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.notifications_none_rounded,
                          color: Colors.white,
                          size: 25,
                        ),
                      ),
                      Positioned(
                        top: -1,
                        right: -1,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: AppColors.warning,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.headerStart,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _UnitCard(
            details: details,
            loading: loading,
            hasError: hasError,
            onRetry: onRetry,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TenantProfilePage()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _UnitCard extends StatelessWidget {
  const _UnitCard({
    required this.details,
    required this.loading,
    required this.hasError,
    required this.onRetry,
    required this.onTap,
  });

  final TenantRentalDetails? details;
  final bool loading;
  final bool hasError;
  final VoidCallback onRetry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final assigned =
        details?.hasTenancy == true && details?.unitNumber != 'Not assigned';
    final unitDescription = loading
        ? 'Loading your assigned unit…'
        : hasError
        ? 'Could not load unit details'
        : assigned
        ? details!.unitLabel
        : 'Unit assignment pending';

    return InkWell(
      onTap: hasError ? onRetry : onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(255, 255, 255, 0.17),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.home_work_outlined,
                color: AppColors.primary,
                size: 23,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rental unit',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    unitDescription,
                    style: TextStyle(
                      color: Color.fromRGBO(255, 255, 255, 0.85),
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: 7),
                  Text(
                    'View rental details  →',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TenantStatusPill(
              label: loading
                  ? 'Loading'
                  : hasError
                  ? 'Retry'
                  : assigned
                  ? 'Occupied'
                  : 'Not assigned',
              foregroundColor: assigned
                  ? AppColors.success
                  : const Color(0xFFE8953E),
              backgroundColor: assigned
                  ? const Color.fromRGBO(225, 255, 237, 0.95)
                  : const Color.fromRGBO(255, 240, 215, 0.95),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutstandingBillCard extends StatelessWidget {
  const _OutstandingBillCard({required this.onPayNow});

  final VoidCallback onPayNow;

  @override
  Widget build(BuildContext context) {
    final bill = TenantPreviewData.bill;

    return TenantCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total Outstanding Bill',
                  style: TextStyle(
                    color: AppColors.heading,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const TenantIconBox(
                icon: Icons.receipt_long_outlined,
                color: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'RM ${bill.total.toStringAsFixed(2)}',
            style: const TextStyle(
              color: AppColors.heading,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                color: AppColors.warning,
                size: 15,
              ),
              const SizedBox(width: 5),
              Text(
                'Due ${bill.dueDate}',
                style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPayNow,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Pay Now',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
