// lib/models/demo_data.dart
// Hardcoded demo data so the Sprint 0 app can run without Supabase.
// All numbers and provider names mirror the values from
// supabase/seed/0001_demo_data.sql and the tutor example table.

import 'package:flutter/material.dart';
import '../features/availability/domain/provider_availability.dart';
import '../features/bookings/domain/booking_status.dart';

export '../features/bookings/domain/booking_status.dart';

extension BookingStatusColor on BookingStatus {
  Color get color => switch (this) {
        BookingStatus.pending => const Color(0xFF6B7280),
        BookingStatus.accepted => const Color(0xFF26A69A),
        BookingStatus.inProgress => const Color(0xFFFB8C00),
        BookingStatus.completed => const Color(0xFF2E7D32),
        BookingStatus.declined => const Color(0xFFC62828),
        BookingStatus.cancelled => const Color(0xFF991B1B),
      };
}

class DemoProvider {
  DemoProvider({
    required this.id,
    required this.name,
    required this.serviceTypes,
    required this.distanceKm,
    required this.rating,
    required this.workload,
    required this.score,
    required this.availability,
    this.activeBookingCount = 0,
    this.distanceSuitability = 0,
    this.ratingSuitability = 0,
    this.workloadSuitability = 0,
    this.hasRankingBreakdown = false,
    this.phone = '+60 12-345 6789',
    this.email = 'provider.a@smartrental.my',
    this.bio =
        'Professional cleaning service. Trusted by 50+ property owners in KL.',
    this.workingHoursStart = const TimeOfDay(hour: 8, minute: 0),
    this.workingHoursEnd = const TimeOfDay(hour: 18, minute: 0),
    ProviderAvailabilitySchedule? availabilitySchedule,
    this.hourlyRate = 80.0,
    this.isVerified = true,
    this.avatarColorIndex = 0,
    this.showPhoneToOwners = true,
  }) : availabilitySchedule = availabilitySchedule ??
            (availability == 'Full match'
                ? ProviderAvailabilitySchedule.daily
                : availability == 'Partial match'
                    ? ProviderAvailabilitySchedule.partialDaily
                    : ProviderAvailabilitySchedule.closed);
  final String id;
  final String name;
  final List<String> serviceTypes;
  final double distanceKm;
  final double rating;
  final String workload; // Low / Medium / High
  final double score;
  final String availability; // Full match / Partial match / No slot
  final int activeBookingCount;
  final double distanceSuitability;
  final double ratingSuitability;
  final double workloadSuitability;
  final bool hasRankingBreakdown;

  // Editable fields
  final String phone;
  final String email;
  final String bio;
  final TimeOfDay workingHoursStart;
  final TimeOfDay workingHoursEnd;
  final ProviderAvailabilitySchedule availabilitySchedule;
  final double hourlyRate;
  final bool isVerified;
  final int avatarColorIndex;

  // Privacy setting: when true, owner can see this provider's phone number
  // on the provider profile and booking detail. When false, the phone is
  // hidden and the owner can only contact through in-app chat.
  // Bonus from Round 7 (Edit profile privacy toggle).
  final bool showPhoneToOwners;

