import '../presentation/workspace_text.dart';
import 'package:flutter/material.dart';
import '../services/backend/safe_diagnostics.dart';
import '../services/backend/booking_rate_limit.dart';
import '../widgets/rate_limit_notice.dart';

import '../services/backend/supabase_message_repository.dart';
import '../services/backend/connected_failure_message.dart';
import '../widgets/connected_state_panel.dart';
import '../services/backend/cursor_feed.dart';
import '../widgets/connected_paged_list.dart';
import '../widgets/connected_route_lifecycle.dart';
import '../widgets/lifecycle_stream_builder.dart';
import '../widgets/visible_message_receipt.dart';
import '../services/backend/message_unread_binding.dart';

/// Booking-scoped conversation. Server RLS protects reads and the send RPC
/// rechecks both participant identity and the current booking state.
class ConnectedBookingMessagesScreen extends StatefulWidget {
  const ConnectedBookingMessagesScreen({
    super.key,
    required this.bookingId,
    required this.currentUserId,
    required this.isProvider,
    this.messages,
    this.pagedMessages,
    required this.bookingStatus,
    required this.send,
    required this.wasSent,
    this.markRead,
  }) : assert(messages != null || pagedMessages != null);

  final String bookingId;
  final String currentUserId;
  final bool isProvider;
  final Stream<List<BookingMessage>> Function()? messages;
  final CursorFeed<BookingMessage>? pagedMessages;
  final Stream<String?> Function() bookingStatus;
  final Future<void> Function(String clientMessageId, String body) send;
  final Future<bool> Function(String bookingId, String clientMessageId) wasSent;
  final Future<void> Function(List<String>)? markRead;

  @override
  State<ConnectedBookingMessagesScreen> createState() =>
      _ConnectedBookingMessagesScreenState();
}

