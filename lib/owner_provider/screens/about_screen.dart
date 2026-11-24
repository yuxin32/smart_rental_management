import 'package:flutter/material.dart';

import '../content/prototype_legal_drafts.dart';
import '../services/prototype_support_store.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_section_card.dart';
import 'prototype_legal_draft_screen.dart';

typedef _HelpQuestion = ({String title, String answer});

class AboutScreen extends StatelessWidget {
  const AboutScreen({
    super.key,
    this.environmentLabel,
    this.prototypeSupport,
  });

  final String? environmentLabel;
  final PrototypeSupportStore? prototypeSupport;

  bool get _draftsAvailable => canPreviewLegalDrafts(
        environmentLabel,
        localPreview: prototypeSupport?.available == true,
      );

  static const _topics = [
    (
      title: 'Bookings',
      subtitle: 'Find a provider, change or cancel a request',
      icon: Icons.event_note_outlined,
      questions: <_HelpQuestion>[
        (
          title: 'How are providers selected for a booking?',
          answer:
              'Booking search checks approval, cleaning service, the complete requested time interval, the property cleaning window and conflicting confirmed jobs. A Pending request does not reserve a slot. Availability and the saved quote are checked again by the server when a request is submitted or accepted.'
        ),
        (
          title: 'Can I change the requested time?',
          answer:
              'The Owner can revise a Pending request within the supported same-duration rules. The server rechecks the property window and conflicts. A different duration needs a new priced request. Accepted bookings cannot use the Pending revision action.'
        ),
        (
          title: 'Can I cancel a booking after accepting?',
          answer: 'The Owner can cancel a Pending request.\n\n'
              'Either person can cancel an Accepted booking before work starts. A reason is required.\n\n'
              'Once work starts, standard cancellation is unavailable. Check Booking details for your options. Refunds and cancellation fees aren’t automatic.'
        ),
        (
          title: 'Are recurring bookings available?',
          answer:
              'Recurring bookings are not connected. Each request is for one specific start and end time. Do not assume that another appointment has been created automatically.'
        ),
      ],
    ),
    (
      title: 'Provider work',
      subtitle: 'Services, working hours and earnings',
      icon: Icons.cleaning_services_outlined,
      questions: <_HelpQuestion>[
        (
          title: 'Where do I change my services and working hours?',
          answer:
              'Providers can edit their area, private service origin, contact preference and rates in Edit profile. Use Services & availability to manage cleaning services, weekly slots and blocked dates. Slots must be at least two hours, and confirmed jobs remain protected against incompatible changes.'
        ),
        (
          title: 'What do the Earnings amounts mean?',
          answer:
              'Completed job value uses the quote saved with each completed booking and its completion date in Malaysia time (MYT). Last 30 days is a rolling range, This month starts on the first day of the current month, and All time includes all dated completions. Platform fees, payments and payouts are not connected; these figures do not confirm money received.'
        ),
      ],
    ),
    (
      title: 'Messages & notifications',
      subtitle: 'Unread messages and booking updates',
      icon: Icons.chat_bubble_outline,
      questions: <_HelpQuestion>[
        (
          title: 'How do message read status and badges work?',
          answer:
              'Only received messages actually displayed in the active chat are marked read for your account. Opening the list does not clear a thread, and your own sent messages do not count as unread. Read status survives sign-in; no peer Seen indicator is shown. Foreground badges quietly recheck about every 30 seconds, not instantly through device push. Closed booking history remains readable, but new messages require Accepted or In Progress.'
        ),
        (
          title: 'How do notifications work?',
          answer:
              'Notifications show real booking updates from the other participant. Tap an item to open the booking. Read status is saved to your account, and Needs action follows the current booking state. Pull down to refresh. Phone push notifications, payment alerts and review alerts are not enabled.'
        ),
      ],
    ),
    (
      title: 'Account & troubleshooting',
      subtitle: 'Signing out and connection issues',
      icon: Icons.manage_accounts_outlined,
      questions: <_HelpQuestion>[
        (
          title: 'Does signing out delete my data?',
          answer:
              'No. Signing out clears the App session and account-scoped memory, not cloud bookings, photos or messages. Your saved records remain in your account. Self-service account deletion and export are not complete.'
        ),
        (
          title: 'What if a save or upload loses connection?',
          answer:
              'A timeout does not prove that a write failed or succeeded. Reopen or refresh the booking or conversation to check the saved result before retrying. Do not create another request just because a response was lost. Cached content may stay visible while a refresh fails; it is not confirmation of a new save.'
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColors.of(context);
    final divider =
        Divider(height: 1, indent: 56, endIndent: 16, color: colors.border);
    return Scaffold(
      appBar: AppBar(title: const Text('About & help')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SettingsSectionCard(
                title: 'Help center',
                icon: Icons.help_outline,
                children: [
                  for (final (index, topic) in _topics.indexed) ...[
                    if (index > 0) divider,
                    _link(
                      icon: topic.icon,
                      title: topic.title,
                      subtitle: topic.subtitle,
                      onTap: () => _openTopic(
                        context,
                        topic.title,
                        topic.icon,
                        topic.questions,
                      ),
                    ),
                  ],
                ],
              ),
              SettingsSectionCard(
                title: 'Policies',
                icon: Icons.description_outlined,
                children: [
                  _link(
                    icon: Icons.article_outlined,
                    title: 'Terms of service',
                    subtitle: _draftsAvailable
                        ? 'Draft · Review pending'
                        : 'Not published yet',
                    onTap: () => _legal(context, LegalDraftKind.terms),
                  ),
                  divider,
                  _link(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy policy',
                    subtitle: _draftsAvailable
                        ? 'Draft · Review pending'
                        : 'Not published yet',
                    onTap: () => _legal(context, LegalDraftKind.privacy),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  'Smart Rental',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ListTile _link({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      ListTile(
        leading: Icon(icon, size: 20),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
      );

  void _openTopic(
    BuildContext context,
    String title,
    IconData icon,
    List<_HelpQuestion> questions,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          final colors = SemanticColors.of(context);
          final theme = Theme.of(context);
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SettingsSectionCard(
                      title: 'Common questions',
                      icon: icon,
                      children: [
                        for (final (index, question) in questions.indexed) ...[
                          if (index > 0)
                            Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: colors.border,
                            ),
                          ExpansionTile(
                            shape: const Border(),
                            collapsedShape: const Border(),
                            title: Text(question.title),
                            expandedCrossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            childrenPadding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            children: [
                              SelectableText(
                                question.answer,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.textSecondary,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _article(BuildContext context, String title, String content) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(title)),
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                SelectableText(content, style: const TextStyle(height: 1.6)),
              ],
            ),
          ),
        ),
      );

  void _legal(BuildContext context, LegalDraftKind kind) {
    final draft = PrototypeLegalDraft.forKind(kind);
    if (!_draftsAvailable) {
      _article(context, draft.title, draft.notice);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrototypeLegalDraftScreen(
          kind: kind,
          environmentLabel: environmentLabel,
          localPreview: prototypeSupport?.available == true,
        ),
      ),
    );
  }
}
