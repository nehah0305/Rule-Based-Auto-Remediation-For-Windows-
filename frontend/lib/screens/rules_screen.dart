import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../models/rule.dart';
import '../widgets/badges.dart';

class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});
  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  final _api = ApiService();
  bool _loading = true;
  List<Rule> _rules = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try { _rules = await _api.getRules(); } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _deleteRule(int id) async {
    final confirmed = await showDialog<bool>(context: context, builder: (_) => const _ConfirmDialog(
      title: 'Delete Rule', message: 'This cannot be undone.'));
    if (confirmed == true) {
      try {
        await _api.deleteRule(id);
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _testRule(int id) async {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => const AlertDialog(content: SizedBox(height: 60,
        child: Row(children: [CircularProgressIndicator(color: AppTheme.accent), SizedBox(width: 16),
          Text('Running test…', style: TextStyle(color: AppTheme.textPrimary))]))));
    try {
      final result = await _api.testRule(id);
      if (mounted) {
        Navigator.pop(context);
        showDialog(context: context, builder: (_) => _ResultDialog(
          title: 'Test Result', status: result['status'] as String? ?? '', output: result['output'] as String? ?? ''));
      }
    } catch (e) {
      if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
    }
  }

  void _openRuleDialog([Rule? rule]) {
    showDialog(context: context, builder: (_) => RuleDialog(api: _api, rule: rule, onSaved: _load));
  }

  Future<void> _importFromJson() async {
    try {
      final result = await _api.populateRulesFromJson();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported ${result['rules_created'] ?? 0} rules')));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: const BoxDecoration(gradient: AppTheme.gradientSuccess,
              borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
          child: Row(children: [
            const Icon(Icons.rule_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            const Expanded(child: Text('Active Rules',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
            _HeaderBtn(icon: Icons.add, label: 'New Rule', onTap: () => _openRuleDialog()),
            const SizedBox(width: 8),
            _HeaderBtn(icon: Icons.download_rounded, label: 'Import from JSON', onTap: _importFromJson),
          ]),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: AppTheme.bgCard,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                border: Border.all(color: AppTheme.border)),
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
                : _RulesTable(rules: _rules,
                    onEdit: _openRuleDialog, onDelete: _deleteRule, onTest: _testRule),
          ),
        ),
      ]),
    );
  }
}

class _RulesTable extends StatelessWidget {
  final List<Rule> rules;
  final void Function(Rule) onEdit;
  final Future<void> Function(int) onDelete;
  final Future<void> Function(int) onTest;
  const _RulesTable({required this.rules, required this.onEdit, required this.onDelete, required this.onTest});

  @override
  Widget build(BuildContext context) {
    if (rules.isEmpty) return const Center(child: Text('No rules yet — create one!', style: TextStyle(color: AppTheme.textMuted)));
    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            columnSpacing: 16,
            headingRowColor: const WidgetStatePropertyAll(Color(0xFF181830)),
            headingTextStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
            columns: const [
              DataColumn(label: Text('Rule Name')),
              DataColumn(label: Text('Priority')),
              DataColumn(label: Text('Criteria')),
              DataColumn(label: Text('Severity')),
              DataColumn(label: Text('Auto')),
              DataColumn(label: Text('Cooldown')),
              DataColumn(label: Text('Actions')),
            ],
            rows: rules.map((r) => DataRow(cells: [
              DataCell(SizedBox(width: 180, child: Text(r.name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                  maxLines: 2, overflow: TextOverflow.ellipsis))),
              DataCell(_PriorityBadge(r.priority)),
              DataCell(SizedBox(width: 160, child: _CriteriaText(rule: r))),
              DataCell(SeverityBadge(r.severity)),
              DataCell(r.autoRemediate
                  ? const Icon(Icons.check_circle, color: AppTheme.accentGreen, size: 18)
                  : const Icon(Icons.cancel_outlined, color: AppTheme.textDimmed, size: 18)),
              DataCell(r.cooldownMinutes > 0
                  ? Text('${r.cooldownMinutes}m', style: const TextStyle(color: AppTheme.accentYellow, fontSize: 12))
                  : const Text('—', style: TextStyle(color: AppTheme.textDimmed))),
              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                _ActionBtn(icon: Icons.play_arrow_rounded, label: 'Test', color: AppTheme.accentGreen, onTap: () => onTest(r.id)),
                const SizedBox(width: 4),
                _ActionBtn(icon: Icons.edit_rounded, label: 'Edit', color: AppTheme.accent, onTap: () => onEdit(r)),
                const SizedBox(width: 4),
                _ActionBtn(icon: Icons.delete_outline_rounded, label: 'Delete', color: AppTheme.accentRed, onTap: () => onDelete(r.id)),
              ])),
            ])).toList(),
          ),
        ),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  final int priority;
  const _PriorityBadge(this.priority);

  @override
  Widget build(BuildContext context) {
    final color = priority <= 20 ? AppTheme.accentRed : priority <= 50 ? AppTheme.accentYellow : AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
      child: Text('$priority', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class _CriteriaText extends StatelessWidget {
  final Rule rule;
  const _CriteriaText({required this.rule});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (rule.eventId != null) parts.add('Event: ${rule.eventId}');
    if (rule.source != null) parts.add('Source: ${rule.source}');
    if (rule.messageRegex != null) parts.add('Regex: ${rule.messageRegex}');
    return Text(parts.isEmpty ? 'All events' : parts.join(' · '),
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
        maxLines: 2, overflow: TextOverflow.ellipsis);
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 13, color: color),
    label: Text(label, style: TextStyle(color: color, fontSize: 11)),
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );
}

