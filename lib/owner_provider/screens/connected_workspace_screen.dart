import '../presentation/workspace_text.dart';
import 'package:flutter/material.dart';
import '../services/backend/safe_diagnostics.dart';

import '../services/backend/supabase_backend_provider.dart';
import '../services/backend/connected_failure_message.dart';
import '../services/user_session.dart';
import '../widgets/cancellation_reason_sheet.dart';
import '../widgets/connected_workspace_components.dart';
import '../widgets/connected_state_panel.dart';
import '../widgets/connected_action_feedback.dart';
import '../services/backend/cursor_feed.dart';
import '../widgets/connected_paged_list.dart';
import '../widgets/connected_route_lifecycle.dart';
import 'connected_property_form_screen.dart';
import 'connected_booking_request_screen.dart';
import 'connected_provider_setup_screen.dart';
import 'connected_booking_evidence_screen.dart';
import 'connected_booking_history_sheet.dart';
import 'workspace_messages.dart';
import 'connected_booking_review_screen.dart';
import 'connected_pending_edit_screen.dart';

/// Honest connected-mode checkpoint: these cards contain only server rows.
/// The local demo's seeded Owner/Provider data is not mixed into this view.
class ConnectedWorkspaceScreen extends StatefulWidget {
  const ConnectedWorkspaceScreen({
    super.key,
    required this.backend,
    required this.role,
    this.bookingId,
  });

  final SupabaseBackendProvider backend;
  final UserRole role;

  /// Single protected booking detail, reached from the original home/inbox UI.
  final String? bookingId;

  @override
  State<ConnectedWorkspaceScreen> createState() =>
      _ConnectedWorkspaceScreenState();
}