  /// Returns a copy with selected fields replaced.
  DemoProvider copyWith({
    String? name,
    List<String>? serviceTypes,
    double? distanceKm,
    double? rating,
    String? workload,
    String? availability,
    String? phone,
    String? email,
    String? bio,
    TimeOfDay? workingHoursStart,
    TimeOfDay? workingHoursEnd,
    ProviderAvailabilitySchedule? availabilitySchedule,
    double? hourlyRate,
    bool? isVerified,
    int? avatarColorIndex,
    double? score,
    int? activeBookingCount,
    double? distanceSuitability,
    double? ratingSuitability,
    double? workloadSuitability,
    bool? hasRankingBreakdown,
    bool? showPhoneToOwners,
  }) {
    return DemoProvider(
      id: id,
      name: name ?? this.name,
      serviceTypes: serviceTypes ?? this.serviceTypes,
      distanceKm: distanceKm ?? this.distanceKm,
      rating: rating ?? this.rating,
      workload: workload ?? this.workload,
      availability: availability ?? this.availability,
      score: score ?? this.score,
      activeBookingCount: activeBookingCount ?? this.activeBookingCount,
      distanceSuitability: distanceSuitability ?? this.distanceSuitability,
      ratingSuitability: ratingSuitability ?? this.ratingSuitability,
      workloadSuitability: workloadSuitability ?? this.workloadSuitability,
      hasRankingBreakdown: hasRankingBreakdown ?? this.hasRankingBreakdown,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      bio: bio ?? this.bio,
      workingHoursStart: workingHoursStart ?? this.workingHoursStart,
      workingHoursEnd: workingHoursEnd ?? this.workingHoursEnd,
      availabilitySchedule: availabilitySchedule ?? this.availabilitySchedule,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      isVerified: isVerified ?? this.isVerified,
      avatarColorIndex: avatarColorIndex ?? this.avatarColorIndex,
      showPhoneToOwners: showPhoneToOwners ?? this.showPhoneToOwners,
    );
  }

  /// Raw provider fixtures. Request-specific eligibility and ranking are
  /// calculated by ProviderMatchingService rather than stored here.
  static List<DemoProvider> seeded() => [
        DemoProvider(
          id: 'p-a',
          name: 'Provider A',
          serviceTypes: const ['standard', 'deep'],
          distanceKm: 2.0,
          rating: 4.8,
          workload: 'Low',
          score: 0,
          availability: 'Full match',
          activeBookingCount: 1,
        ),
        DemoProvider(
          id: 'p-b',
          name: 'Provider B',
          serviceTypes: const ['standard', 'deep', 'window'],
          distanceKm: 5.0,
          rating: 4.9,
          workload: 'High',
          score: 0,
          availability: 'Full match',
          activeBookingCount: 4,
        ),
        DemoProvider(
          id: 'p-c',
          name: 'Provider C',
          serviceTypes: const ['standard'],
          distanceKm: 1.0,
          rating: 4.5,
          workload: 'Medium',
          score: 0,
          availability: 'Partial match',
          activeBookingCount: 2,
        ),
      ];
}

class DemoBooking {
  DemoBooking({
    required this.id,
    required this.property,
    required this.serviceType,
    required this.providerName,
    this.hourlyRateAtBooking,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.status,
    required this.specialInstructions,
    this.isRecurring = false,
    this.recurrencePattern,
    this.totalDays = 1,
    this.acceptedAt,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
    this.declinedAt,
    this.declineReason,
    this.cancellationReason,
    this.beforeImagePath,
    this.afterImagePath,
    this.completionRemarks,
    this.ownerRating,
    this.ownerRatingComment,
  });
  final String id;
  final String property;
  final String serviceType;
  final String? providerName;

  /// Agreed demo rate captured when the request is created, so later profile
  /// edits do not recalculate an existing booking's amount.
  final double? hourlyRateAtBooking;
  final DateTime scheduledStart;
  final DateTime scheduledEnd;
  final BookingStatus status;
  final String? specialInstructions;
  final bool isRecurring;
  final RecurrencePattern? recurrencePattern;
  final int totalDays; // For multi-day bookings (>1 if spans multiple days)

  // Lifecycle timestamps (Chapter 2.6.3: continuity of information).
  final DateTime? acceptedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final DateTime? declinedAt;

  // Reason text fields.
  final String? declineReason;
  final String? cancellationReason;

  // Completion evidence. Paths are local in the demo and move to Supabase
  // Storage in the formal implementation.
  final String? beforeImagePath;
  final String? afterImagePath;
  final String? completionRemarks;

  // Owner rating (F2). 1-5 stars (Section 2.4.8).
  final int? ownerRating;
  final String? ownerRatingComment;

  /// Whether the booking spans more than one calendar day.
  bool get isMultiDay => totalDays > 1;