class _HeaderBtn extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _HeaderBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 14, color: Colors.white),
    label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
    style: TextButton.styleFrom(
      backgroundColor: Colors.white12,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

// ── Rule Create/Edit Dialog ─────────────────────────────────────────────────
class RuleDialog extends StatefulWidget {
  final ApiService api;
  final Rule? rule;
  final VoidCallback onSaved;
  const RuleDialog({super.key, required this.api, this.rule, required this.onSaved});

  @override
  State<RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<RuleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name       = TextEditingController();
  final _eventId    = TextEditingController();
  final _source     = TextEditingController();
  final _regex      = TextEditingController();
  final _script     = TextEditingController();
  final _priority   = TextEditingController();
  final _cooldown   = TextEditingController();
  final _category   = TextEditingController();
  final _severity   = TextEditingController();
  final _desc       = TextEditingController();
  final _action     = TextEditingController();
  bool _auto = false, _stop = false;
  String _scriptType = 'file';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    if (r != null) {
      _name.text      = r.name;
      _eventId.text   = r.eventId?.toString() ?? '';
      _source.text    = r.source ?? '';
      _regex.text     = r.messageRegex ?? '';
      _script.text    = r.remediationScript ?? '';
      _priority.text  = r.priority.toString();
      _cooldown.text  = r.cooldownMinutes.toString();
      _category.text  = r.category ?? '';
      _severity.text  = r.severity ?? '';
      _desc.text      = r.description ?? '';
      _action.text    = r.recommendedAction ?? '';
      _auto           = r.autoRemediate;
      _stop           = r.stopProcessing;
      _scriptType     = r.scriptType;
    } else {
      _priority.text = '100';
      _cooldown.text = '0';
    }
  }

  @override
  void dispose() {
    for (final c in [_name,_eventId,_source,_regex,_script,_priority,_cooldown,_category,_severity,_desc,_action]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final data = {
      'name': _name.text.trim(),
      'event_id': int.tryParse(_eventId.text),
      'source': _source.text.isEmpty ? null : _source.text.trim(),
      'message_regex': _regex.text.isEmpty ? null : _regex.text.trim(),
      'remediation_script': _script.text.trim(),
      'script_type': _scriptType,
      'auto_remediate': _auto,
      'stop_processing': _stop,
      'category': _category.text.isEmpty ? null : _category.text.trim(),
      'severity': _severity.text.isEmpty ? null : _severity.text.trim(),
      'description': _desc.text.isEmpty ? null : _desc.text.trim(),
      'recommended_action': _action.text.isEmpty ? null : _action.text.trim(),
      'priority': int.tryParse(_priority.text) ?? 100,
      'cooldown_minutes': int.tryParse(_cooldown.text) ?? 0,
    };
    try {
      if (widget.rule != null) {
        await widget.api.updateRule(widget.rule!.id, data);
      } else {
        await widget.api.createRule(data);
      }
      if (mounted) { Navigator.pop(context); widget.onSaved(); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
      child: Form(key: _formKey, child: Column(children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(gradient: AppTheme.gradientInfo,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          child: Row(children: [
            Icon(widget.rule != null ? Icons.edit_rounded : Icons.add_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Text(widget.rule != null ? 'Edit Rule' : 'Create Rule',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white, size: 18)),
          ]),
        ),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
          Row(children: [
            Expanded(flex: 2, child: _Field('Rule Name *', _name, required: true)),
            const SizedBox(width: 12),
            Expanded(child: _Field('Event ID', _eventId, hint: 'e.g. 7034')),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _Field('Source', _source, hint: 'e.g. Service Control Manager')),
            const SizedBox(width: 12),
            Expanded(child: _Field('Message Regex', _regex, hint: 'Optional regex')),
          ]),
          const SizedBox(height: 12),
          // Script type toggle
          Row(children: [
            const Text('Script Type:', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            const SizedBox(width: 12),
            _ScriptTypeToggle(value: _scriptType, onChanged: (v) => setState(() => _scriptType = v)),
          ]),
          const SizedBox(height: 8),
          _Field('Remediation Script', _script, hint: _scriptType == 'file' ? 'C:\\scripts\\fix.ps1' : 'PowerShell inline code', maxLines: 4),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _Field('Category', _category)),
            const SizedBox(width: 12),
            Expanded(child: _Field('Severity', _severity, hint: 'High/Medium/Low/Critical')),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _Field('Priority', _priority, hint: '100')),
            const SizedBox(width: 12),
            Expanded(child: _Field('Cooldown (mins)', _cooldown, hint: '0')),
          ]),
          const SizedBox(height: 12),
          _Field('Description', _desc, maxLines: 2),
          const SizedBox(height: 12),
          _Field('Recommended Action', _action, maxLines: 2),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: CheckboxListTile(
              value: _auto, onChanged: (v) => setState(() => _auto = v ?? false),
              title: const Text('Enable Auto-Remediation', style: TextStyle(fontSize: 13)),
              dense: true, contentPadding: EdgeInsets.zero,
            )),
            Expanded(child: CheckboxListTile(
              value: _stop, onChanged: (v) => setState(() => _stop = v ?? false),
              title: const Text('Stop Processing Further Rules', style: TextStyle(fontSize: 13, color: AppTheme.accentYellow)),
              dense: true, contentPadding: EdgeInsets.zero,
            )),
          ]),
        ]))),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.border))),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded, size: 16),
              label: Text(_saving ? 'Saving…' : 'Save Rule'),
            ),
          ]),
        ),
      ])),
    ),
  );
}

