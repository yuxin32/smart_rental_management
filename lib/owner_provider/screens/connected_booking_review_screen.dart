import 'package:flutter/material.dart';
import '../services/backend/safe_diagnostics.dart';

import '../services/backend/supabase_review_repository.dart';
import '../services/backend/connected_failure_message.dart';
import '../widgets/connected_state_panel.dart';
import '../widgets/connected_action_feedback.dart';
import '../widgets/rating_input.dart';

/// Only a Completed booking's Owner can save a review. The RPC repeats this
/// check on the server; the UI condition is only presentation.
class ConnectedBookingReviewScreen extends StatefulWidget {
  const ConnectedBookingReviewScreen({
    super.key,
    required this.bookingId,
    required this.isOwner,
    required this.load,
    required this.save,
  });

  final String bookingId;
  final bool isOwner;
  final Future<BookingReviewRecord?> Function(String) load;
  final Future<BookingReviewRecord> Function(String, int, String?) save;

  @override
  State<ConnectedBookingReviewScreen> createState() =>
      _ConnectedBookingReviewScreenState();
}

class _ConnectedBookingReviewScreenState
    extends State<ConnectedBookingReviewScreen> {
  BookingReviewRecord? _review;
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  String? _error;
  ConnectedActionNotice? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _error = null;
    });
    try {
      final review = await widget.load(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _review = review;
        _loading = false;
        _loadFailed = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
        _error = 'Could not load this booking review. Please retry.';
      });
    }
  }

  Future<void> _save(int rating, String? comment) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = const ConnectedActionNotice(
          ConnectedActionState.working,
          'Saving your review',
          'Please wait while we save your rating and comment.');
    });
    try {
      final saved = await widget.save(widget.bookingId, rating, comment);
      if (!mounted) return;
      setState(() {
        _review = saved;
        _notice = const ConnectedActionNotice(ConnectedActionState.success,
            'Review saved', 'Your review was saved.');
      });
    } catch (error) {
      SafeDiagnostics.app.record(SafeOperation.reviewSave, error);
      if (!mounted) return;
      setState(() => _notice = const ConnectedActionNotice(
          ConnectedActionState.working,
          'Checking your review',
          'We are checking whether your rating was saved before offering a retry.'));
      try {
        final verified = await widget.load(widget.bookingId);
        if (!mounted) return;
        if (verified != null &&
            verified.rating == rating &&
            (verified.comment?.trim() ?? '') == (comment?.trim() ?? '')) {
          setState(() {
            _review = verified;
            _notice = const ConnectedActionNotice(ConnectedActionState.success,
                'Review saved', 'Your review was saved.');
          });
        } else {
          setState(() => _error =
              'Your rating was not confirmed. Your draft is still here; check your connection and try again.');
        }
      } catch (lookupError) {
        SafeDiagnostics.app.record(SafeOperation.reviewVerify, lookupError);
        if (!mounted) return;
        setState(() => _error = ConnectedFailureMessage.forWrite(
              error,
              item: 'review',
            ));
      }
    } finally {
      if (mounted)
        setState(() {
          _saving = false;
          if (_error != null) {
            _notice = ConnectedActionNotice(
                ConnectedActionState.error, 'Review not confirmed', _error!);
          }
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Cleaning review')),
        body: ConnectedActionFeedbackFrame(
          notice: _notice,
          onDismiss: _saving ? null : () => setState(() => _notice = null),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  widget.isOwner ? 'How was the cleaning?' : 'Owner review',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(widget.isOwner
                    ? 'Rate this completed booking. You may update your rating later.'
                    : 'The Property Owner’s feedback for this completed booking.'),
                const SizedBox(height: 20),
                if (_loading)
                  const ConnectedStatePanel(
                    state: ConnectedViewState.loading,
                    title: 'Loading review',
                    message: 'Checking feedback for this booking.',
                  )
                else if (_loadFailed)
                  ConnectedStatePanel(
                    state: ConnectedViewState.error,
                    title: 'Could not load review',
                    message: 'Check your connection and try again.',
                    actionLabel: 'Retry',
                    onAction: _load,
                  )
                else if (widget.isOwner)
                  RatingInput(
                    key: ValueKey(
                        '${_review?.bookingId ?? 'new'}-${_review?.rating ?? 0}'),
                    initialRating: _review?.rating,
                    initialComment: _review?.comment,
                    busy: _saving,
                    onChanged: () => setState(() {
                      _notice = null;
                      _error = null;
                    }),
                    onSubmit: _save,
                  )
                else if (_review != null)
                  RatingDisplay(
                    rating: _review!.rating,
                    comment: _review!.comment,
                  )
                else
                  const ConnectedStatePanel(
                    state: ConnectedViewState.empty,
                    title: 'No review yet',
                    message:
                        'The Property Owner has not submitted a review yet.',
                  ),
              ],
            ),
          ),
        ),
      );
}
