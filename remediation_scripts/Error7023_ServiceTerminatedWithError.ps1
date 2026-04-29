# Remediation Script for Event ID 7023: Service terminated with an error
# This script handles cases where a Windows service terminated abnormally with a specific error code
# It attempts to restart the service and performs diagnostics if needed

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
$LOG_FILE = "C:\Temp\Event7023_Remediation.log"

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
    
    # Pattern 2: Service name before "terminated"
    if ($Message -match "The (.+?) service") {
        return $matches[1]
    }
    
    # Pattern 3: Windows service common name
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

# Extract service name from event message
Write-Log "Event 7023 received: Service terminated with error"
Write-Log "Message: $message"

$serviceName = Get-ServiceNameFromMessage -Message $message
Write-Log "Extracted service name: $serviceName"

if ($serviceName) {
    $service = Get-ServiceObject -ServiceName $serviceName
    
    if ($service) {
        Write-Log "Service found: $serviceName (Status: $($service.Status))"
        
        if ($SIMULATION_MODE) {
            Write-Log "[SIMULATION] Would restart service: $serviceName"
            Write-Log "[SIMULATION] Current status: $($service.Status)"
            Write-Log "[SIMULATION] Startup type: $($service.StartType)"
        }
        else {
            try {
                Write-Log "Attempting to restart service: $serviceName"
                
                if ($service.Status -eq 'Running') {
                    Stop-Service -Name $serviceName -Force -ErrorAction Stop
                    Write-Log "Stopped service: $serviceName"
                    Start-Sleep -Milliseconds 500
                }
                
                Start-Service -Name $serviceName -ErrorAction Stop
                Write-Log "Successfully started service: $serviceName"
                
                # Update startup type to Automatic to prevent recurrence
                Set-Service -Name $serviceName -StartupType 'Automatic' -ErrorAction Stop
                Write-Log "Set startup type to Automatic for: $serviceName"
            }
            catch {
                Write-Log ("Error restarting service: {0}" -f $_.Exception.Message)
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

# Fallback diagnostics if service not found or restart failed
if (-not $service -or ($SIMULATION_MODE -eq $false -and (Get-Service -Name $serviceName -ErrorAction SilentlyContinue).Status -ne 'Running')) {
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
}

# Write resolution event to Event Log
$resolutionMessage = "Auto-remediation attempt for Event 7023 (Service terminated with error - $serviceName). Task completed at $timestamp."
if ($SIMULATION_MODE) {
    $resolutionMessage = "[SIMULATION] $resolutionMessage"
}
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage

Write-Log "Remediation complete"
exit 0
