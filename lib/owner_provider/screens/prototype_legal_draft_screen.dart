import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../content/prototype_legal_drafts.dart';
import '../theme/app_theme.dart';

class PrototypeLegalDraftScreen extends StatelessWidget {
  const PrototypeLegalDraftScreen({
    super.key,
    required this.kind,
    required this.environmentLabel,
    this.localPreview = false,
  });

  final LegalDraftKind kind;
  final String? environmentLabel;
  final bool localPreview;

  @override
  Widget build(BuildContext context) {
    final draft = PrototypeLegalDraft.forKind(kind);
    final sem = SemanticColors.of(context);
    final allowed =
        canPreviewLegalDrafts(environmentLabel, localPreview: localPreview);
    return Scaffold(
      appBar: AppBar(title: Text(draft.title)),
      body: !allowed
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                  'Not published yet. No approved policy or legal acceptance is provided here.',
                  style: TextStyle(color: sem.textPrimary, height: 1.6)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(PrototypeLegalDraft.status,
                              style: TextStyle(
                                  color: sem.textPrimary,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text(PrototypeLegalDraft.version,
                              style: TextStyle(color: sem.textSecondary)),
                          const SizedBox(height: 12),
                          SelectableText(draft.notice,
                              style: TextStyle(
                                  color: sem.textPrimary, height: 1.6)),
                          const SizedBox(height: 12),
                          const Text(
                              'No effective date or legal acceptance is recorded by this page.'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Copy review draft'),
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: draft.copyText));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  'Draft copied with its unpublished status.')));
                        }
                      },
                    ),
                  ),
                  for (final section in draft.sections) ...[
                    const SizedBox(height: 20),
                    Semantics(
                      header: true,
                      child: Text(section.title,
                          style: TextStyle(
                              color: sem.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(section.body,
                        style:
                            TextStyle(color: sem.textSecondary, height: 1.6)),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
