# Remediation Script for Event ID 1014: DNS name resolution timeout
# Conservative remediation: flush caches, register DNS, and verify the DNS client state.

param()

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$SIMULATION_MODE = ($env:RM_SIMULATION_MODE -eq '1')
$LOG_NAME = 'Application'
$SOURCE = 'AutoRemediationDemo'
$RESOLVE_ID = 7036
$message = $env:RM_MESSAGE
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$LOG_FILE = 'C:\Temp\Event1014_Remediation.log'

if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LOG_FILE -Value "[$timestamp] $Message" -Force
}

function Get-DnsNameFromMessage {
    param([string]$Message)

    if ($Message -match "'([^']+)'") { return $matches[1] }
    if ($Message -match '([A-Za-z0-9.-]+\.[A-Za-z]{2,})') { return $matches[1] }
    return $null
}

function Write-ResolutionEvent {
    param([int]$EventId, [string]$Message)
    try {
        Write-EventLog -LogName $LOG_NAME -Source $SOURCE -EventId $EventId -EntryType 'Information' -Message $Message -ErrorAction Stop
    }
    catch {
        Write-Log ("Error writing event: {0}" -f $_.Exception.Message)
    }
}

Write-Log 'Event 1014 received: DNS name resolution timeout.'
Write-Log ("Message: {0}" -f $message)

$dnsName = Get-DnsNameFromMessage -Message $message
$action = 'none'

if ($SIMULATION_MODE) {
    Write-Log '[SIMULATION] Would flush DNS cache, renew registration, and check resolver configuration.'
    $action = 'simulated-refresh'
}
else {
    try {
        ipconfig /flushdns | Out-Null
        ipconfig /registerdns | Out-Null
        Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Log ("DNS server config for interface {0}: {1}" -f $_.InterfaceAlias, ($_.ServerAddresses -join ', '))
        }
        $action = 'refreshed-dns'
    }
    catch {
        Write-Log ("DNS remediation failed: {0}" -f $_.Exception.Message)
        $action = 'partial'
    }
}

$status = if ($action -in @('simulated-refresh','refreshed-dns')) { 'SUCCESS' } else { 'PARTIAL' }
$resolutionMessage = "Auto-remediation $status for Event 1014. DnsName=$dnsName Action=$action Time=$timestamp"
if ($SIMULATION_MODE) { $resolutionMessage = "[SIMULATION] $resolutionMessage" }
Write-ResolutionEvent -EventId $RESOLVE_ID -Message $resolutionMessage
Write-Log ("Remediation complete with action: {0}" -f $action)
exit 0