  /// True for states with no further transitions.
  bool get isTerminal => status.isTerminal;

  /// True when both proof photos have been captured (F2 helper).
  bool get hasProof => beforeImagePath != null && afterImagePath != null;

  bool get hasCompletionEvidence =>
      hasProof && (completionRemarks?.trim().isNotEmpty ?? false);

  /// True when owner has submitted a rating (F2 helper).
  bool get isRated => ownerRating != null;

  /// Returns a copy with selected fields replaced. Used by BookingStore
  /// for transactional updates that preserve unrelated fields.
  DemoBooking copyWith({
    String? providerName,
    double? hourlyRateAtBooking,
    DateTime? scheduledStart,
    DateTime? scheduledEnd,
    BookingStatus? status,
    String? specialInstructions,
    bool? isRecurring,
    RecurrencePattern? recurrencePattern,
    int? totalDays,
    DateTime? acceptedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? cancelledAt,
    DateTime? declinedAt,
    String? declineReason,
    String? cancellationReason,
    String? beforeImagePath,
    String? afterImagePath,
    String? completionRemarks,
    bool clearBeforeImagePath = false,
    bool clearAfterImagePath = false,
    bool clearCompletionRemarks = false,
    int? ownerRating,
    String? ownerRatingComment,
  }) {
    return DemoBooking(
      id: id,
      property: property,
      serviceType: serviceType,
      providerName: providerName ?? this.providerName,
      hourlyRateAtBooking: hourlyRateAtBooking ?? this.hourlyRateAtBooking,
      scheduledStart: scheduledStart ?? this.scheduledStart,
      scheduledEnd: scheduledEnd ?? this.scheduledEnd,
      status: status ?? this.status,
      specialInstructions: specialInstructions ?? this.specialInstructions,
      isRecurring: isRecurring ?? this.isRecurring,
      recurrencePattern: recurrencePattern ?? this.recurrencePattern,
      totalDays: totalDays ?? this.totalDays,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      declinedAt: declinedAt ?? this.declinedAt,
      declineReason: declineReason ?? this.declineReason,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      beforeImagePath:
          clearBeforeImagePath ? null : beforeImagePath ?? this.beforeImagePath,
      afterImagePath:
          clearAfterImagePath ? null : afterImagePath ?? this.afterImagePath,
      completionRemarks: clearCompletionRemarks
          ? null
          : completionRemarks ?? this.completionRemarks,
      ownerRating: ownerRating ?? this.ownerRating,
      ownerRatingComment: ownerRatingComment ?? this.ownerRatingComment,
    );
  }

  static List<DemoBooking> all() => [
        DemoBooking(
          id: 'b-001',
          property: 'Unit A-12, Menara Suria',
          serviceType: 'Move-out cleaning',
          providerName: 'Provider A',
          scheduledStart: DateTime(2026, 7, 14, 10, 0),
          scheduledEnd: DateTime(2026, 7, 14, 12, 0),
          status: BookingStatus.inProgress,
          specialInstructions:
              'Focus on kitchen and both bathrooms. Tenant move-in tomorrow 9 AM.',
        ),
        DemoBooking(
          id: 'b-002',
          property: 'Unit B-08, Menara Suria',
          serviceType: 'Deep cleaning',
          providerName: 'Provider B',
          scheduledStart: DateTime(2026, 7, 16, 14, 0),
          scheduledEnd: DateTime(2026, 7, 16, 17, 0),
          status: BookingStatus.accepted,
          specialInstructions: 'Window cleaning included.',
        ),
        DemoBooking(
          id: 'b-003',
          property: 'Unit C-21, Menara Suria',
          serviceType: 'Routine cleaning',
          providerName: 'Provider A',
          scheduledStart: DateTime(2026, 7, 18, 9, 0),
          scheduledEnd: DateTime(2026, 7, 18, 11, 0),
          status: BookingStatus.pending,
          specialInstructions: null,
        ),
        DemoBooking(
          id: 'b-004',
          property: 'Unit D-03, Menara Suria',
          serviceType: 'Move-in cleaning',
          providerName: 'Provider C',
          scheduledStart: DateTime(2026, 7, 11, 13, 0),
          scheduledEnd: DateTime(2026, 7, 11, 15, 0),
          status: BookingStatus.completed,
          specialInstructions: 'Already confirmed by owner.',
        ),
        // Sample recurring booking (weekly deep clean on Unit A-12)
        DemoBooking(
          id: 'b-005',
          property: 'Unit A-12, Menara Suria',
          serviceType: 'Routine cleaning',
          providerName: 'Provider A',
          scheduledStart: DateTime(2026, 7, 21, 10, 0),
          scheduledEnd: DateTime(2026, 7, 21, 12, 0),
          status: BookingStatus.accepted,
          specialInstructions:
              'Recurring weekly clean. Same scope every visit.',
          isRecurring: true,
          recurrencePattern: RecurrencePattern.weekly,
        ),
      ].map((booking) => booking.copyWith(hourlyRateAtBooking: 80)).toList();
}

