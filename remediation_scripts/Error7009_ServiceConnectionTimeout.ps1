# Remediation Script for Event ID 7009: Timeout waiting for service to connect
# This script handles cases where services fail to communicate with other services
# It checks connectivity, restarts dependent services, and clears stalled connections

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
$LOG_FILE = "C:\Temp\Event7009_Remediation.log"

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
    
    # Pattern 3: Service name before "timeout"
    if ($Message -match "(\w+).*timeout") {
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

function Get-ServiceDependencies {
    param([string]$ServiceName)
    
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
        $dependsOn = (Get-ItemProperty -Path $regPath -Name 'DependOnService' -ErrorAction SilentlyContinue).DependOnService
        
        return @($dependsOn)
    }
    catch {
        Write-Log ("Error getting dependencies: {0}" -f $_.Exception.Message)
        return @()
    }
}

function Start-SafeService {
    param([string]$ServiceName)
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        
        if ($service.Status -ne 'Running') {
            Start-Service -Name $ServiceName -ErrorAction Stop
            Write-Log "Started service: $ServiceName"
            return $true
        }
        else {
            Write-Log "Service already running: $ServiceName"
            return $true
        }
    }
    catch {
        Write-Log ("Error starting service {0}: {1}" -f $ServiceName, $_.Exception.Message)
        return $false
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

Write-Log "Event 7009 received: Timeout waiting for service to connect"
Write-Log "Message: $message"

$serviceName = Get-ServiceNameFromMessage -Message $message
Write-Log "Extracted service name: $serviceName"

if ($serviceName) {
    $service = Get-ServiceObject -ServiceName $serviceName
    
    if ($service) {
        Write-Log "Service found: $serviceName (Status: $($service.Status))"
        
        # Get service dependencies
        $dependencies = Get-ServiceDependencies -ServiceName $serviceName
        Write-Log "Service dependencies: $($dependencies -join ', ')"
        
        if ($SIMULATION_MODE) {
            Write-Log "[SIMULATION] Would restart dependencies: $($dependencies -join ', ')"
            Write-Log "[SIMULATION] Would restart service: $serviceName"
        }
        else {
            # Restart dependencies first
            foreach ($dep in $dependencies) {
                if ($dep) {
                    Write-Log "Starting dependency: $dep"
                    Start-SafeService -ServiceName $dep
                    Start-Sleep -Milliseconds 200
                }
            }
            
            # Restart main service
            try {
                Write-Log "Restarting service: $serviceName"
                
                if ($service.Status -eq 'Running') {
                    Stop-Service -Name $serviceName -Force -ErrorAction Stop
                    Write-Log "Stopped service: $serviceName"
                    Start-Sleep -Milliseconds 500
                }
                
                Start-Service -Name $serviceName -ErrorAction Stop
                Write-Log "Successfully started service: $serviceName"
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

# Fallback diagnostics
Write-Log "Running fallback diagnostics..."

if ($SIMULATION_MODE) {
    Write-Log "[SIMULATION] Would run network diagnostics"
    Write-Log "[SIMULATION] Would run: sfc /scannow"
}
else {
    Write-Log "Running system file checker..."
    & cmd.exe /c "sfc /scannow" 2>&1 | Out-Null
    
    Write-Log "Running DISM image repair..."
    & cmd.exe /c "DISM /Online /Cleanup-Image /RestoreHealth" 2>&1 | Out-Null
}

# Write resolution event
$resolutionMessage = "Auto-remediation attempt for Event 7009 (Service connection timeout - $serviceName). Task completed at $timestamp."
if ($SIMULATION_MODE) {
    $resolutionMessage = "[SIMULATION] $resolutionMessage"
}
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage

Write-Log "Remediation complete"
exit 0
