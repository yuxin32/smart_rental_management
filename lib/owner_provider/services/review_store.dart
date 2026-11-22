// lib/services/review_store.dart
// In-memory store for provider reviews. Single source of truth.
// Seeded with mock reviews so the providers page has real data.

import 'package:flutter/foundation.dart';
import '../models/review.dart';

class ReviewStore extends ChangeNotifier {
  ReviewStore() {
    _reviews = List.of(_seed());
  }

  late List<Review> _reviews;
  List<Review> get all => List.unmodifiable(_reviews);

  List<Review> forProvider(String providerName) =>
      _reviews.where((r) => r.providerName == providerName).toList();

  /// Aggregate: average rating for a provider.
  double averageFor(String providerName) {
    final list = forProvider(providerName);
    if (list.isEmpty) return 0;
    final sum = list.fold<int>(0, (acc, r) => acc + r.rating);
    return sum / list.length;
  }

  /// Aggregate: histogram count of each star rating.
  Map<int, int> distributionFor(String providerName) {
    final list = forProvider(providerName);
    final hist = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in list) {
      hist[r.rating] = (hist[r.rating] ?? 0) + 1;
    }
    return hist;
  }

  void add(Review review) {
    _reviews = [review, ..._reviews];
    notifyListeners();
  }

  // Mock seed data — Provider A has 5 reviews, B has 3, C has 2.
  static List<Review> _seed() {
    final now = DateTime.now();
    return [
      Review(
        id: 'r-1', bookingId: 'b-old1', providerName: 'Provider A',
        ownerName: 'Oh Wan Ting', rating: 5,
        comment: 'Excellent work! Very thorough and the team was punctual. Will book again.',
        tags: const ['On time', 'Thorough', 'Professional'],
        timestamp: now.subtract(const Duration(days: 2)),
      ),
      Review(
        id: 'r-2', bookingId: 'b-old2', providerName: 'Provider A',
        ownerName: 'Siti Rahman', rating: 5,
        comment: 'Move-out cleaning was impeccable. Got my full deposit back!',
        tags: const ['On time', 'Thorough'],
        timestamp: now.subtract(const Duration(days: 6)),
      ),
      Review(
        id: 'r-3', bookingId: 'b-old3', providerName: 'Provider A',
        ownerName: 'David Lim', rating: 4,
        comment: 'Good service overall. Took a bit longer than expected but the result was great.',
        tags: const ['Thorough', 'Friendly'],
        timestamp: now.subtract(const Duration(days: 10)),
      ),
      Review(
        id: 'r-4', bookingId: 'b-old4', providerName: 'Provider A',
        ownerName: 'Priya Nair', rating: 5,
        comment: 'Best cleaning service in KL! Re-booking every 2 weeks.',
        tags: const ['On time', 'Friendly', 'Value for money', 'Great communication'],
        timestamp: now.subtract(const Duration(days: 14)),
      ),
      Review(
        id: 'r-5', bookingId: 'b-old5', providerName: 'Provider A',
        ownerName: 'Jason Wong', rating: 4,
        comment: 'Friendly team. Will use again.',
        tags: const ['Friendly'],
        timestamp: now.subtract(const Duration(days: 21)),
      ),
      Review(
        id: 'r-6', bookingId: 'b-old6', providerName: 'Provider B',
        ownerName: 'Aisha Tan', rating: 5,
        comment: 'Window cleaning was perfect. They brought their own equipment.',
        tags: const ['Professional', 'Thorough'],
        timestamp: now.subtract(const Duration(days: 3)),
      ),
      Review(
        id: 'r-7', bookingId: 'b-old7', providerName: 'Provider B',
        ownerName: 'Kumar Raj', rating: 4,
        comment: 'Reliable and friendly. Pricing is fair.',
        tags: const ['Friendly', 'Value for money'],
        timestamp: now.subtract(const Duration(days: 9)),
      ),
      Review(
        id: 'r-8', bookingId: 'b-old8', providerName: 'Provider B',
        ownerName: 'Mei Lin', rating: 3,
        comment: 'Decent but missed a few spots. Would give them another try though.',
        tags: const ['Friendly'],
        timestamp: now.subtract(const Duration(days: 18)),
      ),
      Review(
        id: 'r-9', bookingId: 'b-old9', providerName: 'Provider C',
        ownerName: 'Hafiz Ahmad', rating: 4,
        comment: 'Quick turnaround. Good for small jobs.',
        tags: const ['On time', 'Value for money'],
        timestamp: now.subtract(const Duration(days: 4)),
      ),
      Review(
        id: 'r-10', bookingId: 'b-old10', providerName: 'Provider C',
        ownerName: 'Nadia Yusof', rating: 4,
        comment: 'Reliable. Will use again.',
        tags: const ['On time'],
        timestamp: now.subtract(const Duration(days: 11)),
      ),
    ];
  }
}
