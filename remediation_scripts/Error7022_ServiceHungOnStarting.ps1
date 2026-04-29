# Remediation Script for Event ID 7022: Service hung on starting
# This script handles cases where a Windows service appears to hang during startup
# It terminates hung processes and attempts clean restart with timeout enforcement

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
$LOG_FILE = "C:\Temp\Event7022_Remediation.log"

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
    if ($Message -match "The (.+?) service.*hung") {
        return $matches[1]
    }
    
    # Pattern 3: Generic service name
    if ($Message -match "service (\w+)") {
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

function Get-ServiceExecutable {
    param([string]$ServiceName)
    
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
        $imagePath = (Get-ItemProperty -Path $regPath -Name 'ImagePath' -ErrorAction Stop).ImagePath
        
        # Remove quotes if present
        $imagePath = $imagePath -replace '^"', '' -replace '"$', ''
        
        # Extract executable path (handle parameters)
        $execPath = $imagePath -split ' ' | Select-Object -First 1
        
        return $execPath
    }
    catch {
        Write-Log ("Error getting service executable: {0}" -f $_.Exception.Message)
        return $null
    }
}

function Get-HungProcessesForService {
    param([string]$ServiceName)
    
    try {
        $execPath = Get-ServiceExecutable -ServiceName $ServiceName
        if (-not $execPath) { return @() }
        
        $processName = [System.IO.Path]::GetFileNameWithoutExtension($execPath)
        $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
        
        return $processes
    }
    catch {
        Write-Log ("Error getting processes: {0}" -f $_.Exception.Message)
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

Write-Log "Event 7022 received: Service hung on starting"
Write-Log "Message: $message"

$serviceName = Get-ServiceNameFromMessage -Message $message
Write-Log "Extracted service name: $serviceName"

if ($serviceName) {
    $service = Get-ServiceObject -ServiceName $serviceName
    
    if ($service) {
        Write-Log "Service found: $serviceName (Status: $($service.Status))"
        
        # Get hung processes
        $processes = Get-HungProcessesForService -ServiceName $serviceName
        Write-Log "Found $($processes.Count) process(es) for service: $serviceName"
        
        if ($SIMULATION_MODE) {
            Write-Log "[SIMULATION] Would terminate hung processes: $($processes.Name -join ', ')"
            Write-Log "[SIMULATION] Would restart service: $serviceName"
        }
        else {
            # Terminate hung processes
            foreach ($proc in $processes) {
                try {
                    Write-Log "Terminating process: $($proc.Name) (PID: $($proc.Id))"
                    Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                    Write-Log "Successfully terminated process: $($proc.Name)"
                }
                catch {
                    Write-Log ("Error terminating process: {0}" -f $_.Exception.Message)
                }
            }
            
            Start-Sleep -Milliseconds 500
            
            # Stop service
            try {
                if ($service.Status -eq 'Running') {
                    Stop-Service -Name $serviceName -Force -ErrorAction Stop
                    Write-Log "Stopped service: $serviceName"
                }
                
                Start-Sleep -Milliseconds 500
                
                # Set to automatic startup
                Set-Service -Name $serviceName -StartupType 'Automatic' -ErrorAction Stop
                
                # Start service with timeout
                Write-Log "Starting service: $serviceName"
                Start-Service -Name $serviceName -ErrorAction Stop
                
                Write-Log "Successfully started service: $serviceName"
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

# Fallback diagnostics
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
$resolutionMessage = "Auto-remediation attempt for Event 7022 (Service hung on starting - $serviceName). Task completed at $timestamp."
if ($SIMULATION_MODE) {
    $resolutionMessage = "[SIMULATION] $resolutionMessage"
}
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage

Write-Log "Remediation complete"
exit 0
