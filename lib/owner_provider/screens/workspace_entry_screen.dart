import 'package:flutter/material.dart';

import '../content/prototype_legal_drafts.dart';
import '../services/backend/supabase_backend_provider.dart';
import '../theme/app_theme.dart';
import 'prototype_legal_draft_screen.dart';
import 'workspace_login_screen.dart';

/// Swap authentication views in place so login cannot remain above Home.
class WorkspaceEntryScreen extends StatefulWidget {
  const WorkspaceEntryScreen({super.key, this.backend});
  final SupabaseBackendProvider? backend;

  @override
  State<WorkspaceEntryScreen> createState() => _WorkspaceEntryScreenState();
}

class _WorkspaceEntryScreenState extends State<WorkspaceEntryScreen> {
  bool? _registering;

  void _openLegal(LegalDraftKind kind) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PrototypeLegalDraftScreen(
        kind: kind,
        environmentLabel: widget.backend?.config?.environmentName,
        localPreview: widget.backend == null,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_registering != null) {
      return WorkspaceLoginScreen(
        backend: widget.backend,
        initiallyRegistering: _registering!,
        onBackToWelcome: () => setState(() => _registering = null),
      );
    }
    final colors = SemanticColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Icon(Icons.home_work_outlined,
                        color: Theme.of(context).colorScheme.primary, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Smart Rental',
                          style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                    ),
                  ]),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(24)),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.cleaning_services_outlined,
                            size: 44, color: AppColors.primaryLighter),
                        SizedBox(height: 24),
                        Text('Rental care,\nmade simpler.',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                height: 1.2,
                                fontWeight: FontWeight.w800)),
                        SizedBox(height: 14),
                        Text(
                            'Arrange cleaning, follow each booking and keep everyone on the same page.',
                            style: TextStyle(
                                color: Color(0xFFD9E8FF), height: 1.5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    header: true,
                    child: Text('Welcome to Smart Rental',
                        style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 21,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 16),
                  _role(context, Icons.apartment_outlined, 'For owners',
                      'Manage rental units and request cleaning.'),
                  const SizedBox(height: 16),
                  _role(
                      context,
                      Icons.event_available_outlined,
                      'For providers',
                      'Manage requests, availability and completed jobs.'),
                  const SizedBox(height: 28),
                  FilledButton(
                    key: const Key('welcome-create-account'),
                    onPressed: () => setState(() => _registering = true),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    child: const Text('Create account'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const Key('welcome-log-in'),
                    onPressed: () => setState(() => _registering = false),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    child: const Text('Log in'),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      TextButton(
                          onPressed: () => _openLegal(LegalDraftKind.terms),
                          child: const Text('Terms of service')),
                      TextButton(
                          onPressed: () => _openLegal(LegalDraftKind.privacy),
                          child: const Text('Privacy policy')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _role(BuildContext context, IconData icon, String title, String body) {
    final colors = SemanticColors.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: colors.primarySurface,
            borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  color: colors.textPrimary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(body,
              style: TextStyle(color: colors.textSecondary, height: 1.4)),
        ]),
      ),
    ]);
  }
}
