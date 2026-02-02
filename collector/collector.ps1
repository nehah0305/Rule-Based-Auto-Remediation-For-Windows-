<#
Simple collector: fetch latest events and POST to the Flask API.
Usage examples:
  - Send one event: .\collector.ps1 -MaxEvents 1 -LogName System
  - Tail events continuously: .\collector.ps1 -Tail
#>
param(
    [int]$MaxEvents = 5,
    [string]$LogName = 'System',
    [switch]$Tail,
    [string]$ApiUrl = 'http://localhost:5000/api/events'
)

function Send-EventToApi($ev) {
    $payload = [ordered]@{
        event_id = $ev.Id
        log_name = $ev.LogName
        source = $ev.ProviderName
        message = ($ev.Message -join " ")
        timestamp = $ev.TimeCreated.ToString('o')
    }
    try {
        Invoke-RestMethod -Method Post -Uri $ApiUrl -Body ($payload | ConvertTo-Json -Depth 5) -ContentType 'application/json'
    } catch {
        Write-Error "Failed to send event: $_"
    }
}

if ($Tail) {
    Write-Host "Tailing $LogName events and sending to $ApiUrl"
    Register-WmiEvent -Class Win32_NTLogEvent -SourceIdentifier 'AutoRemediator' | Out-Null
    while ($true) {
        $events = Get-WinEvent -MaxEvents 5 -LogName $LogName
        foreach ($e in $events) { Send-EventToApi $e }
        Start-Sleep -Seconds 5
    }
} else {
    $events = Get-WinEvent -MaxEvents $MaxEvents -LogName $LogName
    foreach ($e in $events) { Send-EventToApi $e }
}
