<#
.SYNOPSIS
    Load configuration from .env file

.DESCRIPTION
    This script loads configuration from the .env file in the project root.
    It returns a hashtable with all configuration values.

.EXAMPLE
    $config = & .\Load-Config.ps1
    $apiUrl = $config.API_BASE_URL
#>

function Load-EnvFile {
    param(
        [string]$EnvFilePath
    )
    
    $config = @{}
    
    if (-not (Test-Path $EnvFilePath)) {
        Write-Warning ".env file not found at: $EnvFilePath"
        Write-Warning "Using default configuration values"
        return $config
    }
    
    Get-Content $EnvFilePath | ForEach-Object {
        $line = $_.Trim()
        
        # Skip empty lines and comments
        if ($line -eq "" -or $line.StartsWith("#")) {
            return
        }
        
        # Parse KEY=VALUE
        if ($line -match "^([^=]+)=(.*)$") {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            
            # Remove quotes if present
            $value = $value -replace '^"(.*)"$', '$1'
            $value = $value -replace "^'(.*)'$", '$1'
            
            $config[$key] = $value
        }
    }
    
    return $config
}

# Get the project root directory (parent of collector directory)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$EnvFile = Join-Path $ProjectRoot ".env"

# Load configuration
$config = Load-EnvFile -EnvFilePath $EnvFile

# Set defaults if not specified
if (-not $config.ContainsKey("API_BASE_URL") -or [string]::IsNullOrWhiteSpace($config.API_BASE_URL)) {
    $config.API_BASE_URL = "http://localhost:5000"
}

if (-not $config.ContainsKey("POLL_INTERVAL_SECONDS") -or [string]::IsNullOrWhiteSpace($config.POLL_INTERVAL_SECONDS)) {
    $config.POLL_INTERVAL_SECONDS = "10"
}

if (-not $config.ContainsKey("MAX_EVENTS_PER_POLL") -or [string]::IsNullOrWhiteSpace($config.MAX_EVENTS_PER_POLL)) {
    $config.MAX_EVENTS_PER_POLL = "100"
}

if (-not $config.ContainsKey("HISTORICAL_DAYS") -or [string]::IsNullOrWhiteSpace($config.HISTORICAL_DAYS)) {
    $config.HISTORICAL_DAYS = "30"
}

if (-not $config.ContainsKey("MAX_HISTORICAL_EVENTS") -or [string]::IsNullOrWhiteSpace($config.MAX_HISTORICAL_EVENTS)) {
    $config.MAX_HISTORICAL_EVENTS = "10000"
}

if (-not $config.ContainsKey("LOG_NAMES") -or [string]::IsNullOrWhiteSpace($config.LOG_NAMES)) {
    $config.LOG_NAMES = "System,Application"
}

if (-not $config.ContainsKey("EVENT_IDS_TO_MONITOR") -or [string]::IsNullOrWhiteSpace($config.EVENT_IDS_TO_MONITOR)) {
    $config.EVENT_IDS_TO_MONITOR = ""
}

# Return the configuration hashtable
return $config