class _Field extends StatelessWidget {
  final String label; final TextEditingController ctrl;
  final String? hint; final bool required; final int maxLines;
  const _Field(this.label, this.ctrl, {this.hint, this.required = false, this.maxLines = 1});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
    const SizedBox(height: 4),
    TextFormField(
      controller: ctrl, maxLines: maxLines,
      style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
      decoration: InputDecoration(hintText: hint),
      validator: required ? (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null : null,
    ),
  ]);
}

class _ScriptTypeToggle extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _ScriptTypeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(children: [
    _TypeBtn('file', 'File Path', value, onChanged, Icons.insert_drive_file_rounded),
    const SizedBox(width: 8),
    _TypeBtn('inline', 'Inline Script', value, onChanged, Icons.code_rounded),
  ]);
}

class _TypeBtn extends StatelessWidget {
  final String v, label, current; final ValueChanged<String> onChanged; final IconData icon;
  const _TypeBtn(this.v, this.label, this.current, this.onChanged, this.icon);

  @override
  Widget build(BuildContext context) {
    final active = v == current;
    return GestureDetector(
      onTap: () => onChanged(v),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.accent.withOpacity(0.15) : AppTheme.bgCardAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? AppTheme.accent : AppTheme.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: active ? AppTheme.accent : AppTheme.textMuted),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: active ? AppTheme.accent : AppTheme.textMuted, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  final String title, message;
  const _ConfirmDialog({required this.title, required this.message});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: Text(message, style: const TextStyle(color: AppTheme.textMuted)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      ElevatedButton(
        onPressed: () => Navigator.pop(context, true),
        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
        child: const Text('Confirm'),
      ),
    ],
  );
}

class _ResultDialog extends StatelessWidget {
  final String title, status, output;
  const _ResultDialog({required this.title, required this.status, required this.output});

  @override
  Widget build(BuildContext context) => Dialog(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 560, maxHeight: 480),
    child: Column(children: [
      Container(padding: const EdgeInsets.all(16), decoration: const BoxDecoration(gradient: AppTheme.gradientInfo,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        child: Row(children: [
          const Icon(Icons.terminal_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white, size: 16)),
        ])),
      Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StatusBadge(status),
        const SizedBox(height: 12),
        Container(width: double.infinity, constraints: const BoxConstraints(maxHeight: 300),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF050510), borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border)),
          child: SingleChildScrollView(child: SelectableText(output.isEmpty ? '(no output)' : output,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF00ff88), height: 1.5)))),
      ])),
    ]),
  ));
}
