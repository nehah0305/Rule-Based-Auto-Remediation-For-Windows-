import 'package:flutter/material.dart';
import 'dart:convert';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../models/event.dart';
import '../models/history_entry.dart';
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
  int _currentPage = 0;
  static const int _pageSize = 50;
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

    setState(() {
      _filteredEvents = filtered;
      _currentPage = 0;
    });
  }

  List<AppEvent> get _paginatedEvents {
    return _filteredEvents.skip(_currentPage * _pageSize).take(_pageSize).toList();
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

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Header
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Event Viewer · ${_filteredEvents.length} / ${_allEvents.length} events',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_lastUpdated.isNotEmpty)
                        Text(
                          'Updated $_lastUpdated',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
                          maxLines: 1,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                  tooltip: 'Refresh',
                  iconSize: 20,
                  splashRadius: 20,
                ),
                PopupMenuButton(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 18),
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
          // Main content area
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  // Filters section
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Search box
                        TextField(
                          onChanged: (v) {
                            setState(() => _searchQuery = v);
                            _applyFilters();
                          },
                          decoration: InputDecoration(
                            hintText: 'Search by source, message, severity, category, or event ID…',
                            prefixIcon: const Icon(Icons.search_rounded, size: 18),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Filter chips - responsive
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
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
                              const SizedBox(width: 10),
                              _FilterDropdown(
                                label: 'Log Name',
                                value: _selectedLogName,
                                items: _logNames,
                                onChanged: (v) {
                                  setState(() => _selectedLogName = v);
                                  _applyFilters();
                                },
                              ),
                              if (uniqueSources.isNotEmpty) ...[
                                const SizedBox(width: 10),
                                _FilterDropdown(
                                  label: 'Source',
                                  value: _selectedSource,
                                  items: uniqueSources,
                                  onChanged: (v) {
                                    setState(() => _selectedSource = v);
                                    _applyFilters();
                                  },
                                ),
                              ],
                              const SizedBox(width: 10),
                              _DateRangeButton(
                                dateRange: _dateRange,
                                onChanged: (range) {
                                  setState(() => _dateRange = range);
                                  _applyFilters();
                                },
                              ),
                              if (hasActiveFilters) ...[
                                const SizedBox(width: 10),
                                OutlinedButton.icon(
                                  onPressed: _clearAllFilters,
                                  icon: const Icon(Icons.clear_all_rounded, size: 16),
                                  label: const Text('Clear'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Events table - responsive
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(),
                          )
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
                                      child: const Icon(
                                        Icons.event_busy_rounded,
                                        color: Colors.white,
                                        size: 34,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    const Text(
                                      'No events found',
                                      style: TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 24),
                                      child: Text(
                                        hasActiveFilters
                                            ? 'Try clearing filters or widening the date range.'
                                            : 'New events will appear here automatically.',
                                        style: const TextStyle(
                                          color: AppTheme.textMuted,
                                          fontSize: 12,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : _buildResponsiveEventsList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveEventsList() {
    return Column(
      children: [
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: ListView.builder(
              itemCount: _paginatedEvents.length,
              padding: const EdgeInsets.all(12),
              itemBuilder: (context, index) {
                final event = _paginatedEvents[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _EventCard(
                    event: event,
                    onTap: () => _showEventDetails(event),
                  ),
                );
              },
            ),
          ),
        ),
        if (!_loading && _filteredEvents.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              border: const Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
                ),
                Text('Page ${_currentPage + 1} of ${(_filteredEvents.length / _pageSize).ceil()}'),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: (_currentPage + 1) * _pageSize < _filteredEvents.length ? () => setState(() => _currentPage++) : null,
                ),
              ],
            ),
          ),
      ],
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

class _EventDetailsDialog extends StatefulWidget {
  final AppEvent event;

  const _EventDetailsDialog({required this.event});

  @override
  State<_EventDetailsDialog> createState() => _EventDetailsDialogState();
}

class _EventDetailsDialogState extends State<_EventDetailsDialog> {
  final ApiService _api = ApiService();
  bool _loadingHistory = true;
  List<HistoryEntry> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final h = await _api.getEventHistory(widget.event.id);
      if (mounted) setState(() {
        _history = h;
        _loadingHistory = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          SeverityBadge(widget.event.severity ?? 'Unknown'),
          const SizedBox(width: 8),
          Text('Event #${widget.event.eventId}'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow('Source', widget.event.source ?? 'N/A'),
            _DetailRow('Category', widget.event.category ?? 'N/A'),
            _DetailRow('Severity', widget.event.severity ?? 'N/A'),
            _DetailRow('Log Name', widget.event.logName ?? 'N/A'),
            _DetailRow('Timestamp', widget.event.timestamp?.toString() ?? 'N/A'),
            _DetailRow('Remediated', widget.event.remediated ? 'Yes ✓' : 'No ○'),
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
              child: Text(widget.event.message ?? 'N/A'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Remediation History:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (_loadingHistory)
              const Center(child: CircularProgressIndicator(color: AppTheme.accent))
            else if (_history.isEmpty)
              const Text('No remediation history found for this event.', style: TextStyle(color: AppTheme.textMuted))
            else
              ..._history.map((h) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: h.status == 'success' ? AppTheme.accentGreen.withValues(alpha: 0.1) : AppTheme.accentRed.withValues(alpha: 0.1),
                  border: Border.all(color: h.status == 'success' ? AppTheme.accentGreen : AppTheme.accentRed),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Rule: ${h.ruleName ?? 'Unknown'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(h.timestamp?.substring(0, 16) ?? '', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Status: ${h.status}', style: TextStyle(fontWeight: FontWeight.w600, color: h.status == 'success' ? AppTheme.accentGreen : AppTheme.accentRed)),
                    if (h.output != null && h.output!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('Output:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.all(8),
                        color: Colors.black.withValues(alpha: 0.05),
                        child: Text(h.output!, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      ),
                    ]
                  ],
                ),
              )).toList(),
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

class _EventCard extends StatelessWidget {
  final AppEvent event;
  final VoidCallback onTap;

  const _EventCard({
    required this.event,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          border: Border.all(color: AppTheme.border, width: 0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // First row: Event ID, Severity, Timestamp
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '#${event.eventId}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SeverityBadge(event.severity ?? 'Unknown'),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                event.timestamp?.toString().substring(0, 16) ?? '-',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textMuted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (event.remediated)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.accentGreen.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_rounded, size: 14, color: AppTheme.accentGreen),
                              SizedBox(width: 4),
                              Text(
                                'Remediated',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.accentGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Second row: Source and Category
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Source',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              event.source ?? '-',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Category',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              event.category ?? '-',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Log',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            event.logName ?? 'Unknown',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ),
                  if ((event.message ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    // Message
                    Text(
                      'Message',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.message ?? '-',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Footer with tap hint
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Tap for details',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.accent.withValues(alpha: 0.7),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_outward_rounded,
                        size: 14,
                        color: AppTheme.accent.withValues(alpha: 0.7),
                      ),
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
}
