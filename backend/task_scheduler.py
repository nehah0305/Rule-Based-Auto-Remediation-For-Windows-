"""
Task Scheduler Management Module
Handles creation, management, and monitoring of Windows Scheduled Tasks
"""

import os
import sqlite3
import subprocess
import json
import shutil
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

DB_PATH = os.path.join(os.path.dirname(__file__), 'rules.db')
DATA_DIR = os.path.join(os.path.dirname(__file__), 'data')
TASKS_DIR = os.path.join(DATA_DIR, 'scheduled_tasks')

# Resolve PowerShell path once at startup
_POWERSHELL = (
    shutil.which('powershell')
    or shutil.which('powershell.exe')
    or r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
)

Path(TASKS_DIR).mkdir(parents=True, exist_ok=True)


def _conn():
    """Get database connection via models' centralized WAL-enabled factory."""
    # Imported lazily to avoid any import-order coupling at module load.
    import models
    return models.get_connection()


def _run_powershell(script):
    """Execute PowerShell script and return output."""
    try:
        result = subprocess.run(
            [_POWERSHELL, '-NoProfile', '-Command', script],
            capture_output=True,
            text=True,
            timeout=30,
        )
        return {
            'success': result.returncode == 0,
            'stdout': result.stdout.strip(),
            'stderr': result.stderr.strip(),
            'exit_code': result.returncode,
        }
    except subprocess.TimeoutExpired:
        return {
            'success': False,
            'stdout': '',
            'stderr': 'PowerShell command timed out',
            'exit_code': -1,
        }
    except Exception as e:
        return {
            'success': False,
            'stdout': '',
            'stderr': str(e),
            'exit_code': -1,
        }


