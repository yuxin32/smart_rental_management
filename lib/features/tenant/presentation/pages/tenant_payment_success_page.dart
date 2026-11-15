import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/tenant_preview_data.dart';
import '../widgets/tenant_ui.dart';

class TenantPaymentSuccessPage extends StatelessWidget {
  const TenantPaymentSuccessPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bill = TenantPreviewData.bill;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 56, 24, 54),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.headerStart, AppColors.headerEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(32),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: const BoxDecoration(
                      color: Color.fromRGBO(255, 255, 255, 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: AppColors.primary,
                        size: 34,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Payment Successful!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 29,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'RM ${bill.total.toStringAsFixed(2)} · ${TenantPreviewData.shortUnitName}',
                    style: const TextStyle(
                      color: Color.fromRGBO(255, 255, 255, 0.84),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Ref: 2609140U6V · 02/09/2026',
                    style: TextStyle(
                      color: Color.fromRGBO(255, 255, 255, 0.75),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                children: [
                  const Text(
                    'Latest Transactions',
                    style: TextStyle(
                      color: AppColors.heading,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SuccessTransactionCard(
                    title: 'Monthly Payment',
                    reference: '#2609140U6V',
                    amount: bill.total,
                    detail:
                        '• ${TenantPreviewData.shortUnitName} Aug Electricity — RM 22.40',
                  ),
                  const SizedBox(height: 14),
                  _SuccessTransactionCard(
                    title: 'Monthly Payment',
                    reference: '#2608139T5N',
                    amount: bill.total,
                    detail:
                        '• ${TenantPreviewData.shortUnitName} Jul Electricity — RM 22.40',
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).popUntil((route) => route.isFirst),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Back to Payments',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessTransactionCard extends StatelessWidget {
  const _SuccessTransactionCard({
    required this.title,
    required this.reference,
    required this.amount,
    required this.detail,
  });

  final String title;
  final String reference;
  final double amount;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return TenantCard(
      color: const Color(0xFFF8F9FB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.heading,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                'RM ${amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppColors.heading,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            reference,
            style: const TextStyle(color: AppColors.body, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: const TextStyle(color: AppColors.body, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
