import 'package:flutter/material.dart';
import '../../../../core/auth/app_logout_button.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../admin/data/tenant_lifecycle_service.dart';
import '../../data/tenant_preview_data.dart';
import '../widgets/tenant_ui.dart';
import 'tenant_payment_page.dart';
import 'tenant_profile_page.dart';

class TenantHomePage extends StatefulWidget {
  const TenantHomePage({this.onNavigateToTab, this.loadDetails, super.key});
  final ValueChanged<int>? onNavigateToTab;
  final Future<TenantRentalDetails?> Function()? loadDetails;
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
    _detailsFuture =
        widget.loadDetails?.call() ??
        TenantLifecycleService.fetchCurrentTenantDetails();
  }

  Future<void> refresh() async {
    setState(_loadDetails);
    await _detailsFuture;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TenantRentalDetails?>(
    future: _detailsFuture,
    builder: (context, snapshot) => CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _TenantHeader(
            details: snapshot.data,
            loading: snapshot.connectionState != ConnectionState.done,
            hasError: snapshot.hasError,
            onRetry: refresh,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          sliver: SliverToBoxAdapter(
            child: _OutstandingBillCard(
              onPayNow: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TenantPaymentPage()),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _TenantHeader extends StatelessWidget {
  const _TenantHeader({
    required this.details,
    required this.loading,
    required this.hasError,
    required this.onRetry,
  });
  final TenantRentalDetails? details;
  final bool loading, hasError;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Container(
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
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Welcome,',
                    style: TextStyle(color: Color(0xFFDDE4EF), fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    loading
                        ? 'Loading your details…'
                        : details?.fullName.trim().isNotEmpty == true
                        ? details!.fullName.trim()
                        : 'Tenant',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
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
          ],
        ),
        const SizedBox(height: 22),
        Material(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: loading
                ? null
                : hasError
                ? onRetry
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TenantProfilePage(),
                    ),
                  ),
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Row(
                children: [
                  const Icon(
                    Icons.apartment_outlined,
                    color: Colors.white,
                    size: 30,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loading
                              ? 'Loading…'
                              : hasError
                              ? 'Unable to load tenancy. Tap to retry.'
                              : details?.hasTenancy == true
                              ? details!.apartmentName
                              : 'Unit assignment pending',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (details?.hasTenancy == true &&
                            !loading &&
                            !hasError) ...[
                          const SizedBox(height: 5),
                          Text(
                            'Unit ${details!.unitNumber}${details!.rentalType == 'room' ? ' · Room ${details!.roomNumber}' : ' · Whole unit'}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ],
                        const SizedBox(height: 7),
                        const Text(
                          'View rental details',
                          style: TextStyle(
                            color: Color(0xFFDDE4EF),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
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
          const SizedBox(height: 18),
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