class _ConnectedBookingMessagesScreenState
    extends State<ConnectedBookingMessagesScreen>
    with ConnectedRouteLifecycle<ConnectedBookingMessagesScreen> {
  final _controller = TextEditingController();
  final _ratePause = ActionRatePause();
  String? _pendingText;
  String? _pendingToken;
  String? _error;
  bool _sending = false;
  bool _serverClosed = false;
  String? _latestStatus;
  late Stream<List<BookingMessage>> Function() _messages;
  late Stream<String?> Function() _status;
  VisibleMessageReads? _reads;

  @override
  void initState() {
    super.initState();
    _messages = widget.messages ?? () => const Stream.empty();
    _status = widget.bookingStatus;
    _ratePause.addListener(_onRatePause);
    if (widget.markRead != null) _reads = VisibleMessageReads(widget.markRead!);
  }

  @override
  void onConnectedRouteActivity(bool active) {
    widget.pagedMessages?.setActive(active);
    _reads?.setActive(active);
    setState(() => _latestStatus = null);
  }

  void _retryMessages() => setState(() {
        widget.pagedMessages?.refresh();
        _messages = () => widget.messages?.call() ?? const Stream.empty();
        _status = () => widget.bookingStatus();
        _latestStatus = null;
      });

  @override
  void dispose() {
    _ratePause.removeListener(_onRatePause);
    _ratePause.dispose();
    widget.pagedMessages?.dispose();
    _reads?.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool get _canSend =>
      connectedRouteActive &&
      widget.pagedMessages?.sessionEnded != true &&
      !_serverClosed &&
      (_latestStatus == 'Accepted' || _latestStatus == 'In Progress');

  Future<void> _send() async {
    if (_sending || !_canSend || _ratePause.active) return;
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    if (body.length > 2000) {
      setState(() => _error = 'Messages must be 2,000 characters or fewer.');
      return;
    }
    if (_pendingText != body) {
      _pendingText = body;
      _pendingToken = ClientMessageToken.newV4();
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.send(_pendingToken!, body);
      if (!mounted) return;
      _controller.clear();
      _pendingText = null;
      _pendingToken = null;
      widget.pagedMessages?.refresh();
    } catch (error) {
      if (!mounted) return;
      SafeDiagnostics.app.record(SafeOperation.messageSend, error);
      if (error is ServerActionLimit &&
          error.action == BookingLimitedAction.message) {
        _ratePause.start(error);
        return; // Definite rejection: do not label this an uncertain send.
      }
      try {
        final verified = await widget.wasSent(widget.bookingId, _pendingToken!);
        if (!mounted) return;
        if (verified) {
          _controller.clear();
          _pendingText = null;
          _pendingToken = null;
          setState(() {
            _error = null;
            widget.pagedMessages?.refresh();
            _messages = () => widget.messages?.call() ?? const Stream.empty();
          });
          return;
        }
      } catch (lookupError) {
        SafeDiagnostics.app.record(SafeOperation.messageVerify, lookupError);
      }
      if (!mounted) return;
      final closed = error.toString().contains('Messages are closed');
      setState(() {
        if (closed) _serverClosed = true;
        _error = closed
            ? 'This booking is no longer open for new messages. Your draft remains here.'
            : '${ConnectedFailureMessage.forWrite(error, item: 'message')} Your draft is kept; retrying will use the same message ID.';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _onRatePause() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LifecycleStreamBuilder<String?>(
      activity: connectedRouteActivity,
      open: _status,
      builder: (context, statusSnapshot) {
        if (statusSnapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Booking messages')),
            body: ConnectedStatePanel(
              state: ConnectedViewState.error,
              title: 'Could not check this booking',
              message:
                  'Message access depends on the current booking status. Check your connection and try again.',
              actionLabel: 'Retry',
              onAction: _retryMessages,
            ),
          );
        }
        _latestStatus = connectedRouteActive &&
                (statusSnapshot.connectionState == ConnectionState.active ||
                    statusSnapshot.connectionState == ConnectionState.done)
            ? statusSnapshot.data
            : null;
        final canSend = _canSend && !statusSnapshot.hasError;
        final checkingStatus = connectedRouteActive &&
            statusSnapshot.connectionState == ConnectionState.waiting;
        return Scaffold(
          appBar: AppBar(title: const Text('Booking messages')),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 520;
              return Column(
                children: [
                  if (!compact || !canSend)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      color: scheme.primaryContainer,
                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 18,
                            color: scheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              checkingStatus
                                  ? 'Checking the latest booking status…'
                                  : canSend
                                      ? 'Private conversation with your ${widget.isProvider ? 'Property Owner' : 'Cleaning Service Provider'}'
                                      : 'Conversation is read-only for this booking',
                              style:
                                  TextStyle(color: scheme.onPrimaryContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: compact && canSend && _ratePause.limit != null
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: RateLimitNotice(limit: _ratePause.limit!),
                          )
                        : widget.pagedMessages != null
                            ? ConnectedPagedList<BookingMessage>(
                                feed: widget.pagedMessages!,
                                itemBuilder: _bubble,
                                reverse: true,
                                showCount: false,
                                emptyTitle: 'No messages yet',
                                emptyMessage:
                                    'Use this space for booking instructions and coordination.',
                                errorTitle: 'Could not load messages',
                                moreLabel: 'Load older messages',
                              )
                            : LifecycleStreamBuilder<List<BookingMessage>>(
                                activity: connectedRouteActivity,
                                open: _messages,
                                builder: (context, snapshot) {
                                  if (snapshot.hasError) {
                                    return ConnectedStatePanel(
                                      state: ConnectedViewState.error,
                                      title: 'Could not load messages',
                                      message:
                                          'Check your connection and try again. Your unsent text will remain here.',
                                      actionLabel: 'Retry',
                                      onAction: _retryMessages,
                                    );
                                  }
                                  if (!snapshot.hasData) {
                                    return const ConnectedStatePanel(
                                      state: ConnectedViewState.loading,
                                      title: 'Loading messages',
                                      message:
                                          'Opening this booking conversation.',
                                    );
                                  }
                                  final messages = snapshot.data!;
                                  if (messages.isEmpty) {
                                    return const ConnectedStatePanel(
                                      state: ConnectedViewState.empty,
                                      title: 'No messages yet',
                                      message:
                                          'Use this space for booking instructions and coordination.',
                                    );
                                  }
                                  return ListView.builder(
                                    reverse: true,
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      16,
                                      16,
                                      12,
                                    ),
                                    itemCount: messages.length,
                                    itemBuilder: (context, index) => _bubble(
                                      messages[messages.length - 1 - index],
                                    ),
                                  );
                                },
                              ),
                  ),
                  if (!compact && canSend && _ratePause.limit != null)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * 0.3,
                      ),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          child: RateLimitNotice(limit: _ratePause.limit!),
                        ),
                      ),
                    ),
                  if (_error != null)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * 0.3,
                      ),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: Text(
                            _error!,
                            style: TextStyle(color: scheme.error),
                          ),
                        ),
                      ),
                    ),
                  if (canSend)
                    ConstrainedBox(
                      constraints:
                          BoxConstraints(maxHeight: constraints.maxHeight),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _controller,
                                  enabled: !_sending,
                                  minLines: 1,
                                  maxLines: compact ? 2 : 4,
                                  maxLength: 2000,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  decoration: const InputDecoration(
                                    labelText: 'Message',
                                    hintText: 'Write a booking message',
                                    border: OutlineInputBorder(),
                                    counterText: '',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filled(
                                tooltip: 'Send message',
                                onPressed: _sending || _ratePause.active
                                    ? null
                                    : _send,
                                icon: _sending
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.send_rounded),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _bubble(BookingMessage message) {
    final bubble = _messageBubble(message);
    if (_reads == null || message.senderUserId == widget.currentUserId)
      return bubble;
    return VisibleMessageReceipt(
        onVisible: () {
          if (mounted &&
              connectedRouteActive &&
              widget.pagedMessages?.sessionEnded != true)
            _reads?.seen(message.id);
        },
        child: bubble);
  }

  Widget _messageBubble(BookingMessage message) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.senderUserId == widget.currentUserId;
    final malaysia = message.createdAt.toUtc().add(const Duration(hours: 8));
    final time =
        TimeOfDay(hour: malaysia.hour, minute: malaysia.minute).format(context);
    final day = '${malaysia.day}/${malaysia.month}/${malaysia.year}';
    final sender = mine
        ? 'You'
        : widget.isProvider
            ? 'Property Owner'
            : 'Provider';
    return Semantics(
      container: true,
      label:
          'Message from $sender, $day at $time MYT: ${workspaceText(message.body)}',
      child: ExcludeSemantics(
        child: Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 290),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: mine ? scheme.primary : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mine
                        ? 'You'
                        : widget.isProvider
                            ? 'Property Owner'
                            : 'Provider',
                    style: TextStyle(
                      color: mine ? scheme.onPrimary : scheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    workspaceText(message.body),
                    style: TextStyle(
                      color: mine ? scheme.onPrimary : scheme.onSurface,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$day · $time MYT',
                    style: TextStyle(
                      color: mine
                          ? scheme.onPrimary.withOpacity(0.75)
                          : scheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
