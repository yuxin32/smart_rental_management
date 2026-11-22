// lib/screens/provider_reviews_screen.dart
// All reviews for a provider: rating breakdown + filterable list.
//
// Round 11 polish (RV1-RV5):
//   RV1 Theme colors (sem.* + AppColors.*) for text
//   RV2 Star icons use AppColors.warning (consistent with stats screen)
//   RV3 intl.DateFormat for review date
//   RV4 Tag chip uses AppColors.secondarySurface / secondaryDark
//   RV5 "No reviews" empty state uses theme
//
// Round 14 fix: wrap body in AnimatedBuilder listening to reviewStore
// so the list and breakdown refresh when a new review is added.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../models/review.dart';
import '../theme/app_theme.dart';

class ProviderReviewsScreen extends StatefulWidget {
  const ProviderReviewsScreen({super.key, required this.providerName});
  final String providerName;

  @override
  State<ProviderReviewsScreen> createState() => _ProviderReviewsScreenState();
}

class _ProviderReviewsScreenState extends State<ProviderReviewsScreen> {
  int _filter = 0; // 0 = all, 5 = 5 stars only, etc.

  @override
  Widget build(BuildContext context) {
    final store = AppProviders.of(context).reviewStore;
    final sem = SemanticColors.of(context);

    // Round 14 fix: listen to reviewStore so the breakdown refreshes
    // when a new review is added elsewhere.
    return AnimatedBuilder(
      animation: store,
      builder: (ctx, _) {
        final reviews = store.forProvider(widget.providerName);
        final avg = store.averageFor(widget.providerName);
        final dist = store.distributionFor(widget.providerName);
        final filtered = _filter == 0
            ? reviews
            : reviews.where((r) => r.rating == _filter).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Reviews'),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Share reviews',
                onPressed: () {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Sharing is unavailable for this record.'), behavior: SnackBarBehavior.floating),
                  );
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: reviews.isEmpty
              ? const EmptyReviews()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildSummary(avg, dist, reviews.length, sem),
                    const SizedBox(height: 16),
                    _buildFilterChips(sem),
                    const SizedBox(height: 8),
                    ...filtered.map((r) => _ReviewTile(review: r)),
                    if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            'No $_filter-star reviews yet',
                            style: TextStyle(color: sem.textSecondary, fontSize: 13),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildSummary(double avg, Map<int, int> dist, int total, SemanticColors sem) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      avg.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w700,
                        color: sem.textPrimary,
                        letterSpacing: -1,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: List.generate(
                        5,
                        (i) => Icon(
                          i < avg.round() ? Icons.star : Icons.star_border,
                          size: 18,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('$total review${total == 1 ? '' : 's'}',
                        style: TextStyle(fontSize: 12, color: sem.textSecondary)),
                  ],
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [5, 4, 3, 2, 1].map((star) {
                      final count = dist[star] ?? 0;
                      final pct = total == 0 ? 0.0 : count / total;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              child: Text(
                                '$star',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: sem.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(Icons.star, size: 12, color: AppColors.warning),
                            const SizedBox(width: 6),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: pct,
                                  minHeight: 6,
                                  backgroundColor: sem.border,
                                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 24,
                              child: Text('$count', style: TextStyle(fontSize: 11, color: sem.textSecondary), textAlign: TextAlign.right),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips(SemanticColors sem) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(label: 'All', value: 0, count: AppProviders.of(context).reviewStore.forProvider(widget.providerName).length, sem: sem),
          const SizedBox(width: 6),
          ...[5, 4, 3, 2, 1].map((star) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _chip(
              label: '$star★',
              value: star,
              count: AppProviders.of(context).reviewStore.forProvider(widget.providerName).where((r) => r.rating == star).length,
              sem: sem,
            ),
          )),
        ],
      ),
    );
  }

  Widget _chip({required String label, required int value, required int count, required SemanticColors sem}) {
    final selected = _filter == value;
    return InkWell(
      onTap: () => setState(() => _filter = value),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : sem.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppColors.primary : sem.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: selected ? Colors.white : sem.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: selected ? Colors.white.withOpacity(0.25) : sem.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : sem.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});
  final Review review;

  // RV3: intl date format
  String _formatDate(DateTime d) => DateFormat('d MMM y').format(d);

  String _ownerInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.secondarySurface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Text(
                      _ownerInitials(review.ownerName),
                      style: const TextStyle(color: AppColors.secondaryDark, fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(review.ownerName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: sem.textPrimary)),
                      Row(
                        children: [
                          ...List.generate(
                          5,
                          (i) => Icon(
                            i < review.rating ? Icons.star : Icons.star_border,
                            size: 12,
                            color: AppColors.warning,
                          ),
                        ),
                          const SizedBox(width: 6),
                          Text(_formatDate(review.timestamp), style: TextStyle(fontSize: 11, color: sem.textTertiary)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(review.comment, style: TextStyle(fontSize: 13, color: sem.textPrimary, height: 1.4)),
            if (review.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4, runSpacing: 4,
                children: review.tags.map((t) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.secondarySurface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    t,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondaryDark,
                    ),
                  ),
                )).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyReviews extends StatelessWidget {
  const EmptyReviews({super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.rate_review_outlined, size: 32, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text('No reviews yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: SemanticColors.of(context).textPrimary)),
          const SizedBox(height: 4),
          Text('Reviews from owners will appear here.', style: TextStyle(fontSize: 13, color: SemanticColors.of(context).textSecondary), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