def create_task(task_name, display_name, description, task_type, script_path=None, 
                script_content=None, schedule_type='once', schedule_value=''):
    """
    Create a new scheduled task.
    
    Args:
        task_name: Unique identifier for the task (used in Windows Task Scheduler)
        display_name: User-friendly display name
        description: Task description
        task_type: 'backend', 'monitor', or 'remediation'
        script_path: Path to script file (or None if script_content provided)
        script_content: Script content (optional if script_path provided)
        schedule_type: 'once', 'daily', 'hourly', 'weekly', 'monthly'
        schedule_value: Schedule details (e.g., '14:30' for daily at 2:30 PM)
    """
    conn = _conn()
    c = conn.cursor()

    # UTC like every other timestamp in the system — the frontend converts
    # to local for display (utils/time_fmt.dart).
    now = datetime.utcnow().isoformat()

    try:
        # Save script if provided
        if script_content:
            script_file = os.path.join(TASKS_DIR, f'{task_name}.ps1')
            with open(script_file, 'w') as f:
                f.write(script_content)
            script_path = script_file
        
        # Insert into database
        c.execute('''
            INSERT INTO scheduled_tasks (
                task_name, display_name, description, task_type,
                script_path, schedule_type, schedule_value,
                created_at, updated_at, enabled, last_run_status
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            task_name, display_name, description, task_type,
            script_path, schedule_type, schedule_value,
            now, now, 1, 'not_run'
        ))
        
        conn.commit()
        task_id = c.lastrowid
        
        return {
            'success': True,
            'message': f'Task "{display_name}" created successfully',
            'task_id': task_id,
            'task_name': task_name,
        }
    except sqlite3.IntegrityError:
        return {
            'success': False,
            'message': f'Task "{task_name}" already exists',
        }
    except Exception as e:
        return {
            'success': False,
            'message': f'Error creating task: {str(e)}',
        }
    finally:
        conn.close()


def register_task_with_windows(task_name, script_path, schedule_type, schedule_value):
    """
    Register a scheduled task with Windows Task Scheduler.
    
    Args:
        task_name: Task name
        script_path: Path to PowerShell script
        schedule_type: Schedule type
        schedule_value: Schedule details
    """
    # Build the Register-ScheduledTask PowerShell command
    ps_script = f'''
    $taskName = "{task_name}"
    $scriptPath = "{script_path}"
    $scheduleType = "{schedule_type}"
    
    # Create action
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    
    # Create trigger based on schedule type
    $trigger = $null
    switch ($scheduleType) {{
        "once" {{ $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) }}
        "hourly" {{ $trigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 365) -Once }}
        "daily" {{ $trigger = New-ScheduledTaskTrigger -Daily -At "{schedule_value}" }}
        "weekly" {{ $trigger = New-ScheduledTaskTrigger -Weekly -At "{schedule_value}" }}
        "monthly" {{ $trigger = New-ScheduledTaskTrigger -Monthly -At "{schedule_value}" }}
    }}
    
    # Create principal (run as SYSTEM)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    # Register the task
    try {{
        $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existingTask) {{
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        }}
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force
        Write-Output "Task registered successfully"
    }} catch {{
        Write-Error "Failed to register task: $_"
    }}
    '''
    
    return _run_powershell(ps_script)


def list_tasks():
    """List all scheduled tasks from database."""
    conn = _conn()
    c = conn.cursor()
    
    try:
        c.execute('''
            SELECT id, task_name, display_name, description, task_type,
                   enabled, created_at, last_run_time, last_run_status, next_run_time
            FROM scheduled_tasks
            ORDER BY created_at DESC
        ''')
        
        rows = c.fetchall()
        tasks = []
        for row in rows:
            tasks.append({
                'id': row[0],
                'task_name': row[1],
                'display_name': row[2],
                'description': row[3],
                'task_type': row[4],
                'enabled': bool(row[5]),
                'created_at': row[6],
                'last_run_time': row[7],
                'last_run_status': row[8],
                'next_run_time': row[9],
            })
        
        return {
            'success': True,
            'tasks': tasks,
        }
    except Exception as e:
        return {
            'success': False,
            'message': f'Error listing tasks: {str(e)}',
            'tasks': [],
        }
    finally:
        conn.close()


def get_task(task_id):
    """Get details of a specific task."""
    conn = _conn()
    c = conn.cursor()
    
    try:
        c.execute('''
            SELECT id, task_name, display_name, description, task_type,
                   script_path, schedule_type, schedule_value, enabled,
                   created_at, updated_at, last_run_time, last_run_status, next_run_time
            FROM scheduled_tasks WHERE id = ?
        ''', (task_id,))
        
        row = c.fetchone()
        if not row:
            return {
                'success': False,
                'message': 'Task not found',
            }
        
        # Read script content if available
        script_content = ''
        if row[5]:  # script_path
            try:
                with open(row[5], 'r') as f:
                    script_content = f.read()
            except:
                pass
        
        return {
            'success': True,
            'task': {
                'id': row[0],
                'task_name': row[1],
                'display_name': row[2],
                'description': row[3],
                'task_type': row[4],
                'script_path': row[5],
                'script_content': script_content,
                'schedule_type': row[6],
                'schedule_value': row[7],
                'enabled': bool(row[8]),
                'created_at': row[9],
                'updated_at': row[10],
                'last_run_time': row[11],
                'last_run_status': row[12],
                'next_run_time': row[13],
            }
        }
    except Exception as e:
        return {
            'success': False,
            'message': f'Error retrieving task: {str(e)}',
        }
    finally:
        conn.close()


def update_task(task_id, display_name=None, description=None, schedule_type=None, 
                schedule_value=None, script_content=None):
    """Update a scheduled task."""
    conn = _conn()
    c = conn.cursor()
    
    try:
        # Get current task
        c.execute('SELECT script_path FROM scheduled_tasks WHERE id = ?', (task_id,))
        row = c.fetchone()
        if not row:
            return {'success': False, 'message': 'Task not found'}
        
        script_path = row[0]
        now = datetime.utcnow().isoformat()
        
        # Update script if provided
        if script_content and script_path:
            with open(script_path, 'w') as f:
                f.write(script_content)
        
        # Build update query
        updates = []
        params = []
        if display_name is not None:
            updates.append('display_name = ?')
            params.append(display_name)
        if description is not None:
            updates.append('description = ?')
            params.append(description)
        if schedule_type is not None:
            updates.append('schedule_type = ?')
            params.append(schedule_type)
        if schedule_value is not None:
            updates.append('schedule_value = ?')
            params.append(schedule_value)
        
        updates.append('updated_at = ?')
        params.append(now)
        params.append(task_id)
        
        c.execute(f'UPDATE scheduled_tasks SET {", ".join(updates)} WHERE id = ?', params)
        conn.commit()
        
        return {
            'success': True,
            'message': 'Task updated successfully',
        }
    except Exception as e:
        return {
            'success': False,
            'message': f'Error updating task: {str(e)}',
        }
    finally:
        conn.close()


def delete_task(task_id, task_name=None):
    """Delete a scheduled task."""
    conn = _conn()
    c = conn.cursor()
    
    try:
        # Get task info
        c.execute('SELECT task_name, script_path FROM scheduled_tasks WHERE id = ?', (task_id,))
        row = c.fetchone()
        if not row:
            return {'success': False, 'message': 'Task not found'}
        
        if not task_name:
            task_name = row[0]
        script_path = row[1]
        
        # Delete script file
        if script_path and os.path.exists(script_path):
            try:
                os.remove(script_path)
            except:
                pass
        
        # Delete from database
        c.execute('DELETE FROM scheduled_tasks WHERE id = ?', (task_id,))
        conn.commit()
        
        # Unregister from Windows Task Scheduler
        ps_script = f'''
        $taskName = "{task_name}"
        try {{
            $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if ($task) {{
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            }}
        }} catch {{}}
        '''
        _run_powershell(ps_script)
        
        return {
            'success': True,
            'message': 'Task deleted successfully',
        }
    except Exception as e:
        return {
            'success': False,
            'message': f'Error deleting task: {str(e)}',
        }
    finally:
        conn.close()


def enable_task(task_id):
    """Enable a scheduled task."""
    return _set_task_enabled(task_id, True)


def disable_task(task_id):
    """Disable a scheduled task."""
    return _set_task_enabled(task_id, False)


def _set_task_enabled(task_id, enabled):
    """Set task enabled status."""
    conn = _conn()
    c = conn.cursor()
    
    try:
        now = datetime.utcnow().isoformat()
        c.execute(
            'UPDATE scheduled_tasks SET enabled = ?, updated_at = ? WHERE id = ?',
            (1 if enabled else 0, now, task_id)
        )
        conn.commit()
        
        return {
            'success': True,
            'message': f'Task {"enabled" if enabled else "disabled"} successfully',
        }
    except Exception as e:
        return {
            'success': False,
            'message': f'Error updating task: {str(e)}',
        }
    finally:
        conn.close()


def run_task_now(task_id):
    """Run a task immediately."""
    conn = _conn()
    c = conn.cursor()
    
    try:
        c.execute('SELECT task_name, script_path FROM scheduled_tasks WHERE id = ?', (task_id,))
        row = c.fetchone()
        if not row:
            return {'success': False, 'message': 'Task not found'}
        
        task_name, script_path = row
        
        if not script_path or not os.path.exists(script_path):
            return {'success': False, 'message': 'Script file not found'}
        
        # Execute the script
        start_time = datetime.utcnow()
        result = _run_powershell(f'& "{script_path}"')
        end_time = datetime.utcnow()
        duration_ms = int((end_time - start_time).total_seconds() * 1000)

        now = datetime.utcnow().isoformat()
        status = 'success' if result['success'] else 'failed'
        
        # Log execution
        c.execute('''
            INSERT INTO task_execution_logs (
                task_id, execution_time, status, exit_code, output, error_output, duration_ms, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            task_id, now, status, result['exit_code'],
            result['stdout'], result['stderr'], duration_ms, now
        ))
        
        # Update task's last run info
        c.execute('''
            UPDATE scheduled_tasks
            SET last_run_time = ?, last_run_status = ?
            WHERE id = ?
        ''', (now, status, task_id))
        
        conn.commit()
        
        return {
            'success': True,
            'message': f'Task executed: {status}',
            'execution': {
                'status': status,
                'exit_code': result['exit_code'],
                'stdout': result['stdout'],
                'stderr': result['stderr'],
                'duration_ms': duration_ms,
            }
        }
    except Exception as e:
        return {
            'success': False,
            'message': f'Error running task: {str(e)}',
        }
    finally:
        conn.close()


def get_task_logs(task_id, limit=50):
    """Get execution logs for a task."""
    conn = _conn()
    c = conn.cursor()
    
    try:
        c.execute('''
            SELECT id, execution_time, status, exit_code, output, error_output, duration_ms, created_at
            FROM task_execution_logs
            WHERE task_id = ?
            ORDER BY execution_time DESC
            LIMIT ?
        ''', (task_id, limit))
        
        logs = []
        for row in c.fetchall():
            logs.append({
                'id': row[0],
                'execution_time': row[1],
                'status': row[2],
                'exit_code': row[3],
                'output': row[4],
                'error_output': row[5],
                'duration_ms': row[6],
                'created_at': row[7],
            })
        
        return {
            'success': True,
            'logs': logs,
        }
    except Exception as e:
        return {
            'success': False,
            'message': f'Error retrieving logs: {str(e)}',
            'logs': [],
        }
    finally:
        conn.close()
