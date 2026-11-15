import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/tenant_preview_data.dart';
import '../widgets/tenant_ui.dart';
import 'tenant_payment_success_page.dart';

class TenantPaymentPage extends StatefulWidget {
  const TenantPaymentPage({super.key});

  @override
  State<TenantPaymentPage> createState() => _TenantPaymentPageState();
}

class _TenantPaymentPageState extends State<TenantPaymentPage> {
  String _selectedMethod = 'FPX Online Banking';

  @override
  Widget build(BuildContext context) {
    final bill = TenantPreviewData.bill;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: const TenantBackAppBar(title: 'Payment'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
        children: [
          TenantCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Amount due',
                  style: TextStyle(color: Color(0xFF9AA3B3), fontSize: 15),
                ),
                const SizedBox(height: 7),
                Text(
                  'RM ${bill.total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: AppColors.heading,
                    fontSize: 43,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const Divider(height: 28, color: Color(0xFFECEFF3)),
                _PaymentLine(label: 'Rent', amount: bill.rent),
                const SizedBox(height: 11),
                _PaymentLine(
                  label: 'Electricity (${bill.billingPeriod.substring(0, 3)})',
                  amount: bill.electricity,
                ),
                const SizedBox(height: 11),
                _PaymentLine(
                  label: 'Water (${bill.billingPeriod.substring(0, 3)})',
                  amount: bill.water,
                ),
                const Divider(height: 28, color: Color(0xFFECEFF3)),
                _PaymentLine(label: 'Total', amount: bill.total, isTotal: true),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Payment method',
            style: TextStyle(
              color: AppColors.heading,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          _PaymentMethodCard(
            icon: Icons.account_balance_outlined,
            title: 'FPX Online Banking',
            subtitle: 'Pay via your bank',
            selected: _selectedMethod == 'FPX Online Banking',
            onTap: () => setState(() => _selectedMethod = 'FPX Online Banking'),
          ),
          const SizedBox(height: 12),
          _PaymentMethodCard(
            icon: Icons.credit_card_outlined,
            title: 'Credit / Debit Card',
            subtitle: 'Visa, Mastercard',
            selected: _selectedMethod == 'Credit / Debit Card',
            onTap: () =>
                setState(() => _selectedMethod = 'Credit / Debit Card'),
          ),
          const SizedBox(height: 12),
          _PaymentMethodCard(
            icon: Icons.account_balance_wallet_outlined,
            title: 'e-Wallet',
            subtitle: "Touch 'n Go, GrabPay",
            selected: _selectedMethod == 'e-Wallet',
            onTap: () => setState(() => _selectedMethod = 'e-Wallet'),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFAE8),
              borderRadius: BorderRadius.circular(18),
            ),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: Color(0xFFB46A16),
                  fontSize: 13,
                  height: 1.4,
                ),
                children: [
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFE39A24),
                        size: 21,
                      ),
                    ),
                  ),
                  const TextSpan(text: 'Payment due by '),
                  TextSpan(
                    text: '${bill.dueDate}.',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const TextSpan(text: ' Late payments may incur charges.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const TenantPaymentSuccessPage(),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 17),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'Confirm Payment — RM ${bill.total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentLine extends StatelessWidget {
  const _PaymentLine({
    required this.label,
    required this.amount,
    this.isTotal = false,
  });

  final String label;
  final double amount;
  final bool isTotal;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: isTotal ? AppColors.heading : AppColors.body,
              fontSize: isTotal ? 16 : 15,
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w400,
            ),
          ),
        ),
        Text(
          'RM ${amount.toStringAsFixed(2)}',
          style: TextStyle(
            color: AppColors.heading,
            fontSize: isTotal ? 17 : 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TenantCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      radius: 19,
      child: Row(
        children: [
          TenantIconBox(
            icon: icon,
            color: selected ? AppColors.primary : const Color(0xFF9CA4B3),
            backgroundColor: selected
                ? const Color(0xFFEAF0FF)
                : const Color(0xFFF8F9FB),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.heading,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF9AA3B3),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.primary : const Color(0xFFD0D5DE),
                width: selected ? 0 : 2,
              ),
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 17)
                : null,
          ),
        ],
      ),
    );
  }
}
