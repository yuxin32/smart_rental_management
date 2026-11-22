import 'package:flutter/foundation.dart';

enum PrototypeTicketStatus { open, replied, closed }

class PrototypeSupportLease {
  const PrototypeSupportLease(this.account, this.epoch);
  final String account;
  final int epoch;
}

class PrototypeSupportDraft {
  const PrototypeSupportDraft(
      {required this.category,
      required this.subject,
      required this.description,
      this.bookingReference = ''});
  static const categories = [
    'Booking',
    'Account',
    'Earnings',
    'App issue',
    'Other'
  ];
  final String category, subject, description, bookingReference;
  static String? subjectError(String? value) => (value ?? '').trim().length < 5
      ? 'Enter at least 5 characters.'
      : (value ?? '').trim().length > 100
          ? 'Use 100 characters or fewer.'
          : null;
  static String? descriptionError(String? value) =>
      (value ?? '').trim().length < 20
          ? 'Describe the issue in at least 20 characters.'
          : (value ?? '').trim().length > 2000
              ? 'Use 2000 characters or fewer.'
              : null;
  bool get valid =>
      categories.contains(category) &&
      subjectError(subject) == null &&
      descriptionError(description) == null &&
      bookingReference.trim().length <= 80;
}

class PrototypeSupportTicket {
  const PrototypeSupportTicket(
      {required this.id,
      required this.draft,
      required this.createdAt,
      this.status = PrototypeTicketStatus.open,
      this.responses = const []});
  final String id;
  final PrototypeSupportDraft draft;
  final DateTime createdAt;
  final PrototypeTicketStatus status;
  final List<String> responses;
  PrototypeSupportTicket copy(
          {PrototypeTicketStatus? status, List<String>? responses}) =>
      PrototypeSupportTicket(
          id: id,
          draft: draft,
          createdAt: createdAt,
          status: status ?? this.status,
          responses: responses ?? this.responses);
}

/// MEMORY ONLY. No mail, HTTP, Supabase, device storage, attachment or log sink.
/// Explicitly enabled only for local preview / Staging by the composition root.
class PrototypeSupportStore extends ChangeNotifier {
  PrototypeSupportStore(
      {required this.enabled, this.maxTickets = 30, DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final bool enabled;
  final int maxTickets;
  final DateTime Function() _now;
  String? _account;
  int _epoch = 0, _sequence = 0;
  bool _disposed = false;
  final _tickets = <String, PrototypeSupportTicket>{};
  bool get available => enabled && !_disposed && _account != null;
  void bindSession(String? account) {
    if (_disposed || account == _account) return;
    _account = account;
    ++_epoch;
    _tickets.clear();
    notifyListeners();
  }

  PrototypeSupportLease? get lease =>
      available ? PrototypeSupportLease(_account!, _epoch) : null;
  bool valid(PrototypeSupportLease lease) =>
      available && lease.account == _account && lease.epoch == _epoch;
  void _check(PrototypeSupportLease lease) {
    if (!valid(lease)) throw StateError('Prototype session ended.');
  }

  List<PrototypeSupportTicket> tickets(PrototypeSupportLease lease) =>
      valid(lease)
          ? List.unmodifiable(_tickets.values.toList().reversed)
          : const [];
  PrototypeSupportTicket? ticket(PrototypeSupportLease lease, String id) =>
      valid(lease) ? _tickets[id] : null;
  PrototypeSupportTicket create(
      PrototypeSupportLease lease, PrototypeSupportDraft draft,
      {required bool acknowledged}) {
    _check(lease);
    if (!acknowledged || !draft.valid)
      throw ArgumentError('Check simulated ticket fields.');
    if (_tickets.length >= maxTickets)
      throw StateError('Prototype ticket limit reached.');
    final ticket = PrototypeSupportTicket(
        id: 'SIM-${(++_sequence).toString().padLeft(4, '0')}',
        createdAt: _now().toUtc(),
        draft: PrototypeSupportDraft(
            category: draft.category,
            subject: draft.subject.trim(),
            description: draft.description.trim(),
            bookingReference: draft.bookingReference.trim()));
    _tickets[ticket.id] = ticket;
    notifyListeners();
    return ticket;
  }

  void simulateReply(PrototypeSupportLease lease, String id) {
    _check(lease);
    final item = _tickets[id];
    if (item == null ||
        item.status == PrototypeTicketStatus.closed ||
        item.responses.length >= 10)
      throw StateError('Test reply unavailable.');
    _tickets[id] = item.copy(
        status: PrototypeTicketStatus.replied,
        responses: List.unmodifiable([
          ...item.responses,
          'Simulated support response: We have reviewed this test issue. This is a demonstration only; no real support team received this ticket.'
        ]));
    notifyListeners();
  }

  void setClosed(PrototypeSupportLease lease, String id, bool closed) {
    _check(lease);
    final item = _tickets[id];
    if (item == null) throw StateError('Test ticket unavailable.');
    _tickets[id] = item.copy(
        status:
            closed ? PrototypeTicketStatus.closed : PrototypeTicketStatus.open);
    notifyListeners();
  }

  void reset(PrototypeSupportLease lease) {
    _check(lease);
    _tickets.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _tickets.clear();
    _account = null;
    ++_epoch;
    super.dispose();
  }
}
