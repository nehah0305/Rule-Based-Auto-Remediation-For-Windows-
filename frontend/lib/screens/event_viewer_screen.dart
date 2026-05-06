import 'package:flutter/material.dart';
import 'dart:convert';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../models/event.dart';
import '../widgets/badges.dart';

class EventViewerScreen extends StatefulWidget {
  const EventViewerScreen({super.key});
  @override
  State<EventViewerScreen> createState() => _EventViewerScreenState();
}

class _EventViewerScreenState extends State<EventViewerScreen> {
  late ApiService _api;
  bool _loading = true;
  bool _autoRefresh = true;
  List<AppEvent> _allEvents = [];
  List<AppEvent> _filteredEvents = [];
  String _lastUpdated = '';

  // Filter state
  String _searchQuery = '';
  String? _selectedSeverity;
  String? _selectedSource;
  String? _selectedLogName;
  DateTimeRange? _dateRange;
  int? _selectedEventId;

  static const _severities = ['Critical', 'High', 'Medium', 'Low'];
  static const _logNames = ['System', 'Application', 'Security', 'Simulation'];

  @override
  void initState() {
    super.initState();
    _api = ApiService();
    _load();
    if (_autoRefresh) {
      _startAutoRefresh();
    }
  }

  void _startAutoRefresh() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _autoRefresh) {
        _load();
        _startAutoRefresh();
      }
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final events = await _api.getFilteredEvents();
      setState(() {
        _allEvents = events;
        _applyFilters();
        _lastUpdated = DateTime.now().toString().substring(0, 16);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
        setState(() => _loading = false);
      }
    }
  }

  void _applyFilters() {
    var filtered = _allEvents;

    // Search query filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((e) =>
        (e.source ?? '').toLowerCase().contains(q) ||
        (e.message ?? '').toLowerCase().contains(q) ||
        (e.severity ?? '').toLowerCase().contains(q) ||
        (e.category ?? '').toLowerCase().contains(q) ||
        '${e.eventId}'.contains(q)
      ).toList();
    }

    // Severity filter
    if (_selectedSeverity != null) {
      filtered = filtered.where((e) => e.severity == _selectedSeverity).toList();
    }

    // Source filter
    if (_selectedSource != null) {
      filtered = filtered.where((e) => e.source == _selectedSource).toList();
    }

    // Log Name filter
    if (_selectedLogName != null) {
      filtered = filtered.where((e) => e.logName == _selectedLogName).toList();
    }

    // Event ID filter
    if (_selectedEventId != null) {
      filtered = filtered.where((e) => e.eventId == _selectedEventId).toList();
    }

    // Date range filter
    if (_dateRange != null) {
      final start = _dateRange!.start;
      final end = _dateRange!.end.add(const Duration(days: 1));
      filtered = filtered.where((e) {
        if (e.timestamp == null) return false;
        final ts = DateTime.tryParse(e.timestamp!);
        if (ts == null) return false;
        return ts.isAfter(start) && ts.isBefore(end);
      }).toList();
    }

    setState(() => _filteredEvents = filtered);
  }

  Future<void> _exportAsJson() async {
    try {
      final json = jsonEncode(_filteredEvents.map((e) => {
        'event_id': e.eventId,
        'source': e.source,
        'severity': e.severity,
        'category': e.category,
        'message': e.message,
        'timestamp': e.timestamp,
        'log_name': e.logName,
        'remediated': e.remediated,
      }).toList());

      _showExportDialog('export_${DateTime.now().millisecondsSinceEpoch}.json', json);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Future<void> _exportAsCsv() async {
    try {
      final csv = StringBuffer('Event ID,Source,Severity,Category,Message,Timestamp,Log Name,Remediated\n');
      for (final event in _filteredEvents) {
        csv.writeln(
          '"${event.eventId}","${event.source}","${event.severity}","${event.category}","${event.message}","${event.timestamp}","${event.logName}","${event.remediated}"',
        );
      }
      _showExportDialog('export_${DateTime.now().millisecondsSinceEpoch}.csv', csv.toString());
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  void _showExportDialog(String filename, String content) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Export Ready'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File: $filename'),
            const SizedBox(height: 12),
            const Text('Content (first 500 chars):'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.bgInput,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  content.substring(0, min(500, content.length)),
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(_).showSnackBar(
                const SnackBar(content: Text('Success: Export content ready to copy.')),
              );
            },
            child: const Text('Copy to Clipboard'),
          ),
        ],
      ),
    );
  }

  void _showEventDetails(AppEvent event) {
    showDialog(
      context: context,
      builder: (_) => _EventDetailsDialog(event: event),
    );
  }

  void _clearAllFilters() {
    setState(() {
      _searchQuery = '';
      _selectedSeverity = null;
      _selectedSource = null;
      _selectedLogName = null;
      _selectedEventId = null;
      _dateRange = null;
      _applyFilters();
    });
  }

  @override
  Widget build(BuildContext context) {
    final uniqueSources = _allEvents.map((e) => e.source).whereType<String>().toSet().toList();
    final hasActiveFilters = _searchQuery.isNotEmpty ||
        _selectedSeverity != null ||
        _selectedSource != null ||
        _selectedLogName != null ||
        _selectedEventId != null ||
        _dateRange != null;

    final tableTheme = Theme.of(context).copyWith(
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.04)),
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return AppTheme.accent.withValues(alpha: 0.06);
          }
          return Colors.transparent;
        }),
        dividerThickness: 0.6,
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              gradient: AppTheme.gradientInfo,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.event_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Event Viewer · ${_filteredEvents.length} / ${_allEvents.length} events',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5),
                      ),
                      if (_lastUpdated.isNotEmpty)
                        Text(
                          'Updated $_lastUpdated',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11.5),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                  tooltip: 'Refresh',
                ),
                PopupMenuButton(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      child: const Text('Export as JSON'),
                      onTap: () { _exportAsJson(); },
                    ),
                    PopupMenuItem(
                      child: const Text('Export as CSV'),
                      onTap: () { _exportAsCsv(); },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          onChanged: (v) {
                            setState(() => _searchQuery = v);
                            _applyFilters();
                          },
                          decoration: const InputDecoration(
                            hintText: 'Search by source, message, severity, category, or event ID…',
                            prefixIcon: Icon(Icons.search_rounded, size: 18),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _FilterDropdown(
                              label: 'Severity',
                              value: _selectedSeverity,
                              items: _severities,
                              onChanged: (v) {
                                setState(() => _selectedSeverity = v);
                                _applyFilters();
                              },
                            ),
                            _FilterDropdown(
                              label: 'Log Name',
                              value: _selectedLogName,
                              items: _logNames,
                              onChanged: (v) {
                                setState(() => _selectedLogName = v);
                                _applyFilters();
                              },
                            ),
                            if (uniqueSources.isNotEmpty)
                              _FilterDropdown(
                                label: 'Source',
                                value: _selectedSource,
                                items: uniqueSources,
                                onChanged: (v) {
                                  setState(() => _selectedSource = v);
                                  _applyFilters();
                                },
                              ),
                            _DateRangeButton(
                              dateRange: _dateRange,
                              onChanged: (range) {
                                setState(() => _dateRange = range);
                                _applyFilters();
                              },
                            ),
                            if (hasActiveFilters)
                              OutlinedButton.icon(
                                onPressed: _clearAllFilters,
                                icon: const Icon(Icons.clear_all_rounded, size: 16),
                                label: const Text('Clear Filters'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _filteredEvents.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 72,
                                      height: 72,
                                      decoration: BoxDecoration(
                                        gradient: AppTheme.gradientInfo,
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: const Icon(Icons.event_busy_rounded, color: Colors.white, size: 34),
                                    ),
                                    const SizedBox(height: 14),
                                    const Text(
                                      'No events found',
                                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      hasActiveFilters ? 'Try clearing filters or widening the date range.' : 'New events will appear here automatically.',
                                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                    ),
                                  ],
                                ),
                              )
                            : Theme(
                                data: tableTheme,
                                child: Scrollbar(
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SingleChildScrollView(
                                      child: DataTable(
                                        columnSpacing: 22,
                                        headingRowHeight: 54,
                                        dataRowMinHeight: 56,
                                        dataRowMaxHeight: 72,
                                        horizontalMargin: 18,
                                        columns: const [
                                          DataColumn(label: Text('Event ID')),
                                          DataColumn(label: Text('Source')),
                                          DataColumn(label: Text('Severity')),
                                          DataColumn(label: Text('Category')),
                                          DataColumn(label: Text('Message')),
                                          DataColumn(label: Text('Timestamp')),
                                          DataColumn(label: Text('Log Name')),
                                          DataColumn(label: Text('Remediated')),
                                          DataColumn(label: Text('Actions')),
                                        ],
                                        rows: _filteredEvents.map((event) {
                                          return DataRow(
                                            cells: [
                                              DataCell(Text('${event.eventId}')),
                                              DataCell(Text(event.source ?? '-')),
                                              DataCell(SeverityBadge(event.severity ?? 'Unknown')),
                                              DataCell(Text(event.category ?? '-')),
                                              DataCell(
                                                LayoutBuilder(
                                                  builder: (ctx, constraints) {
                                                    final maxW = (constraints.maxWidth.isFinite && constraints.maxWidth > 0)
                                                        ? (constraints.maxWidth * 0.45).clamp(160.0, 640.0)
                                                        : 320.0;
                                                    return ConstrainedBox(
                                                      constraints: BoxConstraints(maxWidth: maxW),
                                                      child: Text(
                                                        event.message ?? '-',
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                              DataCell(Text(event.timestamp?.toString().substring(0, 16) ?? '-')),
                                              DataCell(Text(event.logName ?? 'Unknown')),
                                              DataCell(
                                                event.remediated
                                                    ? const Text('✓ Yes', style: TextStyle(color: AppTheme.accentGreen, fontWeight: FontWeight.w700))
                                                    : const Text('○ No', style: TextStyle(color: AppTheme.textSecondary)),
                                              ),
                                              DataCell(
                                                IconButton(
                                                  icon: const Icon(Icons.info_outline_rounded, size: 18),
                                                  tooltip: 'View Details',
                                                  onPressed: () => _showEventDetails(event),
                                                ),
                                              ),
                                            ],
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String?>(
      value: value,
      hint: Text(label),
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(16),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(label),
        ),
        ...items.map((item) => DropdownMenuItem<String?>(value: item, child: Text(item))),
      ],
      onChanged: onChanged,
    );
  }
}

class _DateRangeButton extends StatelessWidget {
  final DateTimeRange? dateRange;
  final ValueChanged<DateTimeRange?> onChanged;

  const _DateRangeButton({
    required this.dateRange,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime.now().subtract(const Duration(days: 30)),
          lastDate: DateTime.now(),
          initialDateRange: dateRange,
        );
        if (range != null) {
          onChanged(range);
        }
      },
      icon: const Icon(Icons.calendar_today, size: 16),
      label: Text(
        dateRange == null
            ? 'Date Range'
            : '${dateRange!.start.toString().substring(0, 10)} to ${dateRange!.end.toString().substring(0, 10)}',
      ),
    );
  }
}

class _EventDetailsDialog extends StatelessWidget {
  final AppEvent event;

  const _EventDetailsDialog({required this.event});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          SeverityBadge(event.severity ?? 'Unknown'),
          const SizedBox(width: 8),
          Text('Event #${event.eventId}'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow('Source', event.source ?? 'N/A'),
            _DetailRow('Category', event.category ?? 'N/A'),
            _DetailRow('Severity', event.severity ?? 'N/A'),
            _DetailRow('Log Name', event.logName ?? 'N/A'),
            _DetailRow('Timestamp', event.timestamp?.toString() ?? 'N/A'),
            _DetailRow('Remediated', event.remediated ? 'Yes ✓' : 'No ○'),
            const SizedBox(height: 16),
            const Text(
              'Message:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.bgInput,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(event.message ?? 'N/A'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 72, maxWidth: 160),
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}

int min(int a, int b) => a < b ? a : b;
