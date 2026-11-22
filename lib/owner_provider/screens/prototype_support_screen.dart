import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/prototype_support_store.dart';

class PrototypeSupportScreen extends StatefulWidget {
  const PrototypeSupportScreen({super.key, required this.store});
  final PrototypeSupportStore store;
  @override
  State<PrototypeSupportScreen> createState() => _PrototypeSupportScreenState();
}

class _PrototypeSupportScreenState extends State<PrototypeSupportScreen> {
  late final lease = widget.store.lease;
  Future<void> _open({String? id}) async {
    final key = lease;
    if (key == null || !widget.store.valid(key)) return;
    if (id == null) {
      final created = await Navigator.of(context).push<String>(
          MaterialPageRoute(
              builder: (_) => _SupportForm(store: widget.store, lease: key)));
      if (!mounted || created == null || !widget.store.valid(key)) return;
      id = created;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) =>
            _SupportDetail(store: widget.store, lease: key, id: id!)));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final key = lease;
        final active = key != null && widget.store.valid(key);
        final tickets =
            active ? widget.store.tickets(key) : <PrototypeSupportTicket>[];
        return Scaffold(
            appBar: AppBar(title: const Text('Contact support'), actions: [
              if (active && tickets.isNotEmpty)
                IconButton(
                    tooltip: 'Reset simulated tickets',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                                  title: const Text('Reset test tickets?'),
                                  content: const Text(
                                      'Only simulated tickets in this app session will be removed. Real bookings and cloud data will not change.'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(false),
                                        child: const Text('Keep')),
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(true),
                                        child: const Text('Reset'))
                                  ]));
                      if (confirm == true && widget.store.valid(key))
                        widget.store.reset(key);
                    })
            ]),
            body: !active
                ? const _SupportUnavailable()
                : ListView(padding: const EdgeInsets.all(16), children: [
                    const _PrototypeNotice(),
                    const SizedBox(height: 20),
                    Text('Your test requests',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    if (tickets.isEmpty)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Column(children: [
                            Icon(Icons.support_agent_outlined, size: 40),
                            SizedBox(height: 12),
                            Text('No simulated tickets yet'),
                            SizedBox(height: 8),
                            Text(
                                'Create a test request to try the support flow.',
                                textAlign: TextAlign.center)
                          ])),
                    for (final ticket in tickets)
                      Card(
                          child: ListTile(
                              onTap: () => _open(id: ticket.id),
                              title: Text(ticket.draft.subject,
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  '${ticket.id} · ${_status(ticket.status)}\n${ticket.draft.category}'),
                              trailing: const Icon(Icons.chevron_right))),
                  ]),
            bottomNavigationBar: !active
                ? null
                : SafeArea(
                    minimum: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                        onPressed: tickets.length >= widget.store.maxTickets
                            ? null
                            : () => _open(),
                        icon: const Icon(Icons.add),
                        label: Text(tickets.length >= widget.store.maxTickets
                            ? 'Test ticket limit reached'
                            : 'New test request'))));
      });
}

class _PrototypeNotice extends StatelessWidget {
  const _PrototypeNotice();
  @override
  Widget build(BuildContext context) => Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: const Padding(
          padding: EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PROTOTYPE · SIMULATED SUPPORT',
                style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text(
                'No email is sent and no real support team receives these requests. Test tickets stay only in memory and are cleared on sign-out, account change or app restart. Do not enter passwords, verification codes or real private information.')
          ])));
}

class _SupportUnavailable extends StatelessWidget {
  const _SupportUnavailable();
  @override
  Widget build(BuildContext context) => const Center(
      child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
              'This prototype session has ended. Return to sign in before creating or viewing test tickets.',
              textAlign: TextAlign.center)));
}

String _status(PrototypeTicketStatus status) => switch (status) {
      PrototypeTicketStatus.open => 'Open (simulated)',
      PrototypeTicketStatus.replied => 'Replied (simulated)',
      PrototypeTicketStatus.closed => 'Closed (simulated)'
    };

class _SupportForm extends StatefulWidget {
  const _SupportForm({required this.store, required this.lease});
  final PrototypeSupportStore store;
  final PrototypeSupportLease lease;
  @override
  State<_SupportForm> createState() => _SupportFormState();
}

