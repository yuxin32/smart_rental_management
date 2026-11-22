// lib/widgets/filter_sheet.dart
// Generic filter + sort sheet used by Owner Home and Provider Inbox.

import 'package:flutter/material.dart';
import '../models/demo_data.dart';
import '../theme/app_theme.dart';

enum SortMode { newest, oldest, byStatus, byProperty }

class FilterResult {
  const FilterResult({
    required this.statusFilter,
    required this.sortMode,
    required this.propertyFilter,
  });
  final BookingStatus? statusFilter;
  final SortMode sortMode;
  final String? propertyFilter;

  static const empty = FilterResult(
    statusFilter: null,
    sortMode: SortMode.newest,
    propertyFilter: null,
  );
}

class FilterSheet extends StatefulWidget {
  const FilterSheet(
      {super.key, required this.initial, required this.properties});
  final FilterResult initial;
  final List<String> properties; // distinct property names

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late BookingStatus? _status;
  late SortMode _sort;
  late String? _property;

  @override
  void initState() {
    super.initState();
    _status = widget.initial.statusFilter;
    _sort = widget.initial.sortMode;
    _property = widget.initial.propertyFilter;
  }

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tune, size: 18, color: AppTheme.accent(context)),
                  const SizedBox(width: 8),
                  Text('Filter & sort',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: sem.textPrimary)),
                ],
              ),
              const SizedBox(height: 20),
              Text('STATUS',
                  style: TextStyle(
                      fontSize: 11,
                      color: sem.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _chip(label: 'All', value: null, isSelected: _status == null),
                  ...BookingStatus.values.map((s) => _chip(
                        label: s.label,
                        value: s,
                        isSelected: _status == s,
                        color: s.color,
                      )),
                ],
              ),
              const SizedBox(height: 20),
              Text('SORT BY',
                  style: TextStyle(
                      fontSize: 11,
                      color: sem.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
              const SizedBox(height: 8),
              Column(
                children: SortMode.values.map((m) {
                  return InkWell(
                    onTap: () => setState(() => _sort = m),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _sort == m ? sem.surfaceAlt : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color:
                                _sort == m ? sem.border : Colors.transparent),
                      ),
                      child: Row(
                        children: [
                          Icon(_iconFor(m),
                              size: 16,
                              color: _sort == m
                                  ? AppTheme.accent(context)
                                  : sem.textSecondary),
                          const SizedBox(width: 10),
                          Text(_labelFor(m),
                              style: TextStyle(
                                  fontSize: 14,
                                  color: sem.textPrimary,
                                  fontWeight: _sort == m
                                      ? FontWeight.w600
                                      : FontWeight.w500)),
                          const Spacer(),
                          if (_sort == m)
                            Icon(Icons.check,
                                size: 16, color: AppTheme.accent(context)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Text('PROPERTY',
                  style: TextStyle(
                      fontSize: 11,
                      color: sem.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                value: _property,
                isExpanded: true,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: sem.surfaceAlt,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: sem.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: sem.border),
                  ),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('All properties')),
                  ...widget.properties.map((p) => DropdownMenuItem<String?>(
                      value: p,
                      child: Text(p, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => setState(() => _property = v),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _status = null;
                          _sort = SortMode.newest;
                          _property = null;
                        });
                      },
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop(FilterResult(
                          statusFilter: _status,
                          sortMode: _sort,
                          propertyFilter: _property,
                        ));
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(
      {required String label,
      required BookingStatus? value,
      required bool isSelected,
      Color? color}) {
    final sem = SemanticColors.of(context);
    final c = color ?? AppTheme.accent(context);
    return InkWell(
      onTap: () => setState(() => _status = value),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? c : sem.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: isSelected ? c : sem.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : sem.textPrimary,
          ),
        ),
      ),
    );
  }

  IconData _iconFor(SortMode m) {
    switch (m) {
      case SortMode.newest:
        return Icons.access_time;
      case SortMode.oldest:
        return Icons.history;
      case SortMode.byStatus:
        return Icons.label;
      case SortMode.byProperty:
        return Icons.apartment;
    }
  }

  String _labelFor(SortMode m) {
    switch (m) {
      case SortMode.newest:
        return 'Newest first';
      case SortMode.oldest:
        return 'Oldest first';
      case SortMode.byStatus:
        return 'By status';
      case SortMode.byProperty:
        return 'By property';
    }
  }
}

/// Apply the filter+sort to a list of bookings.
List<DemoBooking> applyFilter(List<DemoBooking> source, FilterResult f) {
  var out = source;
  if (f.statusFilter != null) {
    out = out.where((b) => b.status == f.statusFilter).toList();
  }
  if (f.propertyFilter != null) {
    out = out.where((b) => b.property == f.propertyFilter).toList();
  }
  final sorted = List<DemoBooking>.from(out);
  switch (f.sortMode) {
    case SortMode.newest:
      sorted.sort((a, b) => b.scheduledStart.compareTo(a.scheduledStart));
      break;
    case SortMode.oldest:
      sorted.sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
      break;
    case SortMode.byStatus:
      sorted.sort((a, b) => a.status.index.compareTo(b.status.index));
      break;
    case SortMode.byProperty:
      sorted.sort((a, b) => a.property.compareTo(b.property));
      break;
  }
  return sorted;
}
