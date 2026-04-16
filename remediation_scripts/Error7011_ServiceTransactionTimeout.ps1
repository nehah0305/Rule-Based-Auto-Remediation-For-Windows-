# Remediation Script for Event ID 7011: Service transaction timeout
# This script handles cases where service control transactions take too long
# It clears stalled transactions, restarts services, and performs cleanup

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$EVENT_ID = $env:RM_EVENT_ID
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = "C:\Temp\Event7011_Remediation.log"

# Create log directory if it doesn't exist
if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    $msg = "[$timestamp] $Message"
    Add-Content -Path $LOG_FILE -Value $msg -Force
}

function Get-ServiceNameFromMessage {
    param([string]$Message)
    
    # Pattern 1: Service name in quotes
    if ($Message -match "service '([^']+)'") {
        return $matches[1]
    }
    
    # Pattern 2: Service name after "The"
    if ($Message -match "The (.+?) service") {
        return $matches[1]
    }
    
    # Pattern 3: Service name before "transaction"
    if ($Message -match "(\w+).*transaction") {
        return $matches[1]
    }
    
    return $null
}

function Get-ServiceObject {
    param([string]$ServiceName)
    
    if (-not $ServiceName) { return $null }
    
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    return $service
}

function Clear-ServiceTransactions {
    param([string]$ServiceName)
    
    try {
        Write-Log "Attempting to clear stalled transactions for: $ServiceName"
        
        # Get all processes related to service
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
        $imagePath = (Get-ItemProperty -Path $regPath -Name 'ImagePath' -ErrorAction SilentlyContinue).ImagePath
        
        if ($imagePath) {
            $processName = [System.IO.Path]::GetFileNameWithoutExtension($imagePath -replace '^"', '' -replace '"$', '')
            $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
            
            if ($processes) {
                Write-Log "Found $($processes.Count) process(es) for service"
                return $processes
            }
        }
        
        return @()
    }
    catch {
        Write-Log ("Error clearing transactions: {0}" -f $_.Exception.Message)
        return @()
    }
}

function Write-ResolutionEvent {
    param(
        [int]$EventId,
        [string]$Message
    )
    
    try {
        Write-EventLog -LogName $LOG_NAME `
                       -Source $SOURCE `
                       -EventId $EventId `
                       -EntryType 'Information' `
                       -Message $Message `
                       -ErrorAction Stop
    }
    catch {
        Write-Log ("Error writing event: {0}" -f $_.Exception.Message)
    }
}

Write-Log "Event 7011 received: Service transaction timeout"
Write-Log "Message: $message"

$serviceName = Get-ServiceNameFromMessage -Message $message
Write-Log "Extracted service name: $serviceName"

if ($serviceName) {
    $service = Get-ServiceObject -ServiceName $serviceName
    
    if ($service) {
        Write-Log "Service found: $serviceName (Status: $($service.Status))"
        
        # Get stalled processes
        $stalledProcesses = Clear-ServiceTransactions -ServiceName $serviceName
        
        if ($SIMULATION_MODE) {
            Write-Log "[SIMULATION] Would terminate stalled processes: $($stalledProcesses.Name -join ', ')"
            Write-Log "[SIMULATION] Would force-restart service: $serviceName"
        }
        else {
            # Terminate stalled processes
            foreach ($proc in $stalledProcesses) {
                try {
                    Write-Log ("Terminating stalled process: {0} (PID: {1})" -f $proc.Name, $proc.Id)
                    Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                    Write-Log ("Successfully terminated: {0}" -f $proc.Name)
                }
                catch {
                    Write-Log ("Error terminating process: {0}" -f $_.Exception.Message)
                }
            }
            
            Start-Sleep -Milliseconds 500
            
            # Force stop service
            try {
                Write-Log "Attempting force-stop of service: $serviceName"
                
                if ($service.Status -eq 'Running') {
                    Stop-Service -Name $serviceName -Force -ErrorAction Stop
                    Write-Log "Force-stopped service: $serviceName"
                }
                
                Start-Sleep -Milliseconds 500
                
                # Set to automatic
                Set-Service -Name $serviceName -StartupType 'Automatic' -ErrorAction Stop
                
                # Restart service
                Write-Log "Restarting service: $serviceName"
                Start-Service -Name $serviceName -ErrorAction Stop
                Write-Log "Successfully restarted service: $serviceName"
            }
            catch {
                Write-Log ("Error managing service: {0}" -f $_.Exception.Message)
            }
        }
    }
    else {
        Write-Log "Service not found: $serviceName"
    }
}
else {
    Write-Log "Could not extract service name from message"
}

# Fallback system diagnostics
Write-Log "Running fallback system diagnostics..."

if ($SIMULATION_MODE) {
    Write-Log "[SIMULATION] Would run: sfc /scannow"
    Write-Log "[SIMULATION] Would run: Repair-WindowsImage"
}
else {
    Write-Log "Running system file checker..."
    & cmd.exe /c "sfc /scannow" 2>&1 | Out-Null
    
    Write-Log "Running DISM image repair..."
    & cmd.exe /c "DISM /Online /Cleanup-Image /RestoreHealth" 2>&1 | Out-Null
}

# Write resolution event
$resolutionMessage = "Auto-remediation attempt for Event 7011 (Service transaction timeout - $serviceName). Task completed at $timestamp."
if ($SIMULATION_MODE) {
    $resolutionMessage = "[SIMULATION] $resolutionMessage"
}
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage

Write-Log "Remediation complete"
exit 0
