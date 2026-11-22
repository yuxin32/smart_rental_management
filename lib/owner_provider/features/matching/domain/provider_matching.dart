import '../../../models/demo_data.dart';

/// The mandatory conditions evaluated before any comparative score is
/// calculated. Availability is deliberately absent from the weighted score.
enum ProviderExclusionReason {
  unsupportedService,
  requestedIntervalNotCovered,
  rentalWindowIncompatible,
  activeBookingConflict,
}

extension ProviderExclusionReasonLabel on ProviderExclusionReason {
  String get label => switch (this) {
        ProviderExclusionReason.unsupportedService =>
          'Does not support the requested service',
        ProviderExclusionReason.requestedIntervalNotCovered =>
          'Declared availability does not cover the full interval',
        ProviderExclusionReason.rentalWindowIncompatible =>
          'Requested interval is outside the rental-unit cleaning window',
        ProviderExclusionReason.activeBookingConflict =>
          'Conflicts with an Accepted or In Progress booking',
      };
}

class ProviderMatchRequest {
  const ProviderMatchRequest({
    required this.serviceType,
    required this.requestedStart,
    required this.requestedEnd,
    required this.rentalWindowStart,
    required this.rentalWindowEnd,
  });

  final String serviceType;
  final DateTime requestedStart;
  final DateTime requestedEnd;
  final DateTime rentalWindowStart;
  final DateTime rentalWindowEnd;

  bool get hasValidInterval => requestedEnd.isAfter(requestedStart);

  bool get isInsideRentalWindow =>
      !requestedStart.isBefore(rentalWindowStart) &&
      !requestedEnd.isAfter(rentalWindowEnd);
}

class ExcludedProvider {
  const ExcludedProvider({required this.provider, required this.reasons});

  final DemoProvider provider;
  final List<ProviderExclusionReason> reasons;
}

class ProviderMatchResult {
  const ProviderMatchResult({
    required this.rankedProviders,
    required this.excludedProviders,
  });

  final List<DemoProvider> rankedProviders;
  final List<ExcludedProvider> excludedProviders;
}

/// Implements the two-stage matching design from Sections 3.4.3 and 4.7.1:
/// mandatory eligibility filtering, followed by equal-weight ranking of route
/// distance, rating, and current workload.
class ProviderMatchingService {
  const ProviderMatchingService();

  static const double distanceWeight = 1 / 3;
  static const double ratingWeight = 1 / 3;
  static const double workloadWeight = 1 / 3;
  static const double unratedProviderNeutralRating = 3;

  ProviderMatchResult match({
    required Iterable<DemoProvider> providers,
    required ProviderMatchRequest request,
    required Iterable<DemoBooking> bookings,
  }) {
    if (!request.hasValidInterval) {
      throw ArgumentError('The requested end must be after the start.');
    }

    final bookingList = bookings.toList(growable: false);
    final eligible = <DemoProvider>[];
    final excluded = <ExcludedProvider>[];

    for (final provider in providers) {
      final reasons = _exclusionReasons(
        provider: provider,
        request: request,
        bookings: bookingList,
      );
      if (reasons.isEmpty) {
        eligible.add(provider);
      } else {
        excluded.add(ExcludedProvider(provider: provider, reasons: reasons));
      }
    }

    if (eligible.isEmpty) {
      return ProviderMatchResult(
        rankedProviders: const [],
        excludedProviders: List.unmodifiable(excluded),
      );
    }

    final distances = eligible.map((provider) => provider.distanceKm).toList();
    final ratings = eligible.map(_effectiveRating).toList();
    final workloadCounts = eligible
        .map((provider) => _currentWorkload(provider, request, bookingList))
        .toList();
    final workloads = workloadCounts.map((count) => count.toDouble()).toList();

    final ranked = <DemoProvider>[];
    for (var index = 0; index < eligible.length; index++) {
      final provider = eligible[index];
      final distanceSuitability = _reverseMinMax(distances[index], distances);
      final ratingSuitability = _minMax(ratings[index], ratings);
      final workloadSuitability = _reverseMinMax(workloads[index], workloads);
      final score = distanceSuitability * distanceWeight +
          ratingSuitability * ratingWeight +
          workloadSuitability * workloadWeight;

      ranked.add(
        provider.copyWith(
          score: score,
          activeBookingCount: workloadCounts[index],
          workload: _workloadLabel(workloadCounts[index]),
          distanceSuitability: distanceSuitability,
          ratingSuitability: ratingSuitability,
          workloadSuitability: workloadSuitability,
          hasRankingBreakdown: true,
        ),
      );
    }

    ranked.sort(_compareRankedProviders);
    return ProviderMatchResult(
      rankedProviders: List.unmodifiable(ranked),
      excludedProviders: List.unmodifiable(excluded),
    );
  }

