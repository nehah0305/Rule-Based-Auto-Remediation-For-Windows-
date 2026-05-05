import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/api_service.dart';

class TaskManagerScreen extends StatefulWidget {
  const TaskManagerScreen({super.key});
  @override
  State<TaskManagerScreen> createState() => _TaskManagerScreenState();
}

class _TaskManagerScreenState extends State<TaskManagerScreen> {
  late ApiService _api;
  bool _loading = true;
  List<dynamic> _tasks = [];
  String _lastUpdated = '';

  @override
  void initState() {
    super.initState();
    _api = ApiService();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final response = await _api.getJson('/api/tasks');
      setState(() {
        _tasks = (response['tasks'] as List?) ?? [];
        _lastUpdated = DateTime.now().toString().substring(0, 16);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tasks: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteTask(int taskId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Task?'),
        content: const Text('Are you sure you want to delete this task?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(_, true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _api.deleteJson('/api/tasks/$taskId');
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Task deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting task: $e')),
          );
        }
      }
    }
  }

  Future<void> _runTaskNow(int taskId, String taskName) async {
    try {
      await _api.postJson('/api/tasks/$taskId/run');
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Task "$taskName" executed successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error running task: $e')),
        );
      }
    }
  }

  Future<void> _toggleTaskEnabled(int taskId, bool enabled) async {
    try {
      final endpoint = enabled ? '/api/tasks/$taskId/enable' : '/api/tasks/$taskId/disable';
      await _api.postJson(endpoint);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating task: $e')),
        );
      }
    }
  }

  Future<void> _showTaskLogs(int taskId, String taskName) async {
    try {
      final response = await _api.getJson('/api/tasks/$taskId/logs?limit=20');
      final logs = (response['logs'] as List?) ?? [];

      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('Execution Logs - $taskName'),
            content: SizedBox(
              width: 600,
              height: 400,
              child: logs.isEmpty
                  ? const Center(child: Text('No execution logs'))
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final log in logs)
                            _LogEntry(log: log),
                        ],
                      ),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(_),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading logs: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              gradient: AppTheme.gradientAccent,
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Task Scheduler · ${_tasks.length} tasks${_lastUpdated.isNotEmpty ? " · Updated $_lastUpdated" : ""}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
                  tooltip: 'Refresh',
                ),
                ElevatedButton.icon(
                  onPressed: () => _showCreateTaskDialog(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New Task'),
                ),
              ],
            ),
          ),

          // Body
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                border: Border.all(color: AppTheme.border),
              ),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _tasks.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.schedule_rounded,
                                size: 48,
                                color: AppTheme.textSecondary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No scheduled tasks',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          child: DataTable(
                            columnSpacing: 20,
                            columns: const [
                              DataColumn(label: Text('Task Name')),
                              DataColumn(label: Text('Type')),
                              DataColumn(label: Text('Schedule')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Last Run')),
                              DataColumn(label: Text('Actions')),
                            ],
                            rows: _tasks.map((task) {
                              final taskId = task['id'];
                              final taskName = task['display_name'] ?? task['task_name'];
                              final taskType = task['task_type'] ?? 'unknown';
                              final schedule = '${task['schedule_type'] ?? "once"}${task["schedule_value"] != null && task["schedule_value"].isNotEmpty ? " @ ${task["schedule_value"]}" : ""}';
                              final enabled = task['enabled'] ?? false;
                              final lastRun = task['last_run_time'] != null
                                  ? task['last_run_time'].toString().substring(0, 16)
                                  : 'Never';
                              final lastStatus = task['last_run_status'] ?? 'not_run';

                              return DataRow(
                                cells: [
                                  DataCell(Text(taskName)),
                                  DataCell(_TaskTypeBadge(type: taskType)),
                                  DataCell(Text(schedule)),
                                  DataCell(
                                    Row(
                                      children: [
                                        if (enabled)
                                          const Chip(
                                            label: Text('Enabled', style: TextStyle(fontSize: 11)),
                                            backgroundColor: Color(0xFF2d5016),
                                          )
                                        else
                                          const Chip(
                                            label: Text('Disabled', style: TextStyle(fontSize: 11)),
                                            backgroundColor: Color(0xFF5a2d2d),
                                          ),
                                        const SizedBox(width: 8),
                                        if (lastStatus == 'success')
                                          const Icon(Icons.check_circle, color: Colors.green, size: 16)
                                        else if (lastStatus == 'failed')
                                          const Icon(Icons.error_outline, color: Colors.red, size: 16)
                                        else
                                          const Icon(Icons.schedule, color: AppTheme.textSecondary, size: 16),
                                      ],
                                    ),
                                  ),
                                  DataCell(Text(lastRun)),
                                  DataCell(
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.play_arrow, size: 16),
                                          tooltip: 'Run Now',
                                          onPressed: () => _runTaskNow(taskId, taskName),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.description, size: 16),
                                          tooltip: 'View Logs',
                                          onPressed: () => _showTaskLogs(taskId, taskName),
                                        ),
                                        PopupMenuButton(
                                          itemBuilder: (_) => [
                                            PopupMenuItem(
                                              child: const Text('Edit'),
                                              onTap: () => _showEditTaskDialog(task),
                                            ),
                                            PopupMenuItem(
                                              child: Text(
                                                enabled ? 'Disable' : 'Enable',
                                              ),
                                              onTap: () =>
                                                  _toggleTaskEnabled(taskId, !enabled),
                                            ),
                                            PopupMenuItem(
                                              child: const Text('Delete'),
                                              onTap: () => _deleteTask(taskId),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateTaskDialog() {
    showDialog(
      context: context,
      builder: (_) => _CreateTaskDialog(
        api: _api,
        onTaskCreated: _load,
      ),
    );
  }

  void _showEditTaskDialog(dynamic task) {
    showDialog(
      context: context,
      builder: (_) => _EditTaskDialog(
        api: _api,
        task: task,
        onTaskUpdated: _load,
      ),
    );
  }
}

class _TaskTypeBadge extends StatelessWidget {
  final String type;

  const _TaskTypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      'backend' => const Color(0xFF1e3a8a),
      'monitor' => const Color(0xFF7c2d12),
      'remediation' => const Color(0xFF14532d),
      _ => AppTheme.textSecondary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type,
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
    );
  }
}

class _LogEntry extends StatelessWidget {
  final dynamic log;

  const _LogEntry({required this.log});

  @override
  Widget build(BuildContext context) {
    final status = log['status'] ?? 'unknown';
    final time = log['execution_time'] ?? 'N/A';
    final output = log['output'] ?? '';
    final error = log['error_output'] ?? '';
    final duration = log['duration_ms'] ?? 0;

    final statusColor = switch (status) {
      'success' => Colors.green,
      'failed' => Colors.red,
      _ => AppTheme.textSecondary,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Chip(
                label: Text(
                  status.toUpperCase(),
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
                backgroundColor: statusColor,
              ),
              const SizedBox(width: 8),
              Text(
                time.toString().substring(0, 16),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text(
                '${duration}ms',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (output.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.bgInput,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                output.length > 200 ? output.substring(0, 200) + '...' : output,
                style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
              ),
            ),
          if (error.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF5a2d2d),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                error.length > 200 ? error.substring(0, 200) + '...' : error,
                style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }
}

class _CreateTaskDialog extends StatefulWidget {
  final ApiService api;
  final Function() onTaskCreated;

  const _CreateTaskDialog({required this.api, required this.onTaskCreated});

  @override
  State<_CreateTaskDialog> createState() => _CreateTaskDialogState();
}

class _CreateTaskDialogState extends State<_CreateTaskDialog> {
  late TextEditingController _nameController;
  late TextEditingController _displayNameController;
  late TextEditingController _descriptionController;
  late TextEditingController _scriptContentController;

  String _selectedType = 'backend';
  String _selectedSchedule = 'once';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _displayNameController = TextEditingController();
    _descriptionController = TextEditingController();
    _scriptContentController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _displayNameController.dispose();
    _descriptionController.dispose();
    _scriptContentController.dispose();
    super.dispose();
  }

  Future<void> _createTask() async {
    try {
      await widget.api.postJson('/api/tasks', {
        'task_name': _nameController.text.trim(),
        'display_name': _displayNameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'task_type': _selectedType,
        'script_content': _scriptContentController.text.trim(),
        'schedule_type': _selectedSchedule,
        'schedule_value': '',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task created successfully')),
        );
        Navigator.pop(context);
        widget.onTaskCreated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating task: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New Task'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Task Name',
                hintText: 'e.g., daily_backup_task',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _displayNameController,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                hintText: 'e.g., Daily Backup',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            DropdownButton<String>(
              value: _selectedType,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'backend', child: Text('Backend')),
                DropdownMenuItem(value: 'monitor', child: Text('Monitor')),
                DropdownMenuItem(value: 'remediation', child: Text('Remediation')),
              ],
              onChanged: (v) => setState(() => _selectedType = v ?? 'backend'),
            ),
            const SizedBox(height: 12),
            DropdownButton<String>(
              value: _selectedSchedule,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'once', child: Text('Once')),
                DropdownMenuItem(value: 'hourly', child: Text('Hourly')),
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
              ],
              onChanged: (v) => setState(() => _selectedSchedule = v ?? 'once'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _scriptContentController,
              decoration: const InputDecoration(
                labelText: 'PowerShell Script',
                hintText: 'Enter PowerShell script content',
              ),
              maxLines: 5,
              minLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _createTask,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _EditTaskDialog extends StatefulWidget {
  final ApiService api;
  final dynamic task;
  final Function() onTaskUpdated;

  const _EditTaskDialog({
    required this.api,
    required this.task,
    required this.onTaskUpdated,
  });

  @override
  State<_EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends State<_EditTaskDialog> {
  late TextEditingController _displayNameController;
  late TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _displayNameController =
        TextEditingController(text: widget.task['display_name']);
    _descriptionController =
        TextEditingController(text: widget.task['description']);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _updateTask() async {
    try {
      await widget.api.putJson('/api/tasks/${widget.task["id"]}', {
        'display_name': _displayNameController.text.trim(),
        'description': _descriptionController.text.trim(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task updated successfully')),
        );
        Navigator.pop(context);
        widget.onTaskUpdated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating task: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Task'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _displayNameController,
              decoration: const InputDecoration(labelText: 'Display Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _updateTask,
          child: const Text('Update'),
        ),
      ],
    );
  }
}
