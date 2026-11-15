import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/tenant_preview_data.dart';
import '../widgets/tenant_ui.dart';

class TenantTransactionHistoryPage extends StatefulWidget {
  const TenantTransactionHistoryPage({super.key});

  @override
  State<TenantTransactionHistoryPage> createState() =>
      _TenantTransactionHistoryPageState();
}

class _TenantTransactionHistoryPageState
    extends State<TenantTransactionHistoryPage> {
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final records = TenantPreviewData.transactions;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: const TenantBackAppBar(title: 'Transaction History'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: ['All', 'Rent', 'Electricity', 'Water']
                    .map(
                      (filter) => Padding(
                        padding: const EdgeInsets.only(right: 9),
                        child: ChoiceChip(
                          label: Text(filter),
                          selected: _selectedFilter == filter,
                          onSelected: (_) =>
                              setState(() => _selectedFilter = filter),
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: _selectedFilter == filter
                                ? Colors.white
                                : AppColors.body,
                            fontWeight: FontWeight.w600,
                          ),
                          side: BorderSide(
                            color: _selectedFilter == filter
                                ? AppColors.primary
                                : const Color(0xFFE2E6ED),
                          ),
                          backgroundColor: Colors.white,
                          showCheckmark: false,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
            ...records.map(
              (record) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _TransactionCard(record: record),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({required this.record});

  final TenantTransactionRecord record;

  @override
  Widget build(BuildContext context) {
    return TenantCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.month,
                        style: const TextStyle(
                          color: AppColors.heading,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        record.reference,
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
                      'RM ${record.amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppColors.heading,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      record.paidDate,
                      style: const TextStyle(
                        color: Color(0xFF9AA3B3),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const TenantStatusPill(
                      label: 'Paid',
                      foregroundColor: AppColors.success,
                      backgroundColor: Color(0xFFE0F7E7),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFECEFF3)),
          _LineItem(
            label: '${TenantPreviewData.shortUnitName} Rent',
            amount: 1200,
          ),
          _LineItem(
            label: '${TenantPreviewData.shortUnitName} Electricity',
            amount: record.electricity,
          ),
          _LineItem(
            label: '${TenantPreviewData.shortUnitName} Water',
            amount: record.water,
            last: true,
          ),
        ],
      ),
    );
  }
}

class _LineItem extends StatelessWidget {
  const _LineItem({
    required this.label,
    required this.amount,
    this.last = false,
  });

  final String label;
  final double amount;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFECEFF3))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '• $label',
              style: const TextStyle(color: AppColors.body, fontSize: 13),
            ),
          ),
          Text(
            'RM ${amount.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Color(0xFF465064),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