/// Properties the owner manages. Used by New Booking form.
class DemoProperty {
  const DemoProperty(
      {this.id = '',
      required this.unit,
      required this.tower,
      required this.bedrooms,
      required this.sizeSqft,
      this.address = '',
      this.cleaningWindowStart = const TimeOfDay(hour: 8, minute: 0),
      this.cleaningWindowEnd = const TimeOfDay(hour: 18, minute: 0)});
  final String id;
  final String unit;
  final String tower;
  final int bedrooms;
  final int sizeSqft;
  final String address;
  // Local preview fixture until rental-unit availability is persisted.
  final TimeOfDay cleaningWindowStart;
  final TimeOfDay cleaningWindowEnd;
  String get display => 'Unit $unit, $tower';

  DemoProperty copyWith({
    String? unit,
    String? tower,
    int? bedrooms,
    int? sizeSqft,
    String? address,
    TimeOfDay? cleaningWindowStart,
    TimeOfDay? cleaningWindowEnd,
  }) =>
      DemoProperty(
        id: id,
        unit: unit ?? this.unit,
        tower: tower ?? this.tower,
        bedrooms: bedrooms ?? this.bedrooms,
        sizeSqft: sizeSqft ?? this.sizeSqft,
        address: address ?? this.address,
        cleaningWindowStart: cleaningWindowStart ?? this.cleaningWindowStart,
        cleaningWindowEnd: cleaningWindowEnd ?? this.cleaningWindowEnd,
      );

  static const List<DemoProperty> all = [
    DemoProperty(
        id: 'prop-a12',
        unit: 'A-12',
        tower: 'Menara Suria',
        bedrooms: 3,
        sizeSqft: 980),
    DemoProperty(
        id: 'prop-b08',
        unit: 'B-08',
        tower: 'Menara Suria',
        bedrooms: 2,
        sizeSqft: 760),
    DemoProperty(
        id: 'prop-c21',
        unit: 'C-21',
        tower: 'Menara Suria',
        bedrooms: 4,
        sizeSqft: 1200),
    DemoProperty(
        id: 'prop-d03',
        unit: 'D-03',
        tower: 'Menara Suria',
        bedrooms: 2,
        sizeSqft: 720),
    DemoProperty(
        id: 'prop-e15',
        unit: 'E-15',
        tower: 'Vista Bayu',
        bedrooms: 3,
        sizeSqft: 1050),
  ];
}

/// Service types offered. Used by New Booking form.
class ServiceTypeOption {
  const ServiceTypeOption(
      {required this.id,
      required this.label,
      required this.durationHours,
      required this.priceFrom});
  final String id;
  final String label;
  final int durationHours;
  final double priceFrom;

