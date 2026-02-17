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
        severity = if ($ev.LevelDisplayName) { $ev.LevelDisplayName } else { switch ($ev.Level) { 1 { 'Critical' } 2 { 'Error' } 3 { 'Warning' } 4 { 'Information' } Default { 'Info' } } }
        category = $ev.TaskDisplayName
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
    # Attempt to fetch last-processed timestamp from API and only load newer events
    try {
        $base = $ApiUrl -replace '/api/events$',''
        $lp = Invoke-RestMethod -Method Get -Uri "$base/api/last-processed" -ErrorAction Stop
        if ($lp -and $lp.last_timestamp) {
            $start = [DateTime]::Parse($lp.last_timestamp)
            $events = Get-WinEvent -FilterHashtable @{LogName=$LogName; StartTime=$start} -MaxEvents $MaxEvents
        } else {
            $events = Get-WinEvent -MaxEvents $MaxEvents -LogName $LogName
        }
    } catch {
        # Fallback to simple fetch
        $events = Get-WinEvent -MaxEvents $MaxEvents -LogName $LogName
    }
    foreach ($e in $events) { Send-EventToApi $e }
}
