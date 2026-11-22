import 'dart:async';
import '../main.dart';
import 'package:flutter/material.dart';
import '../services/backend/message_unread_binding.dart';
import '../services/backend/supabase_backend_provider.dart';
import '../services/user_session.dart';

class MessageUnreadScope extends InheritedNotifier<MessageUnreadBinding> {
  const MessageUnreadScope(
      {super.key, required MessageUnreadBinding binding, required super.child})
      : super(notifier: binding);
  static MessageUnreadBinding? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<MessageUnreadScope>()
      ?.notifier;
}

/// Above Navigator: one session-scoped foreground poller shared by all routes.
class MessageUnreadHost extends StatefulWidget {
  const MessageUnreadHost(
      {super.key,
      required this.backend,
      required this.session,
      required this.child});
  final SupabaseBackendProvider? backend;
  final UserSession session;
  final Widget child;
  @override
  State<MessageUnreadHost> createState() => _MessageUnreadHostState();
}

class _MessageUnreadHostState extends State<MessageUnreadHost>
    with WidgetsBindingObserver {
  MessageUnreadBinding? _binding;
  StreamSubscription<dynamic>? _auth;
  bool _resumed = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resumed = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    widget.session.addListener(_sync);
    _auth = widget.backend?.client.auth.onAuthStateChange.listen((_) => _sync(),
        onError: (Object _) {
      // Transient refresh errors are not an identity change; retain verified UI.
    });
    _sync();
  }

  void _sync() {
    final backend = widget.backend;
    final id =
        widget.session.isLoggedIn && backend?.recovery?.blocksWorkspace != true
            ? backend?.client.auth.currentUser?.id
            : null;
    if (_binding?.userId != id) {
      _binding?.dispose();
      _binding = null;
      if (id != null && backend != null) {
        _binding = MessageUnreadBinding(
            load: backend.messages.unread,
            userId: id,
            currentUserId: () => backend.client.auth.currentUser?.id,
            sessions: backend.client.auth.onAuthStateChange
                .map((s) => s.session?.user.id),
            changes: backend.messages.changes);
      }
      if (mounted) setState(() {});
    }
    _binding?.setActive(_resumed);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _binding?.setActive(_resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_sync);
    unawaited(_auth?.cancel() ?? Future<void>.value());
    _binding?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _binding == null
      ? widget.child
      : MessageUnreadScope(binding: _binding!, child: widget.child);
}

class MessageUnreadBadge extends StatelessWidget {
  const MessageUnreadBadge({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final preferences = AppProviders.maybeOf(context)?.devicePreferences;
    return AnimatedBuilder(
        animation: Listenable.merge([if (preferences != null) preferences]),
        builder: (context, _) =>
            _badge(context, preferences?.messageIndicators != false));
  }

  Widget _badge(BuildContext context, bool enabled) {
    final binding = MessageUnreadScope.maybeOf(context);
    final count = binding?.count;
    if (!enabled || count == null || count == 0) return child;
    return Semantics(
        label:
            '$count unread messages${binding!.failed ? ', last confirmed count' : ''}',
        child: Badge(label: Text(count > 99 ? '99+' : '$count'), child: child));
  }
}
