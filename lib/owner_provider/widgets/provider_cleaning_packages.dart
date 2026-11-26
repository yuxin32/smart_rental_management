import 'package:flutter/material.dart';
import '../features/availability/domain/cleaning_package.dart';
import '../features/availability/domain/provider_setup.dart';
import '../services/backend/connected_failure_message.dart';

typedef SaveCleaningPackage = Future<CleaningPackage> Function(
  CleaningPackageDraft draft,
  CleaningPackage? expected,
);

/// Fixed session totals are verified by the server, never inferred from a
/// displayed hourly rate. A failed write requires a fresh read before retry.
class ProviderCleaningPackages extends StatefulWidget {
  const ProviderCleaningPackages({
    super.key,
    required this.services,
    required this.selectedServices,
    required this.load,
    required this.save,
    required this.enabled,
    required this.onBusyChanged,
  });
  final List<ProviderServiceItem> services;
  final Set<String> selectedServices;
  final Future<List<CleaningPackage>> Function() load;
  final SaveCleaningPackage save;
  final bool enabled;
  final ValueChanged<bool> onBusyChanged;
  @override
  State<ProviderCleaningPackages> createState() =>
      _ProviderCleaningPackagesState();
}

class _ProviderCleaningPackagesState extends State<ProviderCleaningPackages> {
  List<CleaningPackage>? _packages;
  String? _service, _error;
  bool _loading = true, _busy = false;
  int _readVersion = 0;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _readVersion++;
    super.dispose();
  }

  Future<void> _reload() async {
    final version = ++_readVersion;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = await widget.load();
      if (!mounted || version != _readVersion) return;
      setState(() => _packages = items);
    } catch (e) {
      if (mounted && version == _readVersion) {
        setState(
          () => _error =
              'Could not load cleaning packages. Check your connection and refresh.',
        );
      }
    } finally {
      if (mounted && version == _readVersion) setState(() => _loading = false);
    }
  }

  Future<void> _edit(
    ProviderServiceItem service,
    CleaningPackage? package,
  ) async {
    if (_busy || _loading || !widget.enabled || _error != null) return;
    // Re-read before opening: another device may have changed the package.
    setState(() => _busy = true);
    widget.onBusyChanged(true);
    try {
      final items = await widget.load();
      if (!mounted) return;
      _packages = items;
      final matches = items.where((p) => p.id == package?.id).toList();
      if (package != null && matches.isEmpty) {
        setState(
          () => _error = 'This package changed. Refresh before editing.',
        );
        return;
      }
      final base = package == null ? null : matches.single;
      final draft = await showModalBottomSheet<CleaningPackageDraft>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _PackageEditor(service: service, initial: base),
      );
      if (draft == null || !mounted) return;
      await widget.save(draft, base);
      if (!mounted) return;
      await _reload();
      if (mounted && _error == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Package saved')));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              '${ConnectedFailureMessage.forWrite(e, item: 'package')} Refresh packages before trying again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    if (services.isEmpty) return const Text('No cleaning services available.');
    if (!services.any((s) => s.id == _service)) _service = services.first.id;
    final service = services.firstWhere((s) => s.id == _service);
    final rows = (_packages ?? const <CleaningPackage>[])
        .where((p) => p.serviceTypeId == _service)
        .toList()
      ..sort(
        (a, b) => a.durationMinutes != b.durationMinutes
            ? a.durationMinutes.compareTo(b.durationMinutes)
            : a.cleanerCount.compareTo(b.cleanerCount),
      );
    final enabled = widget.enabled &&
        !_busy &&
        !_loading &&
        _error == null &&
        widget.selectedServices.contains(_service);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('package-service-$_service'),
          initialValue: _service,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Service',
            isDense: true,
          ),
          items: services
              .map(
                (s) => DropdownMenuItem(
                  value: s.id,
                  child: Text(s.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: _busy ? null : (value) => setState(() => _service = value),
        ),
        const SizedBox(height: 12),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy || _loading ? null : _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh packages'),
            ),
          ),
        ],
        if (!_loading && _error == null) ...[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              const Text(
                'Packages',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                'Total per session',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Add a package to receive requests for this service.',
              ),
            ),
          if (rows.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 7, 4, 7),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${rows[i].durationMinutes ~/ 60} hours',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${rows[i].cleanerCount} ${rows[i].cleanerCount == 1 ? 'cleaner' : 'cleaners'}${rows[i].enabled ? '' : ' · Paused'}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Flexible(
                            child: Text(
                              'RM ${rows[i].totalPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            key: ValueKey('edit-package-${rows[i].id}'),
                            tooltip:
                                'Edit ${rows[i].durationMinutes ~/ 60}-hour package',
                            onPressed:
                                enabled ? () => _edit(service, rows[i]) : null,
                            icon: const Icon(Icons.edit_outlined, size: 19),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('add-cleaning-package'),
              onPressed: enabled ? () => _edit(service, null) : null,
              icon: const Icon(Icons.add),
              label: const Text('Add package'),
            ),
          ),
          if (!widget.selectedServices.contains(_service))
            const Text(
              'Enable this cleaning service below to receive requests.',
              style: TextStyle(fontSize: 12),
            ),
          const Text(
            'Existing bookings keep their agreed package.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _PackageEditor extends StatefulWidget {
  const _PackageEditor({required this.service, this.initial});
  final ProviderServiceItem service;
  final CleaningPackage? initial;
  @override
  State<_PackageEditor> createState() => _PackageEditorState();
}

