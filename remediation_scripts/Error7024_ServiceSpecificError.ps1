# Remediation Script for Event ID 7024: Service terminated with service-specific error
# This script handles cases where a Windows service terminated due to service-specific error conditions
# It inspects error codes and attempts targeted remediation

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
$LOG_FILE = "C:\Temp\Event7024_Remediation.log"

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
    
    # Pattern 2: Service name before error code
    if ($Message -match "The (.+?) service.*error") {
        return $matches[1]
    }
    
    # Pattern 3: Windows service common pattern
    if ($Message -match "service (\w+)") {
        return $matches[1]
    }
    
    return $null
}

function Get-ErrorCodeFromMessage {
    param([string]$Message)
    
    # Look for error code pattern
    if ($Message -match "error code (\d+)") {
        return [int]$matches[1]
    }
    
    if ($Message -match "error (\d+)") {
        return [int]$matches[1]
    }
    
    return $null
}

function Get-ServiceObject {
    param([string]$ServiceName)
    
    if (-not $ServiceName) { return $null }
    
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    return $service
}

function Repair-ServiceRegistry {
    param([string]$ServiceName)
    
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
    
    if (Test-Path $regPath) {
        try {
            $imagePath = (Get-ItemProperty -Path $regPath -Name 'ImagePath' -ErrorAction Stop).ImagePath
            
            if ($imagePath -and (Test-Path $imagePath)) {
                Write-Log "Service executable found: $imagePath"
                return $true
            }
            else {
                Write-Log "Service executable not found: $imagePath"
                return $false
            }
        }
        catch {
            Write-Log ("Error reading service registry: {0}" -f $_.Exception.Message)
            return $false
        }
    }
    
    return $false
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

Write-Log "Event 7024 received: Service terminated with service-specific error"
Write-Log "Message: $message"

$serviceName = Get-ServiceNameFromMessage -Message $message
$errorCode = Get-ErrorCodeFromMessage -Message $message

Write-Log "Extracted service name: $serviceName"
Write-Log "Extracted error code: $errorCode"

if ($serviceName) {
    $service = Get-ServiceObject -ServiceName $serviceName
    
    if ($service) {
        Write-Log "Service found: $serviceName (Status: $($service.Status))"
        
        # Verify service executable exists
        $executableExists = Repair-ServiceRegistry -ServiceName $serviceName
        
        if ($SIMULATION_MODE) {
            Write-Log "[SIMULATION] Would attempt recovery for: $serviceName"
            Write-Log "[SIMULATION] Error code: $errorCode"
            Write-Log "[SIMULATION] Would restart service"
        }
        else {
            try {
                Write-Log "Attempting to recover service: $serviceName"
                
                # Stop service if running
                if ($service.Status -eq 'Running') {
                    Stop-Service -Name $serviceName -Force -ErrorAction Stop
                    Write-Log "Stopped service: $serviceName"
                    Start-Sleep -Milliseconds 500
                }
                
                # Clear any pending operations
                Set-Service -Name $serviceName -StartupType 'Automatic' -ErrorAction SilentlyContinue
                
                # Start service
                Start-Service -Name $serviceName -ErrorAction Stop
                Write-Log "Successfully started service: $serviceName"
            }
            catch {
                Write-Log ("Error recovering service: {0}" -f $_.Exception.Message)
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
$resolutionMessage = "Auto-remediation attempt for Event 7024 (Service-specific error - $serviceName, Error: $errorCode). Task completed at $timestamp."
if ($SIMULATION_MODE) {
    $resolutionMessage = "[SIMULATION] $resolutionMessage"
}
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage

Write-Log "Remediation complete"
exit 0
