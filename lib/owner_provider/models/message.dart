// lib/models/message.dart

class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderName,
    required this.text,
    required this.timestamp,
    this.read = true,
  });
  final String id;
  final String conversationId;
  final String senderName;
  final String text;
  final DateTime timestamp;
  final bool read;

  Message copyWith({bool? read}) {
    return Message(
      id: id, conversationId: conversationId, senderName: senderName,
      text: text, timestamp: timestamp, read: read ?? this.read,
    );
  }
}

class Conversation {
  const Conversation({
    required this.id,
    required this.participantA,
    required this.participantB,
    required this.bookingId,
    required this.property,
    required this.lastMessage,
    required this.lastTimestamp,
    required this.unreadCount,
  });
  final String id;
  final String participantA;
  final String participantB;
  final String bookingId;
  final String property;
  final String lastMessage;
  final DateTime lastTimestamp;
  final int unreadCount;

  String get counterpartA => participantA;
  String get counterpartB => participantB;

  Conversation copyWith({String? lastMessage, DateTime? lastTimestamp, int? unreadCount}) {
    return Conversation(
      id: id, participantA: participantA, participantB: participantB,
      bookingId: bookingId, property: property,
      lastMessage: lastMessage ?? this.lastMessage,
      lastTimestamp: lastTimestamp ?? this.lastTimestamp,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}
