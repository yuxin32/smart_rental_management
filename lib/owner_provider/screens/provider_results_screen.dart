import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../features/bookings/domain/cleaning_request_flow.dart';
import '../main.dart';
import '../models/demo_data.dart';
import '../theme/app_theme.dart';
import '../widgets/provider_card.dart';
import 'provider_profile_screen.dart';

/// Request-specific results. Unlike the general browse tab, this page uses
/// the owner's selected service, unit and interval for every eligibility check.
class ProviderResultsScreen extends StatefulWidget {
  const ProviderResultsScreen({super.key, required this.draft});

  final CleaningRequestDraft draft;

  @override
  State<ProviderResultsScreen> createState() => _ProviderResultsScreenState();
}

class _ProviderResultsScreenState extends State<ProviderResultsScreen> {
  late CleaningRequestDraft _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
  }

  Future<void> _viewProfile(DemoProvider provider) async {
    final selected = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (profileContext) => ProviderProfileScreen(
          provider: provider,
          onSelect: () => Navigator.of(profileContext).pop(true),
        ),
      ),
    );
    if (selected == true && mounted) await _reviewProvider(provider);
  }

  Future<void> _reviewProvider(DemoProvider provider) async {
    final selected = await Navigator.of(context).push<SelectedCleaningRequest>(
      MaterialPageRoute(
        builder: (_) => ReviewCleaningRequestScreen(
          draft: _draft,
          provider: provider,
        ),
      ),
    );
    if (!mounted) return;
    if (selected != null) {
      Navigator.of(context).pop(selected);
    } else {
      setState(() {}); // Refresh eligibility if the review found a conflict.
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppProviders.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([app.providerStore, app.bookingStore]),
      builder: (context, _) {
        final matches = app.providerStore.matchProviders(
          request: _draft.matchRequest,
          bookings: app.bookingStore.bookings,
        );
        final alternatives = matches.rankedProviders.isEmpty
            ? const AlternativeWindowService().generate(
                draft: _draft,
                providers: app.providerStore.providers,
                bookings: app.bookingStore.bookings,
              )
            : const <DateTime>[];
        final sem = SemanticColors.of(context);

        return Scaffold(
          appBar: AppBar(title: const Text('Find suitable providers')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _requestSummary(sem),
              const SizedBox(height: 18),
              if (matches.rankedProviders.isNotEmpty) ...[
                Text(
                  '${matches.rankedProviders.length} eligible provider${matches.rankedProviders.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: sem.textPrimary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Availability is a required check. Eligible providers are ranked by distance, rating and workload (⅓ each).',
                  style: TextStyle(fontSize: 12, color: sem.textSecondary),
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < matches.rankedProviders.length; i++) ...[
                  ProviderCard(
                    provider: matches.rankedProviders[i],
                    rank: i + 1,
                    actionLabel: 'Select',
                    onViewProfile: () =>
                        _viewProfile(matches.rankedProviders[i]),
                    onAssign: () => _reviewProvider(matches.rankedProviders[i]),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  'Distance estimates and availability may change. Check the selected interval before sending your request.',
                  style: TextStyle(fontSize: 11, color: sem.textSecondary),
                ),
              ] else ...[
                _noProviderCard(sem),
                const SizedBox(height: 16),
                if (alternatives.isNotEmpty) ...[
                  Text(
                    'Feasible alternative windows',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: sem.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Same service duration. Nearest start time first. Choosing one checks provider eligibility again.',
                    style: TextStyle(fontSize: 12, color: sem.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  for (final start in alternatives)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.event_available_outlined,
                            color: AppColors.primary),
                        title:
                            Text(DateFormat('EEE d MMM, HH:mm').format(start)),
                        subtitle: Text(
                          'Until ${DateFormat('HH:mm').format(start.add(_draft.duration))}',
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => setState(() => _draft = _draft.at(start)),
                      ),
                    ),
                ] else
                  Text(
                    'No feasible alternative is available for this service and rental-unit window.',
                    style: TextStyle(color: sem.textSecondary),
                  ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Revise request'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _requestSummary(SemanticColors sem) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primarySurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primaryBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your request',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: sem.textPrimary,
                )),
            const SizedBox(height: 7),
            Text('${_draft.property.display} · ${_draft.service.label}'),
            Text(
              '${DateFormat('EEE d MMM y, HH:mm').format(_draft.requestedStart)}–${DateFormat('HH:mm').format(_draft.requestedEnd)}',
            ),
          ],
        ),
      );

  Widget _noProviderCard(SemanticColors sem) => Card(
        color: sem.surfaceAlt,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.person_off_outlined, color: AppColors.primary),
              const SizedBox(height: 8),
              Text('No eligible provider for this interval',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: sem.textPrimary,
                  )),
              const SizedBox(height: 4),
              Text(
                'Try a feasible alternative below, or revise the request.',
                style: TextStyle(color: sem.textSecondary),
              ),
            ],
          ),
        ),
      );
}

class ReviewCleaningRequestScreen extends StatefulWidget {
  const ReviewCleaningRequestScreen({
    super.key,
    required this.draft,
    required this.provider,
  });

  final CleaningRequestDraft draft;
  final DemoProvider provider;

  @override
  State<ReviewCleaningRequestScreen> createState() =>
      _ReviewCleaningRequestScreenState();
}

class _ReviewCleaningRequestScreenState
    extends State<ReviewCleaningRequestScreen> {
  void _confirm() {
    if (!widget.draft.requestedStart.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please revise the request to a future time.')),
      );
      Navigator.of(context).pop();
      return;
    }
    final app = AppProviders.of(context);
    final latest = app.providerStore.matchProviders(
      request: widget.draft.matchRequest,
      bookings: app.bookingStore.bookings,
    );
    if (!latest.rankedProviders.any((p) => p.id == widget.provider.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'The selected provider or interval changed. Please choose again.'),
          backgroundColor: AppColors.error,
        ),
      );
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(
      SelectedCleaningRequest(draft: widget.draft, provider: widget.provider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    final draft = widget.draft;
    return Scaffold(
      appBar: AppBar(title: const Text('Review & submit request')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detail('Rental unit', draft.property.display),
                  _detail('Service', draft.service.label),
                  _detail('Provider', widget.provider.name),
                  _detail('Date',
                      DateFormat('EEE d MMM y').format(draft.requestedStart)),
                  _detail('Time',
                      '${DateFormat('HH:mm').format(draft.requestedStart)}–${DateFormat('HH:mm').format(draft.requestedEnd)}'),
                  _detail('Duration', '${draft.duration.inHours} hours'),
                  _detail('Instructions', draft.instructions),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              border: Border.all(color: AppColors.primaryBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Submitting creates a Pending request for ${widget.provider.name}. The slot is not reserved until the provider accepts after another availability check.',
              style: TextStyle(color: sem.textPrimary),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to providers'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: FilledButton.icon(
            onPressed: _confirm,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Submit Pending request'),
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
