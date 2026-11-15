class TenantBillSummary {
  const TenantBillSummary({
    required this.total,
    required this.rent,
    required this.electricity,
    required this.water,
    required this.dueDate,
    required this.billingPeriod,
  });

  final double total;
  final double rent;
  final double electricity;
  final double water;
  final String dueDate;
  final String billingPeriod;
}

class TenantTransactionRecord {
  const TenantTransactionRecord({
    required this.month,
    required this.reference,
    required this.amount,
    required this.paidDate,
    required this.electricity,
    required this.water,
  });

  final String month;
  final String reference;
  final double amount;
  final String paidDate;
  final double electricity;
  final double water;
}

abstract final class TenantPreviewData {
  static const tenantName = 'Alex Tan Wei Liang';
  static const propertyName = 'TAMAN DANAU RESIDENCES';
  static const unitName = 'PV16 15-22 Room 4';
  static const shortUnitName = 'PV16 15-22 R4';
  static const bill = TenantBillSummary(
    total: 1242.40,
    rent: 1200.00,
    electricity: 22.40,
    water: 20.00,
    dueDate: '7 Sep 2026',
    billingPeriod: 'August 2026',
  );

  static const transactions = <TenantTransactionRecord>[
    TenantTransactionRecord(
      month: 'August 2026',
      reference: '#2608139T5N',
      amount: 1242.40,
      paidDate: '7 Aug 2026',
      electricity: 22.40,
      water: 20.00,
    ),
    TenantTransactionRecord(
      month: 'July 2026',
      reference: '#2607109836',
      amount: 1259.20,
      paidDate: '7 Jul 2026',
      electricity: 39.20,
      water: 20.00,
    ),
    TenantTransactionRecord(
      month: 'June 2026',
      reference: '#26061081G',
      amount: 1260.00,
      paidDate: '7 Jun 2026',
      electricity: 40.00,
      water: 20.00,
    ),
    TenantTransactionRecord(
      month: 'May 2026',
      reference: '#2605104K2',
      amount: 1256.80,
      paidDate: '7 May 2026',
      electricity: 36.80,
      water: 20.00,
    ),
  ];
}