class _SupportFormState extends State<_SupportForm> {
  final form = GlobalKey<FormState>();
  final subject = TextEditingController(),
      description = TextEditingController(),
      reference = TextEditingController();
  String category = 'Booking';
  bool acknowledged = false,
      ackError = false,
      submitting = false,
      allowPop = false,
      leaving = false;
  String? error;
  bool get dirty =>
      subject.text.isNotEmpty ||
      description.text.isNotEmpty ||
      reference.text.isNotEmpty ||
      category != 'Booking' ||
      acknowledged;
  Future<void> _leave() async {
    if (leaving || submitting) return;
    if (!dirty) {
      setState(() => allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    leaving = true;
    final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Discard this test request?'),
                content: const Text('Your unsaved description will be lost.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Keep editing')),
                  TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Discard'))
                ]));
    leaving = false;
    if (!mounted || discard != true) return;
    setState(() => allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _submit() {
    if (submitting || !widget.store.valid(widget.lease)) return;
    final valid = form.currentState!.validate();
    setState(() => ackError = !acknowledged);
    if (!valid || !acknowledged) return;
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final item = widget.store.create(
          widget.lease,
          PrototypeSupportDraft(
              category: category,
              subject: subject.text,
              description: description.text,
              bookingReference: reference.text),
          acknowledged: acknowledged);
      setState(() => allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(item.id);
      });
    } catch (_) {
      setState(() {
        submitting = false;
        error =
            'Could not save the simulated ticket. Your text is kept. Return to your test requests and check the session or ticket limit.';
      });
    }
  }

  @override
  void dispose() {
    subject.dispose();
    description.dispose();
    reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final active = widget.store.valid(widget.lease);
        return PopScope(
            canPop: allowPop || !active,
            onPopInvoked: (didPop) {
              if (!didPop) _leave();
            },
            child: Scaffold(
                appBar: AppBar(title: const Text('New test request')),
                body: !active
                    ? const _SupportUnavailable()
                    : Form(
                        key: form,
                        child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              const _PrototypeNotice(),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                  value: category,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                      labelText: 'Category'),
                                  items: PrototypeSupportDraft.categories
                                      .map((c) => DropdownMenuItem(
                                          value: c, child: Text(c)))
                                      .toList(),
                                  onChanged: submitting
                                      ? null
                                      : (v) => setState(() => category = v!)),
                              const SizedBox(height: 16),
                              TextFormField(
                                  key: const ValueKey('support-subject'),
                                  controller: subject,
                                  maxLength: 100,
                                  enabled: !submitting,
                                  decoration: const InputDecoration(
                                      labelText: 'Subject'),
                                  validator: PrototypeSupportDraft.subjectError,
                                  onChanged: (_) => setState(() {})),
                              const SizedBox(height: 16),
                              TextFormField(
                                  key: const ValueKey('support-reference'),
                                  controller: reference,
                                  maxLength: 80,
                                  enabled: !submitting,
                                  decoration: const InputDecoration(
                                      labelText: 'Booking reference (optional)',
                                      helperText:
                                          'For this test ticket only; no booking is changed.'),
                                  onChanged: (_) => setState(() {})),
                              const SizedBox(height: 16),
                              TextFormField(
                                  key: const ValueKey('support-description'),
                                  controller: description,
                                  maxLength: 2000,
                                  minLines: 5,
                                  maxLines: 10,
                                  enabled: !submitting,
                                  decoration: const InputDecoration(
                                      labelText: 'Describe the issue'),
                                  validator:
                                      PrototypeSupportDraft.descriptionError,
                                  onChanged: (_) => setState(() {})),
                              CheckboxListTile(
                                  key: const ValueKey('support-acknowledge'),
                                  contentPadding: EdgeInsets.zero,
                                  value: acknowledged,
                                  title: const Text(
                                      'I understand this is a simulated request. No email will be sent.'),
                                  onChanged: submitting
                                      ? null
                                      : (value) => setState(() {
                                            acknowledged = value ?? false;
                                            ackError = false;
                                          })),
                              if (ackError)
                                Text(
                                    'Confirm that this is a simulation before saving.',
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error)),
                              if (error != null)
                                Text(error!,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error)),
                            ])),
                bottomNavigationBar: !active
                    ? null
                    : SafeArea(
                        minimum: const EdgeInsets.all(16),
                        child: FilledButton(
                            onPressed: submitting ? null : _submit,
                            child: const Text('Save simulated ticket')))));
      });
}

class _SupportDetail extends StatelessWidget {
  const _SupportDetail(
      {required this.store, required this.lease, required this.id});
  final PrototypeSupportStore store;
  final PrototypeSupportLease lease;
  final String id;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final ticket = store.ticket(lease, id);
        return Scaffold(
            appBar: AppBar(title: Text(ticket?.id ?? 'Test request')),
            body: ticket == null
                ? const _SupportUnavailable()
                : ListView(padding: const EdgeInsets.all(16), children: [
                    const _PrototypeNotice(),
                    const SizedBox(height: 16),
                    Semantics(
                        liveRegion: true,
                        child: Text(_status(ticket.status),
                            style: Theme.of(context).textTheme.titleMedium)),
                    const SizedBox(height: 12),
                    Text(ticket.draft.subject,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                        '${ticket.draft.category} · ${DateFormat('d MMM yyyy, h:mm a').format(ticket.createdAt.toLocal())}'),
                    if (ticket.draft.bookingReference.isNotEmpty)
                      Text(
                          'Test booking reference: ${ticket.draft.bookingReference}'),
                    const SizedBox(height: 16),
                    SelectableText(ticket.draft.description),
                    const SizedBox(height: 24),
                    for (final reply in ticket.responses)
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(reply))),
                    const SizedBox(height: 16),
                    Text('Prototype controls',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                        onPressed:
                            ticket.status == PrototypeTicketStatus.closed ||
                                    ticket.responses.length >= 10
                                ? null
                                : () => store.simulateReply(lease, id),
                        icon: const Icon(Icons.science_outlined),
                        label: const Text('Simulate support reply')),
                    const SizedBox(height: 8),
                    FilledButton(
                        onPressed: () => store.setClosed(lease, id,
                            ticket.status != PrototypeTicketStatus.closed),
                        child: Text(
                            ticket.status == PrototypeTicketStatus.closed
                                ? 'Reopen test ticket'
                                : 'Close test ticket')),
                  ]));
      });
}