class _ConnectedWorkspaceScreenState extends State<ConnectedWorkspaceScreen>
    with ConnectedRouteLifecycle<ConnectedWorkspaceScreen> {
  late Future<List<Map<String, dynamic>>> _properties;
  late Future<dynamic> _summary;
  CursorFeed<Map<String, dynamic>>? _bookings;
  bool _busy = false;
  Future<Map<String, dynamic>?>? _detail;
  ConnectedActionNotice? _actionNotice;

  void _showAction(ConnectedActionState state, String title, String message) {
    if (mounted) {
      setState(
        () => _actionNotice = ConnectedActionNotice(state, title, message),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    if (widget.bookingId != null) {
      _detail = widget.backend.bookings.readCard(widget.bookingId!);
      return;
    }
    _properties = widget.role == UserRole.owner
        ? widget.backend.owner.properties()
        : Future.value(const <Map<String, dynamic>>[]);
    _summary = widget.role == UserRole.owner
        ? widget.backend.owner.dashboard()
        : widget.backend.provider.profile();
    _bookings?.dispose();
    _bookings = widget.backend.bookings.openFeed(
      active: connectedRouteActive,
      provider: widget.role == UserRole.provider,
      onServerChange: () {
        if (mounted && widget.role == UserRole.owner) {
          setState(() {
            _summary = widget.backend.owner.dashboard();
          });
        }
      },
    );
  }

  @override
  void onConnectedRouteActivity(bool active) => _bookings?.setActive(active);

  @override
  void dispose() {
    _bookings?.dispose();
    super.dispose();
  }

  void _retry() => setState(_reload);

  Future<void> _signOut() async {
    try {
      await widget.backend.auth.signOut();
      if (mounted) UserSessionAccess.of(context).signOut();
    } catch (error) {
      SafeDiagnostics.app.record(SafeOperation.signOut, error);
      if (mounted) {
        _notice('Could not sign out. Check your connection and try again.');
      }
    }
  }

  Future<void> _openPropertyForm() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ConnectedPropertyFormScreen(
          onSave: (input) async {
            await widget.backend.owner.addProperty(
              unitName: input.unitName,
              buildingName: input.buildingName,
              address: input.address,
              bedrooms: input.bedrooms,
              sizeSqft: input.sizeSqft,
              cleaningWindowStart: input.cleaningWindowStart,
              cleaningWindowEnd: input.cleaningWindowEnd,
            );
          },
        ),
      ),
    );
    if (!mounted) return;
    setState(_reload);
    if (saved == true) {
      _showAction(
        ConnectedActionState.success,
        'Rental unit saved',
        'Property saved to your account.',
      );
    }
  }

  Future<void> _openProviderSetup() async {
    final provider = widget.backend.provider;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ConnectedProviderSetupScreen(
          load: provider.loadSetup,
          saveServices: provider.replaceCapabilities,
          addSlot: (weekday, start, end) => provider.addWeeklySlot(
            weekday: weekday,
            startTime: start,
            endTime: end,
          ),
          removeSlot: provider.removeWeeklySlot,
          addUnavailableDate: provider.addUnavailableDate,
          removeUnavailableDate: provider.removeUnavailableDate,
        ),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _openBookingSearch() async {
    final owner = widget.backend.owner;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ConnectedBookingRequestScreen(
          loadProperties: owner.properties,
          loadServiceTypes: owner.serviceTypes,
          findEligible: owner.eligibleProviders,
          createPending: widget.backend.bookings.createPending,
          findCreatedBooking: widget.backend.bookings.createdBookingIdForToken,
        ),
      ),
    );
    if (!mounted || saved != true) return;
    setState(_reload);
    _showAction(
      ConnectedActionState.success,
      'Cleaning request sent',
      'Pending cleaning request saved. Await Provider acceptance.',
    );
  }

  Future<void> _apply(String bookingId, String action, {String? reason}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _actionNotice = ConnectedActionNotice(
        ConnectedActionState.working,
        switch (action) {
          'Accepted' => 'Accepting cleaning request',
          'In Progress' => 'Starting cleaning',
          'Cancelled' => 'Cancelling booking',
          'Declined' => 'Declining request',
          _ => 'Updating booking',
        },
        'Please wait while we check and save this booking change.',
      );
    });
    try {
      if (action == 'Accepted') {
        final result = await widget.backend.bookings.acceptPending(bookingId);
        if (!result.accepted) {
          _showAction(
            ConnectedActionState.error,
            'Request not accepted',
            ConnectedFailureMessage.forAcceptanceReason(result.reason),
          );
        } else {
          _showAction(
            ConnectedActionState.success,
            'Request accepted',
            'This appointment is confirmed. It now reserves the provider’s time.',
          );
        }
      } else {
        await widget.backend.bookings
            .transition(bookingId, action, reason: reason);
        _showAction(
          ConnectedActionState.success,
          'Booking updated',
          'Booking updated to $action.',
        );
      }
      if (mounted) setState(_reload);
    } catch (error) {
      SafeDiagnostics.app.record(SafeOperation.bookingUpdate, error);
      _showAction(
        ConnectedActionState.working,
        'Checking booking status',
        'Checking whether the change was saved before offering a retry.',
      );
      try {
        final status = await widget.backend.bookings.currentStatus(bookingId);
        if (!mounted) return;
        if (status == action) {
          _showAction(
            ConnectedActionState.success,
            'Booking updated',
            'Booking is now $action. The result was verified.',
          );
        } else {
          _showAction(
            ConnectedActionState.error,
            'Booking change not confirmed',
            ConnectedFailureMessage.forWrite(error, item: 'booking'),
          );
        }
        setState(_reload);
      } catch (lookupError) {
        SafeDiagnostics.app.record(SafeOperation.bookingVerify, lookupError);
        if (mounted) {
          _showAction(
            ConnectedActionState.error,
            'Check booking status',
            'Could not confirm the booking status. Refresh bookings before trying again.',
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestCancellation(String bookingId) async {
    final isProvider = widget.role == UserRole.provider;
    final selection = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => CancellationReasonSheet(
        bookingId: bookingId,
        forProvider: isProvider,
      ),
    );
    if (!mounted || selection == null) return;
    final reason =
        bookingCancellationReason(selection, forProvider: isProvider);
    if (reason == null) {
      _notice('A cancellation reason is required.');
      return;
    }
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('Cancel this booking?'),
              content: Text(
                  'The booking will be closed and the other participant will be notified.\n\nReason: $reason'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Keep booking')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Confirm cancellation')),
              ],
            ));
    if (!mounted || confirmed != true) return;
    await _apply(bookingId, 'Cancelled', reason: reason);
  }

  Future<void> _editPending(Map<String, dynamic> row) async {
    final actor = widget.backend.client.auth.currentUser?.id;
    final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ConnectedPendingEditScreen(
          row: row,
          canSave: () =>
              actor != null &&
              actor == widget.backend.client.auth.currentUser?.id,
          save: (start, end, instructions) => widget.backend.bookings
              .revisePending(
                  bookingId: row['booking_id'] as String,
                  start: start,
                  end: end,
                  instructions: instructions)),
    ));
    if (mounted) {
      setState(_reload);
      if (result == true) _notice('Request changes saved.');
    }
  }

  Future<void> _showHistory(String bookingId,
      {String? ownerId, String? providerId}) async {
    final history =
        widget.backend.bookings.openHistory(bookingId, active: false);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ConnectedBookingHistorySheet(
        bookingId: bookingId,
        ownerId: ownerId,
        providerId: providerId,
        pagedHistory: history,
      ),
    );
  }

  Future<void> _openEvidence(String bookingId, String status) async {
    final evidence = widget.backend.evidence;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ConnectedBookingEvidenceScreen(
          bookingId: bookingId,
          isProvider: widget.role == UserRole.provider,
          status: status,
          load: evidence.forBooking,
          download: evidence.download,
          upload: (id, kind, bytes, token, previous) => evidence.upload(
            bookingId: id,
            kind: kind,
            bytes: bytes,
            uploadId: token,
            expectedPreviousPath: previous,
          ),
          cleanup: evidence.cleanup,
          removePhoto: evidence.removePhoto,
          saveRemarks: evidence.saveRemarks,
          complete: (id) async {
            await widget.backend.bookings.transition(id, 'Completed');
          },
          checkStatus: widget.backend.bookings.currentStatus,
        ),
      ),
    );
    if (changed == true && mounted) {
      setState(_reload);
      _showAction(
        ConnectedActionState.success,
        'Cleaning completed',
        'Booking completed. The owner can now review the evidence.',
      );
    }
  }

  Future<void> _openMessages(String bookingId) async {
    await openBookingMessages(context, widget.backend, widget.role, bookingId);
  }

  Future<void> _openReview(String bookingId) async {
    final reviews = widget.backend.reviews;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ConnectedBookingReviewScreen(
          bookingId: bookingId,
          isOwner: widget.role == UserRole.owner,
          load: reviews.forBooking,
          save: reviews.save,
        ),
      ),
    );
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _bookingCard(Map<String, dynamic> row) {
    final bookingId = row['booking_id'] as String;
    return ConnectedBookingCard(
      row: row,
      isProvider: widget.role == UserRole.provider,
      busy: _busy,
      propertyName: row['unit_name'] == null
          ? null
          : '${workspaceText(row['unit_name'] as String)}, ${workspaceText(row['building_name'] as String)}',
      onAction: (action) => _apply(bookingId, action),
      onHistory: () => _showHistory(bookingId,
          ownerId: row['owner_id'] as String?,
          providerId: row['provider_id'] as String?),
      onMessages: () => _openMessages(bookingId),
      onEvidence: () =>
          _openEvidence(bookingId, row['current_status'] as String? ?? ''),
      onReview: () => _openReview(bookingId),
      onCancel: () => _requestCancellation(bookingId),
      onEdit: () => _editPending(row),
    );
  }

  Widget _detailBody() => FutureBuilder<Map<String, dynamic>?>(
        future: _detail,
        builder: (context, snapshot) {
          if (snapshot.hasError) return _loadError();
          if (snapshot.connectionState != ConnectionState.done) {
            return const ConnectedStatePanel(
                state: ConnectedViewState.loading,
                title: 'Loading booking',
                message: 'Checking your latest booking information.');
          }
          if (snapshot.data == null) {
            return const ConnectedStatePanel(
                state: ConnectedViewState.empty,
                title: 'Booking unavailable',
                message:
                    'This booking is no longer accessible to this account.');
          }
          return _bookingCard(snapshot.data!);
        },
      );

  @override
  Widget build(BuildContext context) {
    final owner = widget.role == UserRole.owner;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.bookingId != null
            ? 'Booking details'
            : owner
                ? 'Home'
                : 'My work'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _retry,
            icon: const Icon(Icons.refresh),
          ),
          if (widget.bookingId == null)
            IconButton(
              tooltip: 'Sign out',
              onPressed: _busy ? null : _signOut,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: ConnectedActionFeedbackFrame(
        notice: _actionNotice,
        onDismiss: _busy ? null : () => setState(() => _actionNotice = null),
        actionLabel:
            !_busy && _actionNotice?.state == ConnectedActionState.error
                ? 'Refresh bookings'
                : null,
        onAction: !_busy && _actionNotice?.state == ConnectedActionState.error
            ? () => setState(() {
                  _actionNotice = null;
                  _reload();
                })
            : null,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (widget.bookingId != null)
              _detailBody()
            else ...[
              ConnectedWorkspaceHero(owner: owner),
              const SizedBox(height: 18),
              FutureBuilder<dynamic>(
                future: _summary,
                builder: (context, snapshot) {
                  if (snapshot.hasError) return _loadError();
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const ConnectedStatePanel(
                      state: ConnectedViewState.loading,
                      title: 'Loading your overview',
                      message: 'Getting your latest cleaning activity.',
                    );
                  }
                  if (owner) {
                    final value = snapshot.data;
                    return ConnectedSummaryTiles(
                      values: [
                        (
                          'Properties',
                          value.propertyCount as int,
                          Icons.apartment_outlined
                        ),
                        (
                          'Pending',
                          value.pendingCount as int,
                          Icons.hourglass_top_outlined
                        ),
                        (
                          'Active',
                          value.activeCount as int,
                          Icons.cleaning_services_outlined
                        ),
                        (
                          'Completed',
                          value.completedCount as int,
                          Icons.task_alt_outlined
                        ),
                      ],
                    );
                  }
                  final profile = snapshot.data as Map<String, dynamic>?;
                  return profile == null
                      ? ConnectedStatePanel(
                          state: ConnectedViewState.empty,
                          title: 'Provider profile not ready',
                          message:
                              'Set up your services and working hours to prepare for requests.',
                          actionLabel: 'Set up profile',
                          onAction: _openProviderSetup,
                        )
                      : ConnectedProviderProfileCard(profile: profile);
                },
              ),
              if (!owner) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _openProviderSetup,
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('Manage services & availability'),
                ),
              ],
              if (owner) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _openBookingSearch,
                  icon: const Icon(Icons.search),
                  label: const Text('New cleaning request'),
                ),
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Text(
                      'My properties',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openPropertyForm,
                      icon: const Icon(Icons.add),
                      label: const Text('Add unit'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _properties,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return _loadError();
                    if (!snapshot.hasData) {
                      return const ConnectedStatePanel(
                        state: ConnectedViewState.loading,
                        title: 'Loading your rental units',
                        message: 'Checking the units in your account.',
                      );
                    }
                    if (snapshot.data!.isEmpty) {
                      return ConnectedStatePanel(
                        state: ConnectedViewState.empty,
                        title: 'No rental units yet',
                        message:
                            'Add your first unit before requesting a cleaning service.',
                        actionLabel: 'Add rental unit',
                        onAction: _openPropertyForm,
                      );
                    }
                    return Column(
                      children: snapshot.data!
                          .map((row) => ConnectedPropertyCard(row: row))
                          .toList(),
                    );
                  },
                ),
              ],
              const SizedBox(height: 14),
              Text(
                'Bookings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 9),
              ConnectedPagedList<Map<String, dynamic>>(
                feed: _bookings!,
                embedded: true,
                moreLabel: 'Load older bookings',
                emptyTitle:
                    owner ? 'No cleaning bookings yet' : 'No jobs assigned yet',
                emptyMessage: owner
                    ? 'Find a provider to make your first cleaning request.'
                    : 'New requests will appear here when an Owner selects you.',
                emptyActionLabel:
                    owner ? 'Find providers' : 'Manage availability',
                onEmptyAction: owner ? _openBookingSearch : _openProviderSetup,
                itemBuilder: _bookingCard,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _loadError() => ConnectedStatePanel(
        state: ConnectedViewState.error,
        title: 'Could not load your information',
        message:
            'Check your connection and try again. Your saved information has not been removed.',
        actionLabel: 'Retry',
        onAction: _retry,
      );
}
