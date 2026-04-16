# Windows Event Log Remediation Scripts Guide

This document contains PowerShell remediation scripts for common Windows Event Log errors. These scripts can be used for automated system troubleshooting and recovery.

---

## Table of Contents

1. [Error 7031: Service Terminated Unexpectedly](#error-7031-service-terminated-unexpectedly)
2. [Error 7034: Service Stopped](#error-7034-service-stopped)
3. [Error 7023: Service Error](#error-7023-service-error)
4. [Error 7024: Service Specific Error](#error-7024-service-specific-error)
5. [Error 7000: Service Failed](#error-7000-service-failed)
6. [Usage Guide](#usage-guide)

---

## Error 7031: Service Terminated Unexpectedly

**Description:**  
The service terminated unexpectedly. This script handles recovery by restarting the service and configuring automatic recovery actions.

**File Name:** `Error7031_ServiceTerminatedUnexpectedly.ps1`

**Prerequisites:**
- Administrator privileges required
- Service must exist on the system
- `sfc` (System File Checker) and `DISM` tools available

**Script:**

```powershell
$serviceName = "YourServiceName"
$logFile = "C:\Temp\Event7031_Remediation.log"
$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')

function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -Append $logFile
    Write-Host "$timestamp - $message"
}

# Ensure temp directory exists
if (-not (Test-Path "C:\Temp")) { 
    New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
}

Write-Log "Starting remediation for Event ID 7031"

try {
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

    if ($null -eq $service) {
        Write-Log "ERROR: Service $serviceName not found"
        exit 1
    }

    if ($service.Status -ne "Running") {
        Write-Log "Restarting failed service: $serviceName"
        if (-not $SIMULATION_MODE) { 
            Restart-Service $serviceName -Force
            Start-Sleep -Seconds 2
        }
        Write-Log "Service restart completed"
    }

    Write-Log "Setting recovery actions..."
    if (-not $SIMULATION_MODE) {
        sc.exe failure $serviceName reset= 86400 actions= restart/5000
    } else {
        Write-Log "[SIMULATION] Would set recovery actions for $serviceName"
    }

    Write-Log "Running SFC scan..."
    if (-not $SIMULATION_MODE) { 
        sfc /scannow
    } else {
        Write-Log "[SIMULATION] Would run: sfc /scannow"
    }

    Write-Log "Running DISM restore..."
    if (-not $SIMULATION_MODE) { 
        DISM /Online /Cleanup-Image /RestoreHealth
    } else {
        Write-Log "[SIMULATION] Would run: DISM /Online /Cleanup-Image /RestoreHealth"
    }

    Write-Log "Remediation completed successfully"
}
catch {
    Write-Log "ERROR: $_"
    exit 1
}
```

**Key Actions:**
- Restarts the failed service
- Configures automatic recovery (restart after 5 seconds)
- Runs System File Checker scan
- Runs DISM system image repair

**Log Location:** `C:\Temp\Event7031_Remediation.log`

---

## Error 7034: Service Stopped

**Description:**  
The service stopped unexpectedly. This script restarts the stopped service.

**File Name:** `Error7034_ServiceStopped.ps1`

**Prerequisites:**
- Administrator privileges required
- Service must exist on the system

**Script:**

```powershell
$serviceName = "YourServiceName"
$logFile = "C:\Temp\Event7034_Remediation.log"
$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')

function Write-Log { 
    param([string]$message) 
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -Append $logFile
    Write-Host "$timestamp - $message"
}

# Ensure temp directory exists
if (-not (Test-Path "C:\Temp")) { 
    New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
}

Write-Log "Starting remediation for Event ID 7034"

try {
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    
    if ($null -eq $service) {
        Write-Log "ERROR: Service $serviceName not found"
        exit 1
    }

    if ($service.Status -eq "Stopped") {
        Write-Log "Service is stopped. Starting service: $serviceName"
        if (-not $SIMULATION_MODE) { 
            Start-Service $serviceName
            Start-Sleep -Seconds 2
        } else {
            Write-Log "[SIMULATION] Would start service: $serviceName"
        }
    } else {
        Write-Log "Service is already running with status: $($service.Status)"
    }

    Write-Log "Remediation completed successfully"
}
catch {
    Write-Log "ERROR: $_"
    exit 1
}
```

**Key Actions:**
- Checks service status
- Starts the service if stopped
- Reports service status

**Log Location:** `C:\Temp\Event7034_Remediation.log`

---

## Error 7023: Service Error

**Description:**  
A service has reported an error condition. This script checks dependencies, restarts the service, and runs system repair tools.

**File Name:** `Error7023_ServiceError.ps1`

**Prerequisites:**
- Administrator privileges required
- Service must exist on the system
- `sfc` and `DISM` tools available

**Script:**

```powershell
$serviceName = "YourServiceName"
$logFile = "C:\Temp\Event7023_Remediation.log"
$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')

function Write-Log { 
    param([string]$message) 
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -Append $logFile
    Write-Host "$timestamp - $message"
}

# Ensure temp directory exists
if (-not (Test-Path "C:\Temp")) { 
    New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
}

Write-Log "Starting remediation for Event ID 7023"

try {
    Write-Log "Checking service dependencies..."
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    
    if ($null -eq $service) {
        Write-Log "ERROR: Service $serviceName not found"
        exit 1
    }

    $dependencies = Get-Service -Name $serviceName | Select-Object -ExpandProperty DependentServices
    Write-Log "Dependent services: $(($dependencies | Measure-Object).Count) found"
    
    Write-Log "Restarting service..."
    if (-not $SIMULATION_MODE) { 
        Restart-Service $serviceName -Force
        Start-Sleep -Seconds 2
    } else {
        Write-Log "[SIMULATION] Would restart service: $serviceName"
    }

    Write-Log "Running SFC scan..."
    if (-not $SIMULATION_MODE) {
        sfc /scannow
    } else {
        Write-Log "[SIMULATION] Would run: sfc /scannow"
    }

    Write-Log "Running DISM restore..."
    if (-not $SIMULATION_MODE) {
        DISM /Online /Cleanup-Image /RestoreHealth
    } else {
        Write-Log "[SIMULATION] Would run: DISM /Online /Cleanup-Image /RestoreHealth"
    }

    Write-Log "Remediation completed successfully"
}
catch {
    Write-Log "ERROR: $_"
    exit 1
}
```

**Key Actions:**
- Checks service dependencies
- Restarts the service
- Runs System File Checker scan
- Runs DISM system image repair

**Log Location:** `C:\Temp\Event7023_Remediation.log`

---

## Error 7024: Service Specific Error

**Description:**  
A service has reported a specific error condition. This script logs detailed error information and restarts the service.

**File Name:** `Error7024_ServiceSpecificError.ps1`

**Prerequisites:**
- Administrator privileges required
- Service must exist on the system
- Event logs must be accessible

**Script:**

```powershell
$serviceName = "YourServiceName"
$logFile = "C:\Temp\Event7024_Remediation.log"
$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')

function Write-Log { 
    param([string]$message) 
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -Append $logFile
    Write-Host "$timestamp - $message"
}

# Ensure temp directory exists
if (-not (Test-Path "C:\Temp")) { 
    New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
}

Write-Log "Starting remediation for Event ID 7024"

try {
    Write-Log "Fetching error logs for Event ID 7024..."
    $errorEvents = Get-WinEvent -LogName System -ErrorAction SilentlyContinue | 
                   Where-Object {$_.Id -eq 7024} | 
                   Select-Object -First 5
    
    if ($errorEvents) {
        $errorEvents | Out-File -Append $logFile
        Write-Log "Found $(($errorEvents | Measure-Object).Count) recent events"
    } else {
        Write-Log "No recent Event ID 7024 found in System log"
    }

    Write-Log "Restarting service: $serviceName"
    if (-not $SIMULATION_MODE) {
        Restart-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    } else {
        Write-Log "[SIMULATION] Would restart service: $serviceName"
    }

    Write-Log "Remediation completed successfully"
}
catch {
    Write-Log "ERROR: $_"
    exit 1
}
```

**Key Actions:**
- Retrieves recent Event ID 7024 logs
- Logs error details for analysis
- Restarts the service

**Log Location:** `C:\Temp\Event7024_Remediation.log`

---

## Error 7000: Service Failed

**Description:**  
The service failed to start. This script sets the service to Automatic startup and attempts to start it.

**File Name:** `Error7000_ServiceFailed.ps1`

**Prerequisites:**
- Administrator privileges required
- Service must exist on the system

**Script:**

```powershell
$serviceName = "YourServiceName"
$logFile = "C:\Temp\Event7000_Remediation.log"
$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')

function Write-Log { 
    param([string]$message) 
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -Append $logFile
    Write-Host "$timestamp - $message"
}

# Ensure temp directory exists
if (-not (Test-Path "C:\Temp")) { 
    New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
}

Write-Log "Starting remediation for Event ID 7000"

try {
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    
    if ($null -eq $service) {
        Write-Log "ERROR: Service $serviceName not found"
        exit 1
    }

    Write-Log "Setting service startup type to Automatic..."
    if (-not $SIMULATION_MODE) {
        Set-Service -Name $serviceName -StartupType Automatic
    } else {
        Write-Log "[SIMULATION] Would set startup type to Automatic for: $serviceName"
    }

    Write-Log "Starting service: $serviceName"
    if (-not $SIMULATION_MODE) {
        Start-Service -Name $serviceName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    } else {
        Write-Log "[SIMULATION] Would start service: $serviceName"
    }

    Write-Log "Remediation completed successfully"
}
catch {
    Write-Log "ERROR: $_"
    exit 1
}
```

**Key Actions:**
- Sets service to Automatic startup type
- Starts the service
- Logs execution details

**Log Location:** `C:\Temp\Event7000_Remediation.log`

---

## Usage Guide

### Running Scripts

#### Standard Execution (Live Mode)
To execute a script with actual changes:
```powershell
& "C:\path\to\Error7031_ServiceTerminatedUnexpectedly.ps1"
```

#### Simulation Mode
To run in simulation mode (no actual changes):
```powershell
$env:RM_SIMULATION_MODE = '1'
& "C:\path\to\Error7031_ServiceTerminatedUnexpectedly.ps1"
```

### Customization

Before running any script, update these variables:

```powershell
$serviceName = "YourServiceName"      # Change to your service name
$logFile = "C:\Temp\EventXXXX.log"    # Optional: change log location
```

### Important Notes

1. **Administrator Rights Required:** All scripts must be run with administrator privileges
2. **Service Names:** Replace `"YourServiceName"` with the actual Windows service name
3. **Log Files:** All logs are written to `C:\Temp\` by default
4. **SFC/DISM:** Scripts for Events 7031 and 7023 require system repair tools
5. **Simulation Mode:** Set `RM_SIMULATION_MODE=1` to preview actions without executing them

### Checking Service Names

To find the correct service name:
```powershell
# List all services
Get-Service

# Find a specific service
Get-Service | Where-Object {$_.DisplayName -like "*keyword*"}

# Get service details
Get-Service -Name "ServiceName" | Format-List
```

### Viewing Logs

```powershell
# View log file content
Get-Content "C:\Temp\Event7031_Remediation.log"

# Monitor log in real-time
Get-Content "C:\Temp\Event7031_Remediation.log" -Wait
```

### Error Codes

| Exit Code | Meaning |
|-----------|---------|
| 0 | Success |
| 1 | Error occurred (see log for details) |

### System Event Log Entries

To view Windows Event Log entries:
```powershell
# View recent Event 7031
Get-WinEvent -LogName System | Where-Object {$_.Id -eq 7031} | Select-Object -First 10

# Export to CSV
Get-WinEvent -LogName System | Where-Object {$_.Id -eq 7031} | Export-Csv "events.csv"
```

---

## Script Features

### Common Features (All Scripts)

✅ **Structured Logging** - Timestamped logs with detailed messages  
✅ **Error Handling** - Try-catch blocks for robust error management  
✅ **Simulation Mode** - Safe preview mode with `RM_SIMULATION_MODE` environment variable  
✅ **Service Validation** - Checks if service exists before operations  
✅ **Directory Creation** - Auto-creates `C:\Temp` if needed  
✅ **Exit Codes** - Returns 0 for success, 1 for errors  
✅ **Console Output** - Real-time console feedback with logging  

---

## Related Events

- **Event 7000:** Service installation issues
- **Event 7023:** Service error conditions detected
- **Event 7024:** Service-specific error details
- **Event 7031:** Service crashed or terminated unexpectedly
- **Event 7034:** Service stopped abnormally

---

## Troubleshooting

### Script Won't Run
- Check PowerShell execution policy: `Get-ExecutionPolicy`
- Set to allow scripts: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`
- Ensure you have administrator privileges

### Service Not Found
- Verify service name using `Get-Service` command
- Check service is not already disabled
- Service may require services role/feature installation

### SFC/DISM Failures
- Ensure Windows is up to date
- Run with administrator privileges
- May require system restart for completion

### Permission Denied
- Run PowerShell as Administrator
- Verify account has service modification rights
- Check service permissions

---

**Last Updated:** April 9, 2026  
**Version:** 1.0  
**Scope:** Windows Service Event Log Remediation
