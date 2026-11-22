// lib/services/message_store.dart
// In-memory store for messages and conversations. Owner ↔ Provider chat.
// Seeded with a few mock conversations so the chat UI has content on first load.

import 'package:flutter/foundation.dart';
import '../models/message.dart';

class MessageStore extends ChangeNotifier {
  MessageStore() {
    _conversations = List.of(_seedConversations());
    _messages = List.of(_seedMessages());
  }

  late List<Conversation> _conversations;
  late List<Message> _messages;

  List<Conversation> get conversations => List.unmodifiable(_conversations);
  List<Message> messagesFor(String conversationId) =>
      _messages.where((m) => m.conversationId == conversationId).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  Conversation? byId(String id) {
    try {
      return _conversations.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  int get totalUnread => _conversations.fold(0, (acc, c) => acc + c.unreadCount);

  /// Find or create a conversation between two participants for a booking.
  String findOrCreate({
    required String participantA,
    required String participantB,
    required String bookingId,
    required String property,
  }) {
    final key = [participantA, participantB]..sort();
    final existing = _conversations.firstWhere(
      (c) => ((c.participantA == key[0] && c.participantB == key[1]) ||
              (c.participantA == key[1] && c.participantB == key[0])) &&
             c.bookingId == bookingId,
      orElse: () {
        final c = Conversation(
          id: 'c-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
          participantA: key[0],
          participantB: key[1],
          bookingId: bookingId,
          property: property,
          lastMessage: '',
          lastTimestamp: DateTime.now(),
          unreadCount: 0,
        );
        _conversations = [c, ..._conversations];
        return c;
      },
    );
    return existing.id;
  }

  void send({
    required String conversationId,
    required String senderName,
    required String text,
  }) {
    if (text.trim().isEmpty) return;
    final msg = Message(
      id: 'm-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      conversationId: conversationId,
      senderName: senderName,
      text: text.trim(),
      timestamp: DateTime.now(),
      read: false,
    );
    _messages = [..._messages, msg];
    // Update conversation summary
    final i = _conversations.indexWhere((c) => c.id == conversationId);
    if (i >= 0) {
      _conversations = List.of(_conversations);
      _conversations[i] = _conversations[i].copyWith(
        lastMessage: text.trim(),
        lastTimestamp: msg.timestamp,
        unreadCount: 0,
      );
      // Re-sort by lastTimestamp
      _conversations.sort((a, b) => b.lastTimestamp.compareTo(a.lastTimestamp));
    }
    notifyListeners();
  }

  void markRead(String conversationId) {
    var changed = false;
    for (int i = 0; i < _messages.length; i++) {
      if (_messages[i].conversationId == conversationId && !_messages[i].read) {
        _messages = List.of(_messages);
        _messages[i] = _messages[i].copyWith(read: true);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  // ====================================================================
  // Seed data
  // ====================================================================

  static List<Conversation> _seedConversations() {
    final now = DateTime.now();
    return [
      Conversation(
        id: 'c-1',
        participantA: 'Oh Wan Ting', participantB: 'Provider A',
        bookingId: 'b-001',
        property: 'Unit A-12, Menara Suria',
        lastMessage: 'On the way, ETA 10 minutes.',
        lastTimestamp: now.subtract(const Duration(minutes: 8)),
        unreadCount: 2,
      ),
      Conversation(
        id: 'c-2',
        participantA: 'Oh Wan Ting', participantB: 'Provider B',
        bookingId: 'b-002',
        property: 'Unit B-08, Menara Suria',
        lastMessage: 'Sounds good, see you Saturday!',
        lastTimestamp: now.subtract(const Duration(hours: 3)),
        unreadCount: 0,
      ),
      Conversation(
        id: 'c-3',
        participantA: 'Oh Wan Ting', participantB: 'Provider C',
        bookingId: 'b-old-cleanup',
        property: 'Unit E-15, Vista Bayu',
        lastMessage: 'Thanks for the quick turnaround last time!',
        lastTimestamp: now.subtract(const Duration(days: 2)),
        unreadCount: 0,
      ),
    ];
  }

  static List<Message> _seedMessages() {
    final now = DateTime.now();
    return [
      // Conversation 1: live chat
      Message(id: 'm-1a', conversationId: 'c-1', senderName: 'Oh Wan Ting',
        text: 'Hi! Are you on the way for the Unit A-12 cleaning?',
        timestamp: now.subtract(const Duration(minutes: 30)),
        read: true),
      Message(id: 'm-1b', conversationId: 'c-1', senderName: 'Provider A',
        text: 'Yes! Just finishing the previous job, will head over next.',
        timestamp: now.subtract(const Duration(minutes: 25)),
        read: true),
      Message(id: 'm-1c', conversationId: 'c-1', senderName: 'Provider A',
        text: 'I noticed the door code in the booking notes. Let myself in?',
        timestamp: now.subtract(const Duration(minutes: 22)),
        read: true),
      Message(id: 'm-1d', conversationId: 'c-1', senderName: 'Oh Wan Ting',
        text: 'Yes that works. Please lock the door when you leave.',
        timestamp: now.subtract(const Duration(minutes: 20)),
        read: true),
      Message(id: 'm-1e', conversationId: 'c-1', senderName: 'Provider A',
        text: 'Got it. Will send before/after photos when done.',
        timestamp: now.subtract(const Duration(minutes: 15)),
        read: true),
      Message(id: 'm-1f', conversationId: 'c-1', senderName: 'Provider A',
        text: 'On the way, ETA 10 minutes.',
        timestamp: now.subtract(const Duration(minutes: 8)),
        read: false),

      // Conversation 2: scheduled
      Message(id: 'm-2a', conversationId: 'c-2', senderName: 'Oh Wan Ting',
        text: 'Hi, can you do deep cleaning for Unit B-08 next Saturday at 2pm?',
        timestamp: now.subtract(const Duration(hours: 6)),
        read: true),
      Message(id: 'm-2b', conversationId: 'c-2', senderName: 'Provider B',
        text: 'Yes, 2pm Saturday works. Booking it in now.',
        timestamp: now.subtract(const Duration(hours: 5)),
        read: true),
      Message(id: 'm-2c', conversationId: 'c-2', senderName: 'Provider B',
        text: 'I\'ll bring extra equipment for the windows. Anything else?',
        timestamp: now.subtract(const Duration(hours: 4)),
        read: true),
      Message(id: 'm-2d', conversationId: 'c-2', senderName: 'Oh Wan Ting',
        text: 'Sounds good, see you Saturday!',
        timestamp: now.subtract(const Duration(hours: 3)),
        read: true),

      // Conversation 3: past
      Message(id: 'm-3a', conversationId: 'c-3', senderName: 'Oh Wan Ting',
        text: 'Thanks for the quick turnaround last time!',
        timestamp: now.subtract(const Duration(days: 2)),
        read: true),
    ];
  }
}
