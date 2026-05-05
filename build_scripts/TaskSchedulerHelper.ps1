############################################################################
#  Task Management Helper Functions for Windows Task Scheduler
#  
#  This module provides PowerShell functions to create, register, and manage
#  scheduled tasks with Windows Task Scheduler.
############################################################################

<#
.SYNOPSIS
Creates a scheduled task in Windows Task Scheduler.

.DESCRIPTION
Registers a new scheduled task with Windows Task Scheduler. Supports multiple
schedule types (once, hourly, daily, weekly, monthly).

.PARAMETER TaskName
The name of the task to create.

.PARAMETER ScriptPath
Full path to the PowerShell script to execute.

.PARAMETER ScheduleType
Type of schedule: once, hourly, daily, weekly, monthly.

.PARAMETER ScheduleValue
Schedule-specific value (e.g., time for daily, day of week for weekly).

.PARAMETER RunAsUser
User account to run the task under. Defaults to SYSTEM.

.PARAMETER RunWithHighestPrivileges
Run the task with highest privileges (administrator rights).

.EXAMPLE
New-ScheduledTaskFromScript -TaskName "DailyBackup" -ScriptPath "C:\scripts\backup.ps1" `
  -ScheduleType "daily" -ScheduleValue "02:00:00"
#>
function New-ScheduledTaskFromScript {
    param(
        [string]$TaskName,
        [string]$ScriptPath,
        [string]$ScheduleType = 'once',
        [string]$ScheduleValue = '',
        [string]$RunAsUser = 'NT AUTHORITY\SYSTEM',
        [switch]$RunWithHighestPrivileges
    )

    try {
        # Build the action to run PowerShell with the script
        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

        # Build the trigger based on schedule type
        $trigger = switch ($ScheduleType) {
            'once' {
                New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
            }
            'hourly' {
                New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 1)
            }
            'daily' {
                if ([string]::IsNullOrEmpty($ScheduleValue)) {
                    $ScheduleValue = '02:00:00'
                }
                [TimeSpan]$time = [TimeSpan]::Parse($ScheduleValue)
                New-ScheduledTaskTrigger -Daily -At $time
            }
            'weekly' {
                if ([string]::IsNullOrEmpty($ScheduleValue)) {
                    $ScheduleValue = 'Monday'
                }
                New-ScheduledTaskTrigger -Weekly -DaysOfWeek $ScheduleValue -At '02:00:00'
            }
            'monthly' {
                New-ScheduledTaskTrigger -Once -At (Get-Date).AddDays(1) | 
                    ForEach-Object { $_.Triggers[0].ScheduleByMonth = '*' ; $_ }
            }
            default {
                New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
            }
        }

        # Build settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable

        # Create the task
        $principal = New-ScheduledTaskPrincipal -UserID $RunAsUser -LogonType ServiceAccount
        if ($RunWithHighestPrivileges) {
            $principal = New-ScheduledTaskPrincipal -UserID $RunAsUser -LogonType ServiceAccount -RunLevel Highest
        }

        $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings

        # Register the task
        Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force | Out-Null

        return @{
            success = $true
            message = "Task '$TaskName' registered successfully"
            taskName = $TaskName
        }
    }
    catch {
        return @{
            success = $false
            message = "Failed to register task: $($_.Exception.Message)"
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
Retrieves details about a scheduled task.

.PARAMETER TaskName
The name of the task to retrieve.

.PARAMETER TaskPath
Optional path to the task (e.g., '\Microsoft\Windows\').

.EXAMPLE
Get-ScheduledTaskInfo -TaskName "DailyBackup"
#>
function Get-ScheduledTaskInfo {
    param(
        [string]$TaskName,
        [string]$TaskPath = '\'
    )

    try {
        $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop
        
        $lastRun = $task.LastRunTime
        $nextRun = $task.NextRunTime
        $status = $task.State

        return @{
            success = $true
            task = @{
                name = $task.TaskName
                path = $task.TaskPath
                state = $status.ToString()
                lastRunTime = $lastRun
                nextRunTime = $nextRun
                enabled = $status -eq 'Ready'
                description = $task.Description
            }
        }
    }
    catch {
        return @{
            success = $false
            message = "Failed to retrieve task: $($_.Exception.Message)"
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
Enables a scheduled task.

.PARAMETER TaskName
The name of the task to enable.
#>
function Enable-ScheduledTaskHelper {
    param([string]$TaskName)

    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        Enable-ScheduledTask -TaskName $TaskName | Out-Null
        return @{
            success = $true
            message = "Task '$TaskName' enabled successfully"
        }
    }
    catch {
        return @{
            success = $false
            message = "Failed to enable task: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
Disables a scheduled task.

.PARAMETER TaskName
The name of the task to disable.
#>
function Disable-ScheduledTaskHelper {
    param([string]$TaskName)

    try {
        Disable-ScheduledTask -TaskName $TaskName -Confirm:$false | Out-Null
        return @{
            success = $true
            message = "Task '$TaskName' disabled successfully"
        }
    }
    catch {
        return @{
            success = $false
            message = "Failed to disable task: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
Runs a scheduled task immediately.

.PARAMETER TaskName
The name of the task to run.
#>
function Invoke-ScheduledTask {
    param([string]$TaskName)

    try {
        Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        Start-Sleep -Seconds 1
        
        return @{
            success = $true
            message = "Task '$TaskName' executed successfully"
        }
    }
    catch {
        return @{
            success = $false
            message = "Failed to execute task: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
Unregisters a scheduled task.

.PARAMETER TaskName
The name of the task to unregister.
#>
function Unregister-ScheduledTaskHelper {
    param([string]$TaskName)

    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        return @{
            success = $true
            message = "Task '$TaskName' unregistered successfully"
        }
    }
    catch {
        return @{
            success = $false
            message = "Failed to unregister task: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
Gets the last execution history for a scheduled task.

.PARAMETER TaskName
The name of the task.

.PARAMETER MaxRecords
Maximum number of history records to return.
#>
function Get-ScheduledTaskHistory {
    param(
        [string]$TaskName,
        [int]$MaxRecords = 10
    )

    try {
        $history = Get-WinEvent -FilterHashtable @{
            LogName   = 'Microsoft-Windows-TaskScheduler/Operational'
            ProviderName = 'Microsoft-Windows-TaskScheduler'
            Level     = 0,1,2,3,4
        } -MaxEvents 1000 -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match $TaskName } |
        Select-Object -First $MaxRecords

        $records = $history | ForEach-Object {
            @{
                timeCreated = $_.TimeCreated
                message = $_.Message
                id = $_.Id
                level = $_.LevelDisplayName
            }
        }

        return @{
            success = $true
            records = @($records)
        }
    }
    catch {
        return @{
            success = $false
            message = "Failed to retrieve history: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
Lists all scheduled tasks in a path.

.PARAMETER TaskPath
Path to search for tasks.
#>
function Get-AllScheduledTasks {
    param([string]$TaskPath = '\')

    try {
        $tasks = Get-ScheduledTask -TaskPath $TaskPath -ErrorAction Stop
        
        $taskList = $tasks | ForEach-Object {
            @{
                name = $_.TaskName
                path = $_.TaskPath
                state = $_.State.ToString()
                enabled = $_.State -eq 'Ready'
                description = $_.Description
                lastRunTime = $_.LastRunTime
                nextRunTime = $_.NextRunTime
            }
        }

        return @{
            success = $true
            tasks = @($taskList)
            count = $taskList.Count
        }
    }
    catch {
        return @{
            success = $false
            message = "Failed to list tasks: $($_.Exception.Message)"
        }
    }
}

# Export functions for module use
Export-ModuleMember -Function @(
    'New-ScheduledTaskFromScript',
    'Get-ScheduledTaskInfo',
    'Enable-ScheduledTaskHelper',
    'Disable-ScheduledTaskHelper',
    'Invoke-ScheduledTask',
    'Unregister-ScheduledTaskHelper',
    'Get-ScheduledTaskHistory',
    'Get-AllScheduledTasks'
)
