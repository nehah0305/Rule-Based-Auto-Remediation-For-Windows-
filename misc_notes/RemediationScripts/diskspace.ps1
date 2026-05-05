# Check all local drives for low disk space and report warnings

# Set thresholds
$minFreeGB = 5      # Minimum free space in GB
$minFreePct = 10    # Minimum free space in percent

Write-Host "Checking local drives for low disk space..."

Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $drive = $_.DeviceID
    $sizeGB = [math]::Round($_.Size / 1GB, 2)
    $freeGB = [math]::Round($_.FreeSpace / 1GB, 2)
    $freePct = [math]::Round(($_.FreeSpace / $_.Size) * 100, 2)

    Write-Host "Drive $drive: $freeGB GB free of $sizeGB GB ($freePct% free)"

    if ($freeGB -lt $minFreeGB -or $freePct -lt $minFreePct) {
        Write-Warning "Low disk space on $drive! Only $freeGB GB ($freePct%) free."
    }
}