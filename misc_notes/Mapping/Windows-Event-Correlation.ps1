
# Load Windows Event Correlation Mapping
$MappingPath = Join-Path $PSScriptRoot "windows_event_correlation_mapping.json"
$EventMap = Get-Content $MappingPath -Raw | ConvertFrom-Json

# Example: lookup a specific Event ID
function Get-EventCorrelation {
    param(
        [Parameter(Mandatory=$true)]
        [int]$EventId
    )

    foreach ($domain in $EventMap.PSObject.Properties) {
        foreach ($entry in $domain.Value) {
            if ($entry.EventId -eq $EventId) {
                [PSCustomObject]@{
                    Domain      = $domain.Name
                    EventId     = $entry.EventId
                    Correlated  = ($entry.Correlated -join ',')
                    Message     = $entry.Message
                }
            }
        }
    }
}

# Example usage
Get-EventCorrelation -EventId 7031

# Example: basic triage logic
$RecentEventIds = @(7031, 2019)
if ($RecentEventIds -contains 7031 -and $RecentEventIds -contains 2019) {
    Write-Host "Root cause likely: Memory exhaustion"
}
