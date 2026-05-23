# Remediate_SystemRepair_Fallback_v2.ps1
# Deep System Repair for Core Windows Module Crashes

param()

$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $output = "[$Level] [$timestamp] $Message"
    Write-Host $output
    
    try {
        Add-Content -Path "$PSScriptRoot/../backend/data/remediation_system.log" -Value "[SYSREPAIR-$Level] $output" -ErrorAction SilentlyContinue
    } catch {}
}

function Invoke-SFC {
    param([bool]$SimMode = $false)
    
    Write-Log "Starting SFC scan..." INFO
    
    if ($SimMode) {
        Write-Log "[SIM] SFC scan in simulation mode" WARN
        Start-Sleep -Seconds 2
        return $true
    }
    
    try {
        $proc = & sfc.exe /scannow 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "SFC completed successfully" INFO
            return $true
        } else {
            Write-Log "SFC failed with code: $LASTEXITCODE" WARN
            return $false
        }
    } catch {
        Write-Log "SFC exception: $_" ERROR
        return $false
    }
}

function Invoke-DISM {
    param([bool]$SimMode = $false)
    
    Write-Log "Starting DISM repair..." WARN
    
    if ($SimMode) {
        Write-Log "[SIM] DISM repair in simulation mode" WARN
        Start-Sleep -Seconds 3
        return $true
    }
    
    try {
        $proc = & dism.exe /Online /Cleanup-Image /RestoreHealth 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "DISM completed successfully" INFO
            return $true
        } else {
            Write-Log "DISM failed with code: $LASTEXITCODE - trying component cleanup" WARN
            
            $proc2 = & dism.exe /Online /Cleanup-Image /StartComponentCleanup 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "DISM component cleanup succeeded" INFO
                return $true
            } else {
                Write-Log "Component cleanup failed with code: $LASTEXITCODE" ERROR
                return $false
            }
        }
    } catch {
        Write-Log "DISM exception: $_" ERROR
        return $false
    }
}

function Main {
    $simMode = $env:RM_SIMULATION_MODE -eq '1'
    $faultingModule = $env:RM_FAULTING_MODULE -or 'unknown'
    $eventId = $env:RM_EVENT_ID -or '1000'
    
    Write-Log "=== Deep System Repair Started ===" INFO
    Write-Log "Faulting Module: $faultingModule | Event ID: $eventId" INFO
    Write-Log "Simulation Mode: $simMode" INFO
    
    # Try SFC first
    $sfcResult = Invoke-SFC -SimMode $simMode
    if ($sfcResult) {
        Write-Log "Repair successful via SFC" INFO
        return 0
    }
    
    # Escalate to DISM if SFC failed
    Write-Log "SFC insufficient, escalating to DISM..." WARN
    $dismResult = Invoke-DISM -SimMode $simMode
    if ($dismResult) {
        Write-Log "Repair successful via DISM" INFO
        return 0
    }
    
    # Both failed
    Write-Log "Both SFC and DISM failed - manual intervention required" ERROR
    return 1
}

try {
    $exitCode = Main
    exit $exitCode
} catch {
    Write-Log "Unhandled exception: $_" ERROR
    exit 1
}
