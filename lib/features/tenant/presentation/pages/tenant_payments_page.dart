import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/tenant_preview_data.dart';
import '../widgets/tenant_ui.dart';
import 'tenant_payment_page.dart';
import 'tenant_transaction_history_page.dart';

class TenantPaymentsPage extends StatelessWidget {
  const TenantPaymentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bill = TenantPreviewData.bill;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
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
                const Text(
                  'Payments',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  TenantPreviewData.unitName,
                  style: TextStyle(
                    color: Color.fromRGBO(255, 255, 255, 0.82),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 27),
                Text(
                  'Current Bill — ${bill.billingPeriod}',
                  style: const TextStyle(
                    color: Color.fromRGBO(255, 255, 255, 0.88),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'RM ${bill.total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 47,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      color: Color(0xFFFFD0D0),
                      size: 16,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'Due ${bill.dueDate}',
                      style: const TextStyle(
                        color: Color(0xFFFFD0D0),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    _BillPart(label: 'Rent', amount: bill.rent),
                    const SizedBox(width: 12),
                    _BillPart(label: 'Electricity', amount: bill.electricity),
                    const SizedBox(width: 12),
                    _BillPart(label: 'Water', amount: bill.water),
                  ],
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TenantPaymentPage(),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Pay Now',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                TenantCard(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Recent Transactions',
                              style: TextStyle(
                                color: AppColors.heading,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const TenantTransactionHistoryPage(),
                              ),
                            ),
                            child: const Text('View All'),
                          ),
                        ],
                      ),
                      const Divider(height: 12, color: Color(0xFFE9ECF1)),
                      ...TenantPreviewData.transactions
                          .take(3)
                          .map(_RecentTransactionTile.new),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TenantCard(
                  color: const Color(0xFFF0F6FF),
                  child: const Row(
                    children: [
                      TenantIconBox(
                        icon: Icons.schedule_rounded,
                        color: AppColors.primary,
                        backgroundColor: Colors.white,
                      ),
                      SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Auto-debit active',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Payment scheduled on the 7th of each month.',
                              style: TextStyle(
                                color: Color(0xFF6A84C4),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BillPart extends StatelessWidget {
  const _BillPart({required this.label, required this.amount});

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(255, 255, 255, 0.17),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color.fromRGBO(255, 255, 255, 0.88),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'RM ${amount.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentTransactionTile extends StatelessWidget {
  const _RecentTransactionTile(this.transaction);

  final TenantTransactionRecord transaction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const TenantIconBox(
            icon: Icons.calendar_today_outlined,
            color: AppColors.primary,
            backgroundColor: Color(0xFFF0F4FF),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.month,
                  style: const TextStyle(
                    color: AppColors.heading,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Paid on ${transaction.paidDate}',
                  style: const TextStyle(
                    color: Color(0xFF9AA3B3),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'RM ${transaction.amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppColors.heading,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              const TenantStatusPill(
                label: 'Paid',
                foregroundColor: AppColors.success,
                backgroundColor: Color(0xFFE0F7E7),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
