$ErrorActionPreference = 'Stop'
$base = 'http://localhost:5000'
$pass = 0; $fail = 0

function Ok($label, $val) {
    Write-Host "[PASS] $label : $val" -ForegroundColor Green
    $global:pass++
}
function Fail($label, $val) {
    Write-Host "[FAIL] $label : $val" -ForegroundColor Red
    $global:fail++
}

Write-Host "`n====  Rule Matching Engine — Full Verification  ====" -ForegroundColor Cyan

# ─── 1. Server health ────────────────────────────────────────────────────────
try {
    $rules = Invoke-RestMethod "$base/api/rules" -Method GET
    Ok "Server alive, rules count" $rules.Count
} catch { Fail "Server health" $_.Exception.Message; exit 1 }

# ─── 2. Create a short-circuit (stop_processing) rule with regex captures ───
Write-Host "`n--- Creating test rule with stop_processing + regex captures ---" -ForegroundColor Yellow
$ruleBody = @{
    name              = "__EngineTestRule__"
    event_id          = "88881"
    source            = "EngineTestSrc"
    message_regex     = "Service (?P<ServiceName>\w+) entered (?P<State>\w+) state"
    script_type       = "inline"
    remediation_script = @'
Write-Output "=== Context Injection Test ==="
Write-Output "EventID  : $env:RM_EVENT_ID"
Write-Output "Source   : $env:RM_SOURCE"
Write-Output "Severity : $env:RM_SEVERITY"
Write-Output "Service  : $env:RM_MATCH_ServiceName"
Write-Output "State    : $env:RM_MATCH_State"
Write-Output "=== End Test ==="
'@
    auto_remediate    = $false
    stop_processing   = $true
    priority          = 5
    cooldown_minutes  = 0
} | ConvertTo-Json
$created = Invoke-RestMethod "$base/api/rules" -Method POST -Body $ruleBody -ContentType 'application/json'
if ($created.rule_id) { Ok "Rule created, id" $created.rule_id } else { Fail "Rule create" "no id returned" }
$ruleId = $created.rule_id

# ─── 3. Fetch rule back and verify stop_processing field returned ─────────────
$rule = Invoke-RestMethod "$base/api/rules/$ruleId" -Method GET
if ($rule.stop_processing -eq $true) { Ok "stop_processing returned as true" $rule.stop_processing } else { Fail "stop_processing field" $rule.stop_processing }
if ($rule.priority -eq 5) { Ok "priority field" $rule.priority } else { Fail "priority field" $rule.priority }
if ($rule.script_type -eq "inline") { Ok "script_type field" $rule.script_type } else { Fail "script_type" $rule.script_type }

# ─── 4. Ingest a test event ──────────────────────────────────────────────────
Write-Host "`n--- Ingesting test event ---" -ForegroundColor Yellow
$evBody = @{
    event_id  = "88881"
    source    = "EngineTestSrc"
    log_name  = "System"
    message   = "Service MyWebApp entered running state at startup"
    severity  = "Information"
    timestamp = (Get-Date -Format o)
} | ConvertTo-Json
$evResult = Invoke-RestMethod "$base/api/events" -Method POST -Body $evBody -ContentType 'application/json'
$eventRowId = $evResult.event_id
if ($eventRowId) { Ok "Event ingested, row_id" $eventRowId } else { Fail "Event ingest" "no row id" }

# ─── 5. Check matches (rule should appear for this event) ─────────────────────
Write-Host "`n--- Checking rule matches ---" -ForegroundColor Yellow
$matches = Invoke-RestMethod "$base/api/events/$eventRowId/matches" -Method GET
$match = $matches | Where-Object { $_.id -eq $ruleId }
if ($match) { Ok "Rule matches event" $match.name } else { Fail "Rule matching" "no match returned for rule $ruleId" }
if ($match.stop_processing -eq $true) { Ok "stop_processing in match response" $match.stop_processing } else { Fail "stop_processing in matches" $match.stop_processing }

