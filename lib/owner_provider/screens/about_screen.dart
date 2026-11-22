// lib/screens/about_screen.dart
// App info, version, FAQ, contact support. Standard "About" page.
//
// Round 11 polish (AB1-AB3):
//   AB1 Theme colors (sem.* + AppColors.*) for FAQ text
//   AB2 ListTile trailing icon uses sem.textTertiary
//   AB3 Subtitle text uses sem.textSecondary

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../content/prototype_legal_drafts.dart';
import '../theme/app_theme.dart';
import '../services/prototype_support_store.dart';
import 'prototype_legal_draft_screen.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen(
      {super.key,
      this.environmentLabel,
      this.prototypeSupport,
      this.supportEmail = const String.fromEnvironment('SUPPORT_EMAIL')});
  final String? environmentLabel;
  final String supportEmail;
  final PrototypeSupportStore? prototypeSupport;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  bool get _draftsAvailable => canPreviewLegalDrafts(widget.environmentLabel,
      localPreview: widget.prototypeSupport?.available == true);
  final _expandedFAQs = <int>{};

  static const _faqs = [
    {
      'q': 'How are providers selected for a booking?',
      'a':
          'Booking search checks approval, cleaning service, the complete requested time interval, the property cleaning window and conflicting confirmed jobs. A Pending request does not reserve a slot. Availability and the saved quote are checked again by the server when a request is submitted or accepted.',
    },
    {
      'q': 'Can I cancel a booking after accepting?',
      'a':
          'The Owner can cancel a Pending request. Either participant can cancel an Accepted booking before work starts, with a reason. Once work is In Progress, normal cancellation is not offered. Booking details show the actions currently allowed; no automatic refund or cancellation fee is promised.',
    },
    {
      'q': 'Are recurring bookings available?',
      'a':
          'Recurring bookings are not connected. Each request is for one specific start and end time. Do not assume that another appointment has been created automatically.',
    },
    {
      'q': 'What do the Earnings amounts mean?',
      'a':
          'Completed job value uses the quote saved with each completed booking and its completion date in Malaysia time (MYT). Last 30 days is a rolling range, This month starts on the first day of the current month, and All time includes all dated completions. Platform fees, payments and payouts are not connected; these figures do not confirm money received.',
    },
    {
      'q': 'Where do I change my services and working hours?',
      'a':
          'Providers can edit their area, private service origin, contact preference and rates in Edit profile. Use Services & availability to manage cleaning services, weekly slots and blocked dates. Slots must be at least two hours, and confirmed jobs remain protected against incompatible changes.',
    },
    {
      'q': 'How do message read status and badges work?',
      'a':
          'Only received messages actually displayed in the active chat are marked read for your account. Opening the list does not clear a thread, and your own sent messages do not count as unread. Read status survives sign-in; no peer Seen indicator is shown. Foreground badges quietly recheck about every 30 seconds, not instantly through device push. Closed booking history remains readable, but new messages require Accepted or In Progress.',
    },
    {
      'q': 'Can I change the requested time?',
      'a':
          'The Owner can revise a Pending request within the supported same-duration rules. The server rechecks the property window and conflicts. A different duration needs a new priced request. Accepted bookings cannot use the Pending revision action.',
    },
    {
      'q': 'What if a save or upload loses connection?',
      'a':
          'A timeout does not prove that a write failed or succeeded. Reopen or refresh the booking or conversation to check the saved result before retrying. Do not create another request just because a response was lost. Cached content may stay visible while a refresh fails; it is not confirmation of a new save.',
    },
    {
      'q': 'Does signing out delete my data?',
      'a':
          'No. Signing out clears the App session and account-scoped memory, not cloud bookings, photos or messages. Your saved records remain in your account. Self-service account deletion and export are not complete.',
    },
    {
      'q': 'How do notifications work?',
      'a':
          'Notifications show real booking updates from the other participant. Tap an item to open the booking. Read status is saved to your account, and Needs action follows the current booking state. Pull down to refresh. Phone push notifications, payment alerts and review alerts are not enabled.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About & help')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // App brand card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.apartment,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Smart Rental',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Owner & Cleaning Service Provider',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Manage properties and cleaning in one place',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Quick links
          Card(
            child: Column(
              children: [
                _tile(
                    context,
                    Icons.help_outline,
                    'Help center',
                    'Booking, availability and earnings guides',
                    () => _article(
                        'Help center',
                        _faqs
                            .map((f) => '${f['q']}\n\n${f['a']}')
                            .join('\n\n————\n\n'))),
                _divider(sem),
                if (widget.supportEmail.trim().isNotEmpty) ...[
                  _tile(context, Icons.chat_bubble_outline, 'Contact support',
                      widget.supportEmail.trim(), _contact),
                  _divider(sem),
                ],
                _tile(
                    context,
                    Icons.description_outlined,
                    'Terms of service',
                    _draftsAvailable
                        ? 'Service information · Review pending'
                        : 'Not published yet',
                    () => _legal(LegalDraftKind.terms)),
                _divider(sem),
                _tile(
                    context,
                    Icons.privacy_tip_outlined,
                    'Privacy policy',
                    _draftsAvailable
                        ? 'How your data is used · Review pending'
                        : 'Not published yet',
                    () => _legal(LegalDraftKind.privacy)),
              ],
            ),
          ),

          const SizedBox(height: 24),
          Text(
            'FREQUENTLY ASKED',
            style: TextStyle(
                fontSize: 11,
                color: sem.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          ..._faqs.asMap().entries.map((e) => _buildFAQ(e.key, e.value, sem)),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Smart Rental Manager · Cleaning made easier',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: sem.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext ctx, IconData icon, String title, String? subtitle,
      VoidCallback? onTap) {
    final sem = SemanticColors.of(ctx);
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 18, color: AppColors.primary),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: sem.textPrimary,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: sem.textSecondary),
            )
          : null,
      trailing: Icon(
        Icons.arrow_forward_ios,
        size: 12,
        color: sem.textTertiary,
      ),
      onTap: onTap,
    );
  }

  void _article(String title, String content) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(
              appBar: AppBar(title: Text(title)),
              body: ListView(padding: const EdgeInsets.all(20), children: [
                SelectableText(content, style: const TextStyle(height: 1.6))
              ]))));

  void _legal(LegalDraftKind kind) {
    final draft = PrototypeLegalDraft.forKind(kind);
    if (!_draftsAvailable) {
      _article(draft.title, draft.notice);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PrototypeLegalDraftScreen(
            kind: kind,
            environmentLabel: widget.environmentLabel,
            localPreview: widget.prototypeSupport?.available == true)));
  }

  Future<void> _contact() async {
    final email = widget.supportEmail.trim();
    await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
                scrollable: true,
                title: const Text('Contact support'),
                content: SelectableText(email.isEmpty
                    ? 'A support contact has not been configured. No support request has been sent.'
                    : 'Email $email with the issue, approximate time and booking reference if relevant. Never send your password, verification code or private access keys. No response time is guaranteed.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Close')),
                  if (email.isNotEmpty)
                    TextButton(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: email));
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Support email copied. Send your message from your email app.')));
                        },
                        child: const Text('Copy email'))
                ]));
  }

  Widget _divider(SemanticColors sem) =>
      Divider(height: 1, color: sem.border, indent: 60);

  Widget _buildFAQ(int idx, Map<String, String> faq, SemanticColors sem) {
    final isOpen = _expandedFAQs.contains(idx);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: sem.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sem.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              if (isOpen) {
                _expandedFAQs.remove(idx);
              } else {
                _expandedFAQs.add(idx);
              }
            }),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      faq['q']!,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: sem.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    isOpen ? Icons.expand_less : Icons.expand_more,
                    color: sem.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (isOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text(
                faq['a']!,
                style: TextStyle(
                    fontSize: 13, color: sem.textSecondary, height: 1.5),
              ),
            ),
        ],
      ),
    );
  }
}
