// lib/services/provider_store.dart
// In-memory store for provider profile data. Single source of truth so
// editing the profile updates the rank list, profile screen, earnings, etc.
//
// Sprint 0: pure in-memory. Sprint 1: backed by Supabase (providers table).

import 'package:flutter/foundation.dart';
import '../features/matching/domain/provider_matching.dart';
import '../features/availability/domain/provider_availability.dart';
import '../models/demo_data.dart';

class ProviderStore extends ChangeNotifier {
  ProviderStore() {
    _providers = List.of(DemoProvider.seeded());
  }

  late List<DemoProvider> _providers;
  List<DemoProvider> get providers => List.unmodifiable(_providers);

  /// The currently-logged-in provider's id (set by UserSession on login).
  /// Used by the edit profile page to know which one to load.
  String? _currentProviderId;
  String? get currentProviderId => _currentProviderId;

  void setCurrentProviderId(String? id) {
    _currentProviderId = id;
    notifyListeners();
  }

  DemoProvider? byId(String id) {
    try {
      return _providers.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// The logged-in provider. Falls back to the first provider if none set.
  DemoProvider? get currentProvider {
    if (_currentProviderId != null) {
      final p = byId(_currentProviderId!);
      if (p != null) return p;
    }
    return _providers.isEmpty ? null : _providers.first;
  }

  /// Update the provider with [id]. Request-specific scores are deliberately
  /// not stored here; they are recalculated after eligibility filtering.
  void update(DemoProvider updated) {
    final i = _providers.indexWhere((p) => p.id == updated.id);
    if (i < 0) return;
    _providers = List.of(_providers)
      ..[i] = updated.copyWith(
        score: 0,
        distanceSuitability: 0,
        ratingSuitability: 0,
        workloadSuitability: 0,
        hasRankingBreakdown: false,
      );
    notifyListeners();
  }

  ProviderMatchResult matchProviders({
    required ProviderMatchRequest request,
    required Iterable<DemoBooking> bookings,
  }) =>
      const ProviderMatchingService().match(
        providers: _providers,
        request: request,
        bookings: bookings,
      );

  /// Add a brand new provider. Used when a provider signs up.
  void add(DemoProvider provider) {
    _providers = [provider, ..._providers];
    notifyListeners();
  }

  /// Toggle the availability of the current provider.
  void toggleAvailability(String providerId) {
    final p = byId(providerId);
    if (p == null) return;
    final next = p.availability == 'Full match'
        ? 'Partial match'
        : p.availability == 'Partial match'
            ? 'No slot'
            : 'Full match';
    update(p.copyWith(
      availability: next,
      availabilitySchedule: next == 'Full match'
          ? ProviderAvailabilitySchedule.daily
          : next == 'Partial match'
              ? ProviderAvailabilitySchedule.partialDaily
              : ProviderAvailabilitySchedule.closed,
    ));
  }

  void setWeeklySlots(
      String providerId, int weekday, List<AvailabilitySlot> slots) {
    final provider = byId(providerId);
    if (provider == null) return;
    update(provider.copyWith(
      availabilitySchedule:
          provider.availabilitySchedule.withDaySlots(weekday, slots),
    ));
  }

  void setUnavailableDate(String providerId, DateTime date, bool unavailable) {
    final provider = byId(providerId);
    if (provider == null) return;
    update(provider.copyWith(
      availabilitySchedule: provider.availabilitySchedule
          .withUnavailableDate(date, unavailable: unavailable),
    ));
  }
}
