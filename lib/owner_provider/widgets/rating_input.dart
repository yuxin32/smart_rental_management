// lib/widgets/rating_input.dart
// 1-5 star rating picker with optional comment field.
//
// F2 helper widget. Used on the owner-side booking detail when status is
// [BookingStatus.completed] and the owner has not yet submitted a rating.
//
// Submit returns the chosen star count and optional comment via [onSubmit].
// Tap a star to set the rating. Stars from index 0..rating-1 are filled.

import 'package:flutter/material.dart';

class RatingInput extends StatefulWidget {
  const RatingInput({
    super.key,
    this.initialRating,
    this.initialComment,
    this.onSubmit,
    this.compact = false,
    this.busy = false,
    this.onChanged,
  });

  /// Pre-fill the rating (e.g., when re-rendering after submission).
  final int? initialRating;

  /// Pre-fill the comment text.
  final String? initialComment;

  /// Called when the user taps "Submit rating".
  /// The rating must be 1..5; the comment may be null or empty.
  final void Function(int rating, String? comment)? onSubmit;

  /// Use a smaller visual size (e.g., for embedding in a card).
  final bool compact;
  final bool busy;
  final VoidCallback? onChanged;

  @override
  State<RatingInput> createState() => _RatingInputState();
}

class _RatingInputState extends State<RatingInput> {
  late int _rating;
  late TextEditingController _comment;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating ?? 0;
    _comment = TextEditingController(text: widget.initialComment ?? '');
  }

  @override
  void didUpdateWidget(covariant RatingInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialRating != null &&
        widget.initialRating != oldWidget.initialRating) {
      _rating = widget.initialRating!;
    }
    if (widget.initialComment != null &&
        widget.initialComment != oldWidget.initialComment) {
      _comment.text = widget.initialComment!;
    }
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final starSize = widget.compact ? 28.0 : 36.0;
    final canSubmit = _rating >= 1 && _rating <= 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: List.generate(5, (i) {
            final filled = i < _rating;
            return IconButton(
              padding: const EdgeInsets.all(4),
              constraints: BoxConstraints.tightFor(
                width: starSize + 12,
                height: starSize + 12,
              ),
              icon: Icon(
                filled ? Icons.star_rounded : Icons.star_outline_rounded,
                color: filled
                    ? const Color(0xFFF59E0B) // amber-500
                    : const Color(0xFFD1D5DB),
                size: starSize,
              ),
              onPressed: widget.busy
                  ? null
                  : () {
                      setState(() => _rating = i + 1);
                      widget.onChanged?.call();
                    },
            );
          }),
        ),
        const SizedBox(height: 4),
        Text(
          _rating == 0 ? 'Tap a star to rate' : '$_rating / 5 stars',
          style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _comment,
          onChanged: (_) => widget.onChanged?.call(),
          enabled: _rating > 0 && !widget.busy,
          maxLines: 3,
          maxLength: 300,
          decoration: const InputDecoration(
            labelText: 'Comment (optional)',
            hintText: 'How was the cleaning?',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        if (widget.onSubmit != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canSubmit && !widget.busy
                  ? () {
                      final text = _comment.text.trim();
                      widget.onSubmit!(
                        _rating,
                        text.isEmpty ? null : text,
                      );
                    }
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
              ),
              child: Text(
                widget.busy
                    ? 'Saving rating…'
                    : widget.initialRating != null
                        ? 'Update rating'
                        : 'Submit rating',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Static read-only display of a 1-5 star rating. Used when the booking is
/// already rated and we just need to show the value.
class RatingDisplay extends StatelessWidget {
  const RatingDisplay({
    super.key,
    required this.rating,
    this.comment,
    this.compact = false,
  });

  final int rating;
  final String? comment;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final starSize = compact ? 18.0 : 22.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: List.generate(5, (i) {
            final filled = i < rating;
            return Icon(
              filled ? Icons.star_rounded : Icons.star_outline_rounded,
              color: filled ? const Color(0xFFF59E0B) : const Color(0xFFD1D5DB),
              size: starSize,
            );
          }),
        ),
        const SizedBox(width: 8),
        Text(
          '$rating / 5',
          style: TextStyle(
            fontSize: compact ? 12 : 14,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF374151),
          ),
        ),
        if (comment != null && comment!.isNotEmpty) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '"$comment"',
              style: TextStyle(
                fontSize: compact ? 12 : 13,
                fontStyle: FontStyle.italic,
                color: const Color(0xFF6B7280),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}
