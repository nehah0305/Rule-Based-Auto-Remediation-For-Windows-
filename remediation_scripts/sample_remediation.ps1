# Sample remediation script: creates a timestamped marker file indicating remediation ran.
param(
    [string]$MarkerDir = "$env:TEMP\AutoRemediation",
    [string]$Note = 'remediation ran'
)

if (-not (Test-Path $MarkerDir)) { New-Item -Path $MarkerDir -ItemType Directory -Force | Out-Null }
$fn = Join-Path $MarkerDir "remediation_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
"$((Get-Date).ToString('o')) - $Note" | Out-File -FilePath $fn -Encoding UTF8
Write-Output "Wrote marker file: $fn"
exit 0
