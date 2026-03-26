# LowDiskSpace_Remediation.ps1
# PowerShell script for monitoring and remediating low disk space on local drives
# Run as Administrator if needed for cleanup actions.
# WARNING: Review and test in a safe environment.

$EVENT_ID = 2013
$DESCRIPTION = 'Low Disk Space'
$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')

# Set thresholds
$minFreeGB = 5      # Minimum free space in GB
$minFreePct = 10    # Minimum free space in percent

function Check-DiskSpace {
    param (
        [int]$Count = 10
    )

    $events = Get-WinEvent -LogName System -MaxEvents $Count -FilterHashTable @{ Id = $EVENT_ID; Level = 1,2 } -ErrorAction SilentlyContinue |
        Sort-Object TimeCreated -Descending

    return $events
}

function Clean-DiskSpace {
    param (
        [string]$Drive
    )

    Write-Host "Starting disk cleanup for drive $Drive..."

    if ($SIMULATION_MODE) {
        Write-Host "[SIMULATION MODE] Skipping real cleanup actions for safety."
        Write-Host "[SIMULATION MODE] Would execute the following cleanup steps:"
        Write-Host "  1. Clear Temp files: Remove-Item -Path `"$env:TEMP\*`" -Recurse -Force"
        Write-Host "  2. Clear Windows Temp: Remove-Item -Path `"C:\Windows\Temp\*`" -Recurse -Force"
        Write-Host "  3. Empty Recycle Bin: Clear-RecycleBin -Force"
        Write-Host "  4. Clean prefetch: Remove-Item -Path `"C:\Windows\Prefetch\*`" -Force"
        Write-Host "[SIMULATION MODE] Skipping real command execution."
        return
    }

    # Real cleanup (only if not in simulation mode)
    try {
        # Clean user temp files
        Write-Host "Cleaning temp files from $env:TEMP..."
        Get-ChildItem -Path $env:TEMP -Recurse -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Host "User temp files cleaned."

        # Clean Windows temp files (requires elevation)
        if (Test-Path 'C:\Windows\Temp') {
            Write-Host "Cleaning Windows temp files..."
            Get-ChildItem -Path 'C:\Windows\Temp' -Recurse -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Remove-Item -Force -ErrorAction SilentlyContinue
            Write-Host "Windows temp files cleaned."
        }

        # Empty Recycle Bin
        Write-Host "Emptying Recycle Bin..."
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-Host "Recycle Bin emptied."

        # Clean prefetch (if accessible)
        if (Test-Path 'C:\Windows\Prefetch') {
            Write-Host "Cleaning prefetch cache..."
            Get-ChildItem -Path 'C:\Windows\Prefetch' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Write-Host "Prefetch cache cleaned."
        }

        Write-Host "Disk cleanup completed successfully."
    }
    catch {
        Write-Host "Error during cleanup: $_"
    }
}

function Analyze-DiskHealth {
    param (
        [string]$Drive,
        [decimal]$FreeGB,
        [decimal]$FreePct
    )

    Write-Host "Analyzing drive health for $Drive..."
    Write-Host "Free Space: $FreeGB GB ($FreePct% of total)"

    if ($FreeGB -lt $minFreeGB -or $FreePct -lt $minFreePct) {
        Write-Host "WARNING: Low disk space detected on $Drive!"
        Write-Host "Initiating remediation..."
        Clean-DiskSpace -Drive $Drive
    }
    else {
        Write-Host "Drive $Drive has sufficient free space."
    }
}

function Main {
    Write-Host "Checking local drives for low disk space..."
    Write-Host "Minimum free space threshold: $minFreeGB GB or $minFreePct%"
    Write-Host "-------------------"

    # Check all local drives
    $drivesToCheck = Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
    
    if (-not $drivesToCheck) {
        Write-Host "No local drives found."
        return
    }

    $driveCount = 0
    $driveProblems = 0

    foreach ($drive in $drivesToCheck) {
        $driveId = $drive.DeviceID
        $sizeGB = [math]::Round($drive.Size / 1GB, 2)
        $freeGB = [math]::Round($drive.FreeSpace / 1GB, 2)
        $freePct = [math]::Round(($drive.FreeSpace / $drive.Size) * 100, 2)

        Write-Host "Drive $driveId : $freeGB GB free of $sizeGB GB ($freePct% free)"
        $driveCount++

        if ($freeGB -lt $minFreeGB -or $freePct -lt $minFreePct) {
            Write-Host "[ALERT] Low disk space on $driveId! Only $freeGB GB ($freePct%) free."
            $driveProblems++
            Analyze-DiskHealth -Drive $driveId -FreeGB $freeGB -FreePct $freePct
        }
    }

    Write-Host "-------------------"
    Write-Host "Disk space check complete. Checked $driveCount drive(s), $driveProblems with low space."
}

Main