class _PackageEditorState extends State<_PackageEditor> {
  late int _minutes, _cleaners;
  late bool _enabled;
  late final TextEditingController _price, _scope;
  final _form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    _minutes = widget.initial?.durationMinutes ??
        CleaningPackageDraft.durationsForService(widget.service.name).first;
    _cleaners = widget.initial?.cleanerCount ?? 1;
    _enabled = widget.initial?.enabled ?? true;
    _price = TextEditingController(
      text: widget.initial?.totalPrice.toStringAsFixed(2) ?? '',
    );
    _scope = TextEditingController(text: widget.initial?.scope ?? '');
  }

  @override
  void dispose() {
    _price.dispose();
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.initial == null
                              ? 'Add package'
                              : 'Edit package',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close package editor',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Text(
                    widget.service.name,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _minutes,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Duration',
                            isDense: true,
                          ),
                          items: CleaningPackageDraft.durationsForService(
                            widget.service.name,
                          )
                              .map(
                                (m) => DropdownMenuItem(
                                  value: m,
                                  child: Text('${m ~/ 60} hours'),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _minutes = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _cleaners,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Cleaners',
                            isDense: true,
                          ),
                          items: [
                            for (var n = 1; n <= 4; n++)
                              DropdownMenuItem(value: n, child: Text('$n')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _cleaners = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _price,
                    key: const ValueKey('package-total'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Package total (RM)',
                      hintText: 'e.g. 120.00',
                      helperText: 'Total for all cleaners for this session.',
                      helperMaxLines: 3,
                    ),
                    validator: (v) {
                      final p = num.tryParse(v?.trim() ?? '');
                      return p == null ||
                              !p.isFinite ||
                              p <= 0 ||
                              p > 99999 ||
                              !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(v!.trim())
                          ? 'Enter a valid total, e.g. 120.00.'
                          : null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _scope,
                    key: const ValueKey('package-scope'),
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Included tasks',
                      hintText: 'e.g. Vacuum, mop and bathroom cleaning',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Describe what is included.'
                        : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Offer this package'),
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            if (!_form.currentState!.validate()) return;
                            Navigator.pop(
                              context,
                              CleaningPackageDraft(
                                serviceTypeId: widget.service.id,
                                durationMinutes: _minutes,
                                cleanerCount: _cleaners,
                                totalPrice: num.parse(_price.text.trim()),
                                scope: _scope.text.trim(),
                                enabled: _enabled,
                              ),
                            );
                          },
                          child: const Text('Save package'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