  static const List<ServiceTypeOption> all = [
    ServiceTypeOption(
        id: 'standard',
        label: 'Standard cleaning',
        durationHours: 2,
        priceFrom: 80),
    ServiceTypeOption(
        id: 'deep', label: 'Deep cleaning', durationHours: 3, priceFrom: 150),
    ServiceTypeOption(
        id: 'move-in',
        label: 'Move-in cleaning',
        durationHours: 3,
        priceFrom: 160),
    ServiceTypeOption(
        id: 'move-out',
        label: 'Move-out cleaning',
        durationHours: 3,
        priceFrom: 170),
    ServiceTypeOption(
        id: 'window',
        label: 'Window cleaning',
        durationHours: 2,
        priceFrom: 90),
  ];
}

// ====================================================================
// Aggregations: earnings, spend, reviews. Used by dashboard screens.
// ====================================================================

/// Recurrence cadence for repeating bookings.
enum RecurrencePattern {
  weekly('Weekly'),
  biweekly('Every 2 weeks'),
  monthly('Monthly');

  const RecurrencePattern(this.label);
  final String label;

  String get shortLabel {
    switch (this) {
      case RecurrencePattern.weekly:
        return 'Weekly';
      case RecurrencePattern.biweekly:
        return 'Bi-weekly';
      case RecurrencePattern.monthly:
        return 'Monthly';
    }
  }

  /// Returns the next occurrence after [from] matching this pattern.
  DateTime nextAfter(DateTime from) {
    switch (this) {
      case RecurrencePattern.weekly:
        return from.add(const Duration(days: 7));
      case RecurrencePattern.biweekly:
        return from.add(const Duration(days: 14));
      case RecurrencePattern.monthly:
        return DateTime(
            from.year, from.month + 1, from.day, from.hour, from.minute);
    }
  }
}

/// Earnings record: a single completed job's payout, tagged to a week.
class EarningsRecord {
  const EarningsRecord({
    required this.bookingId,
    required this.date,
    required this.hours,
    required this.gross,
    required this.platformFee,
    required this.net,
    required this.serviceLabel,
    required this.property,
    this.amountAvailable = true,
    this.settlementAvailable = true,
  });
  final String bookingId;
  final DateTime date;
  final double hours;
  final double gross;
  final double platformFee;
  final double net;
  final String serviceLabel;
  final String property;
  final bool amountAvailable;
  final bool settlementAvailable;

  static double computeGross(Duration duration, {required double hourlyRate}) {
    final hours = duration.inMinutes / 60.0;
    return hourlyRate * hours;
  }

  static double computeFee(double gross) => gross * 0.15; // 15% platform fee
}

/// Owner spend record: a single completed job's cost.
class SpendRecord {
  const SpendRecord({
    required this.bookingId,
    required this.date,
    required this.cost,
    required this.serviceLabel,
    required this.property,
    required this.providerName,
    this.amountAvailable = true,
  });
  final String bookingId;
  final DateTime date;
  final double cost;
  final String serviceLabel;
  final String property;
  final String providerName;
  final bool amountAvailable;
}

/// Provider-specific earnings aggregation.
class EarningsSummary {
  const EarningsSummary({
    required this.providerName,
    required this.totalNet,
    required this.weeklyNet,
    required this.monthlyNet,
    required this.jobsCompleted,
    required this.avgPerJob,
    required this.records,
  });
  final String providerName;
  final double totalNet;
  final double weeklyNet;
  final double monthlyNet;
  final int jobsCompleted;
  final double avgPerJob;
  final List<EarningsRecord> records;
}

/// Spend aggregation (owner's view).
class SpendSummary {
  const SpendSummary({
    required this.totalSpent,
    required this.thisMonth,
    required this.lastMonth,
    required this.jobsFunded,
    required this.avgPerJob,
    required this.byProvider,
    required this.records,
  });
  final double totalSpent;
  final double thisMonth;
  final double lastMonth;
  final int jobsFunded;
  final double avgPerJob;
  final List<MapEntry<String, double>> byProvider; // provider -> total
  final List<SpendRecord> records;
}

