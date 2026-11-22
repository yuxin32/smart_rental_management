import 'dart:async';
import 'package:flutter/foundation.dart';
import 'conversation_page.dart';
import 'cursor_feed.dart';

typedef ConversationLoader = Future<ConversationPage> Function(String search,
    {PageCursor? before, String? asOf});

/// No mock stores, fake pins or estimated unread counts. Refreshes only while
/// visible; returning from a thread revalidates the first page silently.
class ConversationBinding extends ChangeNotifier {
  ConversationBinding(
      {required this.load,
      required this.userId,
      required this.currentUserId,
      required this.sessions,
      this.loadUnread}) {
    _createFeed();
  }
  final ConversationLoader load;
  final ConversationLoader? loadUnread;
  bool unreadOnly = false;
  int? unreadTotal;
  final String userId;
  final String? Function() currentUserId;
  final Stream<String?> sessions;
  late CursorFeed<BookingConversation> feed;
  Timer? _poll;
  bool _active = false, _disposed = false;
  bool _extended = false;
  String search = '';
  int _feedEpoch = 0;
  void _createFeed() {
    final epoch = ++_feedEpoch;
    String? boundary;
    var generation = 0;
    final query = search;
    final loader = unreadOnly && loadUnread != null ? loadUnread! : load;
    feed = CursorFeed<BookingConversation>(
        active: false,
        preserveOnRefresh: true,
        ownerUserId: userId,
        currentUserId: currentUserId,
        sessionChanges: sessions,
        idOf: (row) => row.bookingId,
        compare: (a, b) {
          final time = b.timestamp.compareTo(a.timestamp);
          return time != 0 ? time : b.bookingId.compareTo(a.bookingId);
        },
        loadPage: (before) async {
          _extended = before != null;
          if (before == null) ++generation;
          final request = generation;
          final page = await loader(query,
              before: before, asOf: before == null ? null : boundary);
          if (_disposed || epoch != _feedEpoch || currentUserId() != userId) {
            throw StateError('Conversation query/session changed');
          }
          if (request == generation && before == null) {
            boundary = page.asOf;
            unreadTotal = page.unreadTotal;
          }
          if (before != null && page.asOf != boundary) {
            throw const FormatException('Conversation snapshot changed');
          }
          return page.page;
        });
    feed.addListener(_changed);
  }

  void _changed() {
    if (_disposed) return;
    if (feed.sessionEnded) {_poll?.cancel(); unreadTotal = null;}
    notifyListeners();
  }

  void setSearch(String value) {
    final query = value.trim();
    if (_disposed || feed.sessionEnded || query == search) return;
    if (query.runes.length > 80)
      throw ArgumentError('Search must be 80 characters or fewer');
    search = query;
    feed.removeListener(_changed);
    feed.dispose();
    _createFeed();
    feed.setActive(_active);
    notifyListeners();
  }

  void setUnreadOnly(bool value) {
    if (_disposed ||
        feed.sessionEnded ||
        value == unreadOnly ||
        loadUnread == null) return;
    unreadOnly = value;
    feed.removeListener(_changed);
    feed.dispose();
    _createFeed();
    feed.setActive(_active);
    notifyListeners();
  }

  void setActive(bool active) {
    if (_disposed || active == _active) return;
    _active = active;
    _poll?.cancel();
    feed.setActive(active);
    if (active && !feed.sessionEnded) {
      _poll = Timer.periodic(const Duration(seconds: 30), (_) {
        // Do not collapse older pages while the user is reading history.
        if (!_extended && !feed.loading && !feed.loadingMore) feed.refresh();
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    feed.removeListener(_changed);
    feed.dispose();
    super.dispose();
  }
}
