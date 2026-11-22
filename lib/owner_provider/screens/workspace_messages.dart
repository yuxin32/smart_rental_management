import 'package:flutter/material.dart';
import '../services/backend/conversation_binding.dart';
import '../services/backend/supabase_backend_provider.dart';
import '../services/user_session.dart';
import '../widgets/connected_route_lifecycle.dart';
import 'chat_list_screen.dart';
import 'connected_booking_messages_screen.dart';

Future<void> openBookingMessages(BuildContext context,
    SupabaseBackendProvider backend, UserRole role, String bookingId) async {
  final navigator = Navigator.of(context);
  final messages = backend.messages;
  final userId = messages.currentUserId;
  final feed = messages.openFeed(bookingId, active: false);
  await navigator.push<void>(MaterialPageRoute(
      builder: (_) => ConnectedBookingMessagesScreen(
          bookingId: bookingId,
          currentUserId: userId,
          isProvider: role == UserRole.provider,
          pagedMessages: feed,
          bookingStatus: () => backend.bookings.watchStatus(bookingId),
          send: (token, body) => messages.send(
              bookingId: bookingId, clientMessageId: token, body: body),
          markRead: (ids) {
            if (backend.client.auth.currentUser?.id != userId)
              throw StateError('Session changed');
            return messages.markRead(bookingId, ids);
          },
          wasSent: messages.wasSent)));
}

class WorkspaceMessages extends StatefulWidget {
  const WorkspaceMessages(
      {super.key, required this.backend, required this.role});
  final SupabaseBackendProvider backend;
  final UserRole role;
  @override
  State<WorkspaceMessages> createState() => _WorkspaceMessagesState();
}

class _WorkspaceMessagesState extends State<WorkspaceMessages>
    with ConnectedRouteLifecycle<WorkspaceMessages> {
  late final ConversationBinding binding;
  @override
  void initState() {
    super.initState();
    final client = widget.backend.client;
    binding = ConversationBinding(
        load: widget.backend.messages.conversations,
        loadUnread: (search, {before, asOf}) => widget.backend.messages
            .conversations(search,
                before: before, asOf: asOf, unreadOnly: true),
        userId: client.auth.currentUser?.id ?? '',
        currentUserId: () => client.auth.currentUser?.id,
        sessions: client.auth.onAuthStateChange.map((e) => e.session?.user.id));
  }

  @override
  void onConnectedRouteActivity(bool active) => binding.setActive(active);
  @override
  void dispose() {
    binding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChatListScreen(
      binding: binding,
      isProvider: widget.role == UserRole.provider,
      onOpenConversation: (id) =>
          openBookingMessages(context, widget.backend, widget.role, id));
}