/// Compute earnings for a specific provider from a list of bookings.
double _rateForBooking(DemoBooking booking, Iterable<DemoProvider> providers) {
  final rate = booking.hourlyRateAtBooking ??
      providers
          .where((provider) => provider.name == booking.providerName)
          .firstOrNull
          ?.hourlyRate;
  if (rate == null || rate <= 0) {
    throw StateError('Hourly rate unavailable for booking ${booking.id}');
  }
  return rate;
}

EarningsSummary earningsFor(String providerName, List<DemoBooking> bookings,
    {Iterable<DemoProvider>? providers}) {
  final rateProviders = providers ?? DemoProvider.seeded();
  final completed = bookings
      .where((b) =>
          b.providerName == providerName && b.status == BookingStatus.completed)
      .toList()
    ..sort((a, b) => b.scheduledStart.compareTo(a.scheduledStart));

  final records = completed.map((b) {
    final duration = b.scheduledEnd.difference(b.scheduledStart);
    final gross = EarningsRecord.computeGross(
      duration,
      hourlyRate: _rateForBooking(b, rateProviders),
    );
    final fee = EarningsRecord.computeFee(gross);
    return EarningsRecord(
      bookingId: b.id,
      date: b.scheduledStart,
      hours: duration.inMinutes / 60.0,
      gross: gross,
      platformFee: fee,
      net: gross - fee,
      serviceLabel: b.serviceType,
      property: b.property,
    );
  }).toList();

  final now = DateTime.now();
  final startOfWeek = DateTime(now.year, now.month, now.day - now.weekday + 1);
  final startOfMonth = DateTime(now.year, now.month, 1);

  double weekly = 0, monthly = 0, total = 0;
  for (final r in records) {
    total += r.net;
    if (r.date.isAfter(startOfWeek) || r.date.isAtSameMomentAs(startOfWeek)) {
      weekly += r.net;
    }
    if (r.date.isAfter(startOfMonth) || r.date.isAtSameMomentAs(startOfMonth)) {
      monthly += r.net;
    }
  }

  return EarningsSummary(
    providerName: providerName,
    totalNet: total,
    weeklyNet: weekly,
    monthlyNet: monthly,
    jobsCompleted: records.length,
    avgPerJob: records.isEmpty ? 0 : total / records.length,
    records: records,
  );
}

/// Compute owner's spend aggregation from a list of bookings.
SpendSummary spendFor(List<DemoBooking> bookings,
    {Iterable<DemoProvider>? providers}) {
  final rateProviders = providers ?? DemoProvider.seeded();
  final completed = bookings
      .where((b) => b.status == BookingStatus.completed)
      .toList()
    ..sort((a, b) => b.scheduledStart.compareTo(a.scheduledStart));

  final records = completed.map((b) {
    final duration = b.scheduledEnd.difference(b.scheduledStart);
    return SpendRecord(
      bookingId: b.id,
      date: b.scheduledStart,
      cost: EarningsRecord.computeGross(
        duration,
        hourlyRate: _rateForBooking(b, rateProviders),
      ),
      serviceLabel: b.serviceType,
      property: b.property,
      providerName: b.providerName ?? 'Unknown',
    );
  }).toList();

  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month, 1);
  final lastMonthStart = DateTime(now.year, now.month - 1, 1);
  final lastMonthEnd = startOfMonth;

  double total = 0, thisMonth = 0, lastMonth = 0;
  final byProvider = <String, double>{};
  for (final r in records) {
    total += r.cost;
    if (r.date.isAfter(startOfMonth) || r.date.isAtSameMomentAs(startOfMonth)) {
      thisMonth += r.cost;
    }
    if (r.date.isAfter(lastMonthStart) && r.date.isBefore(lastMonthEnd)) {
      lastMonth += r.cost;
    }
    byProvider[r.providerName] = (byProvider[r.providerName] ?? 0) + r.cost;
  }

  final byProviderList = byProvider.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return SpendSummary(
    totalSpent: total,
    thisMonth: thisMonth,
    lastMonth: lastMonth,
    jobsFunded: records.length,
    avgPerJob: records.isEmpty ? 0 : total / records.length,
    byProvider: byProviderList,
    records: records,
  );
}
