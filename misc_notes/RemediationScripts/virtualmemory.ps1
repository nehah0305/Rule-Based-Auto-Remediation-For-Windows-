# Clean Virtual Memory (set page file to clear at shutdown)
Write-Host "Configuring Windows to clear the page file at shutdown..."
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "ClearPageFileAtShutdown" -Value 1
 
# Clean up disk space: Remove temp files, empty Recycle Bin, run Disk Cleanup
 
# Remove temp files
Write-Host "Cleaning temporary files..."
Get-ChildItem "$env:TEMP" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
 
# Clean Windows Temp
Get-ChildItem "C:\Windows\Temp" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
 
# Empty Recycle Bin
Write-Host "Emptying Recycle Bin..."
$shell = New-Object -ComObject Shell.Application
$recycleBin = $shell.Namespace(0xA)
$recycleBin.Items() | %{ Remove-Item $_.Path -Recurse -Force -ErrorAction SilentlyContinue }
 
# Optionally, run Disk Cleanup silently for system files
Write-Host "Running Disk Cleanup..."
Start-Process cleanmgr.exe -ArgumentList "/sagerun:1" -Wait
 
Write-Host "Cleanup complete. For virtual memory cleaning to take effect, please restart your computer."