  List<ProviderExclusionReason> _exclusionReasons({
    required DemoProvider provider,
    required ProviderMatchRequest request,
    required Iterable<DemoBooking> bookings,
  }) {
    final reasons = <ProviderExclusionReason>[];
    if (!provider.serviceTypes.contains(request.serviceType)) {
      reasons.add(ProviderExclusionReason.unsupportedService);
    }
    if (!_coversRequestedInterval(provider, request)) {
      reasons.add(ProviderExclusionReason.requestedIntervalNotCovered);
    }
    if (!request.isInsideRentalWindow) {
      reasons.add(ProviderExclusionReason.rentalWindowIncompatible);
    }
    if (_hasActiveBookingConflict(provider, request, bookings)) {
      reasons.add(ProviderExclusionReason.activeBookingConflict);
    }
    return List.unmodifiable(reasons);
  }

  bool _coversRequestedInterval(
    DemoProvider provider,
    ProviderMatchRequest request,
  ) {
    return provider.availabilitySchedule
        .covers(request.requestedStart, request.requestedEnd);
  }

  bool _hasActiveBookingConflict(
    DemoProvider provider,
    ProviderMatchRequest request,
    Iterable<DemoBooking> bookings,
  ) =>
      bookings.any(
        (booking) =>
            booking.providerName == provider.name &&
            booking.status.blocksProviderSlot &&
            request.requestedStart.isBefore(booking.scheduledEnd) &&
            booking.scheduledStart.isBefore(request.requestedEnd),
      );

  int _currentWorkload(
    DemoProvider provider,
    ProviderMatchRequest request,
    Iterable<DemoBooking> bookings,
  ) {
    final windowStart = DateTime(
      request.requestedStart.year,
      request.requestedStart.month,
      request.requestedStart.day,
    );
    final windowEnd = windowStart.add(const Duration(days: 7));
    return bookings
        .where(
          (booking) =>
              booking.providerName == provider.name &&
              booking.status.blocksProviderSlot &&
              booking.scheduledStart.isBefore(windowEnd) &&
              windowStart.isBefore(booking.scheduledEnd),
        )
        .length;
  }

  static String _workloadLabel(int count) {
    if (count <= 1) return 'Low';
    if (count <= 3) return 'Medium';
    return 'High';
  }

  static double _effectiveRating(DemoProvider provider) =>
      provider.rating > 0 ? provider.rating : unratedProviderNeutralRating;

  static double _minMax(double value, List<double> values) {
    final minimum = values.reduce((a, b) => a < b ? a : b);
    final maximum = values.reduce((a, b) => a > b ? a : b);
    if (maximum == minimum) return 1;
    return (value - minimum) / (maximum - minimum);
  }

  static double _reverseMinMax(double value, List<double> values) {
    final minimum = values.reduce((a, b) => a < b ? a : b);
    final maximum = values.reduce((a, b) => a > b ? a : b);
    if (maximum == minimum) return 1;
    return (maximum - value) / (maximum - minimum);
  }

  static int _compareRankedProviders(DemoProvider a, DemoProvider b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byDistance = a.distanceKm.compareTo(b.distanceKm);
    if (byDistance != 0) return byDistance;
    final byRating = b.rating.compareTo(a.rating);
    if (byRating != 0) return byRating;
    final byWorkload = a.activeBookingCount.compareTo(b.activeBookingCount);
    if (byWorkload != 0) return byWorkload;
    return a.name.compareTo(b.name);
  }
}