# ─── 6. Run the rule — verify context vars in output ────────────────────────
Write-Host "`n--- Run rule and verify context variable injection ---" -ForegroundColor Yellow
$runBody = @{ event_row_id = $eventRowId } | ConvertTo-Json
$runResult = Invoke-RestMethod "$base/api/rules/$ruleId/run" -Method POST -Body $runBody -ContentType 'application/json'
if ($runResult.status -eq "success") { Ok "Rule execution status" $runResult.status } else { Fail "Rule execution" "status=$($runResult.status) output=$($runResult.output)" }

$output = $runResult.output
if ($output -match "EventID\s*:\s*88881") { Ok "RM_EVENT_ID injected" "88881" } else { Fail "RM_EVENT_ID not found" $output.Substring(0, [Math]::Min(200,$output.Length)) }
if ($output -match "Source\s*:\s*EngineTestSrc") { Ok "RM_SOURCE injected" "EngineTestSrc" } else { Fail "RM_SOURCE not found" $output.Substring(0, [Math]::Min(200,$output.Length)) }
if ($output -match "Service\s*:\s*MyWebApp") { Ok "RM_MATCH_ServiceName captured" "MyWebApp" } else { Fail "RM_MATCH_ServiceName not found" $output.Substring(0, [Math]::Min(200,$output.Length)) }
if ($output -match "State\s*:\s*running") { Ok "RM_MATCH_State captured" "running" } else { Fail "RM_MATCH_State not found" $output.Substring(0, [Math]::Min(200,$output.Length)) }

# Print full output for review
Write-Host "`n--- Script Output ---" -ForegroundColor Magenta
Write-Host $output

# ─── 7. Create a second (lower priority) rule to test stop_processing ─────────
Write-Host "`n--- Testing stop_processing short-circuit ---" -ForegroundColor Yellow
$rule2Body = @{
    name              = "__EngineTestRule2__"
    event_id          = "88881"
    source            = "EngineTestSrc"
    script_type       = "inline"
    remediation_script = 'Write-Output "SHOULD NOT RUN - stop_processing bypassed"'
    auto_remediate    = $false
    stop_processing   = $false
    priority          = 999   # much lower priority than rule 1
    cooldown_minutes  = 0
} | ConvertTo-Json
$created2 = Invoke-RestMethod "$base/api/rules" -Method POST -Body $rule2Body -ContentType 'application/json'
$rule2Id = $created2.rule_id
Ok "Second rule created" $rule2Id

$matches2 = Invoke-RestMethod "$base/api/events/$eventRowId/matches" -Method GET
$ids = $matches2 | Select-Object -ExpandProperty id
# Rule 1 has stop_processing=true and priority=5, Rule 2 has priority=999
# Match engine should return ONLY rule 1 (short-circuited after it)
if ($ids -contains $ruleId -and $ids -notcontains $rule2Id) {
    Ok "stop_processing short-circuit: rule2 SKIPPED" "Only rule id=$ruleId returned"
} elseif ($ids -contains $rule2Id) {
    Fail "stop_processing did NOT short-circuit" "Both rules returned: $($ids -join ', ')"
} else {
    Fail "Unexpected matches result" "ids=$($ids -join ', ')"
}

# ─── 8. Cleanup ──────────────────────────────────────────────────────────────
Write-Host "`n--- Cleanup ---" -ForegroundColor Yellow
Invoke-RestMethod "$base/api/rules/$ruleId"  -Method DELETE | Out-Null
Invoke-RestMethod "$base/api/rules/$rule2Id" -Method DELETE | Out-Null
Ok "Test rules cleaned up" ""

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "  PASSED: $pass   FAILED: $fail" -ForegroundColor $(if ($fail -eq 0) {'Green'} else {'Red'})
Write-Host "======================================`n" -ForegroundColor Cyan
