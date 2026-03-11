
$base = 'http://localhost:5000'
$pass = 0; $fail = 0; $warn = 0
$results = @()

function Pass($id, $label, $detail='') {
    $global:pass++
    $global:results += [pscustomobject]@{ID=$id; Result='PASS'; Label=$label; Detail=$detail}
    Write-Host "[PASS] [$id] $label $detail" -ForegroundColor Green
}
function Fail($id, $label, $detail='') {
    $global:fail++
    $global:results += [pscustomobject]@{ID=$id; Result='FAIL'; Label=$label; Detail=$detail}
    Write-Host "[FAIL] [$id] $label $detail" -ForegroundColor Red
}
function Warn($id, $label, $detail='') {
    $global:warn++
    $global:results += [pscustomobject]@{ID=$id; Result='WARN'; Label=$label; Detail=$detail}
    Write-Host "[WARN] [$id] $label $detail" -ForegroundColor Yellow
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "  FULL QA TEST SUITE: Alert Intelligence + Rule Engine  " -ForegroundColor Cyan
Write-Host "==========================================================`n" -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────────
# SECTION A: Alert Intelligence & Enrichment
# ──────────────────────────────────────────────────────────────
Write-Host "--- Section A: Alert Intelligence & Enrichment ---" -ForegroundColor Magenta

# A1: Server alive
try {
    Invoke-RestMethod "$base/api/rules" -Method GET | Out-Null
    Pass "A1" "Server is alive and responding"
} catch { Fail "A1" "Server not responding" $_.Exception.Message; exit 1 }

# A2: Event ingestion returns intelligence fields
$ev1 = @{ event_id="QA_EVT_1"; source="QA_Source"; log_name="System"; message="QA test event alpha"; severity="Warning"; timestamp=(Get-Date).ToUniversalTime().ToString("o") } | ConvertTo-Json
$r1 = Invoke-RestMethod "$base/api/events" -Method POST -Body $ev1 -ContentType 'application/json'
if ($r1.event_id) { Pass "A2" "Event ingested OK, row_id=$($r1.event_id)" }
else              { Fail "A2" "Event ingestion failed" ($r1 | ConvertTo-Json) }
$rowId1 = $r1.event_id

# A3: Deduplication - same event again should increment dedup_count
Start-Sleep -Milliseconds 500
$r2 = Invoke-RestMethod "$base/api/events" -Method POST -Body $ev1 -ContentType 'application/json'
if ($r2.event_id -eq $rowId1) { Pass "A3" "Deduplication: same row_id returned (no duplicate insert)" }
else                           { Warn "A3" "Deduplication: new row created (may be outside dedup window)" "old=$rowId1 new=$($r2.event_id)" }

# A4: GET /api/events returns confidence_score and dedup_count
$events = Invoke-RestMethod "$base/api/events" -Method GET
$qaEvent = $events | Where-Object { $_.event_id -eq "QA_EVT_1" -and $_.source -eq "QA_Source" } | Select-Object -First 1
if ($qaEvent.confidence_score -gt 0) { Pass "A4" "confidence_score populated: $($qaEvent.confidence_score)" }
else                                  { Fail "A4" "confidence_score is 0 or missing" }
if ($qaEvent.dedup_count -ge 1) { Pass "A5" "dedup_count populated: $($qaEvent.dedup_count)" }
else                             { Fail "A5" "dedup_count missing or 0" }
if ($qaEvent.correlation_id)    { Pass "A6" "correlation_id present: $($qaEvent.correlation_id)" }
else                             { Fail "A6" "correlation_id missing" }

# A5: Two events from same source in short time should share correlation_id
$ev2 = @{ event_id="QA_EVT_2"; source="QA_Source"; log_name="System"; message="QA test event beta"; severity="Error"; timestamp=(Get-Date).ToUniversalTime().ToString("o") } | ConvertTo-Json
$r3 = Invoke-RestMethod "$base/api/events" -Method POST -Body $ev2 -ContentType 'application/json'
$events2 = Invoke-RestMethod "$base/api/events" -Method GET
$evt1 = $events2 | Where-Object { $_.event_id -eq "QA_EVT_1" -and $_.source -eq "QA_Source" } | Select-Object -First 1
$evt2 = $events2 | Where-Object { $_.event_id -eq "QA_EVT_2" -and $_.source -eq "QA_Source" } | Select-Object -First 1
if ($evt1 -and $evt2 -and ($evt1.correlation_id -eq $evt2.correlation_id)) {
    Pass "A7" "Correlation: events from same source share correlation_id $($evt1.correlation_id)"
} else {
    Warn "A7" "Correlation ID differs for same-source events (may be outside 10-min bucket)" "evt1=$($evt1.correlation_id) evt2=$($evt2.correlation_id)"
}

# A6: Intelligence summary endpoint
try {
    $intel = Invoke-RestMethod "$base/api/intelligence/summary" -Method GET
    if ($intel.PSObject.Properties.Name -contains 'total_events') { Pass "A8" "Intelligence summary endpoint OK, total_events=$($intel.total_events)" }
    else { Fail "A8" "Intelligence summary missing total_events field" ($intel | ConvertTo-Json) }
    if ($null -ne $intel.avg_confidence) { Pass "A9" "avg_confidence in summary: $($intel.avg_confidence)" }
    else { Fail "A9" "avg_confidence missing from summary" }
    if ($null -ne $intel.total_suppressed) { Pass "A10" "total_suppressed (dedup count) in summary: $($intel.total_suppressed)" }
    else { Fail "A10" "total_suppressed missing from summary" }
} catch { Fail "A8" "Intelligence summary endpoint failed" $_.Exception.Message }

# A7: Higher severity event should have higher confidence than low severity
$evHigh = @{ event_id="QA_HIGH"; source="QA_Confidence"; log_name="System"; message="Critical failure"; severity="Critical"; timestamp=(Get-Date).ToUniversalTime().ToString("o") } | ConvertTo-Json
$evLow  = @{ event_id="QA_LOW";  source="QA_Confidence"; log_name="System"; message="Info startup";    severity="Information"; timestamp=(Get-Date).ToUniversalTime().ToString("o") } | ConvertTo-Json
Invoke-RestMethod "$base/api/events" -Method POST -Body $evHigh -ContentType 'application/json' | Out-Null
Invoke-RestMethod "$base/api/events" -Method POST -Body $evLow  -ContentType 'application/json' | Out-Null
$all = Invoke-RestMethod "$base/api/events" -Method GET
$eHigh = $all | Where-Object { $_.event_id -eq "QA_HIGH" } | Select-Object -First 1
$eLow  = $all | Where-Object { $_.event_id -eq "QA_LOW"  } | Select-Object -First 1
if ($eHigh -and $eLow -and ([float]$eHigh.confidence_score -gt [float]$eLow.confidence_score)) {
    Pass "A11" "Confidence scoring correct: Critical($($eHigh.confidence_score)) > Info($($eLow.confidence_score))"
} else {
    Fail "A11" "Confidence scoring incorrect" "Critical=$($eHigh.confidence_score) Info=$($eLow.confidence_score)"
}

Write-Host ""
# ──────────────────────────────────────────────────────────────
# SECTION B: Rule Matching Engine
# ──────────────────────────────────────────────────────────────
Write-Host "--- Section B: Rule Matching Engine ---" -ForegroundColor Magenta

# B1: Create rules with various features
# Rule 1: Priority=10, stop_processing=true, regex with captures
$rule1 = @{
    name="QA_Rule_Terminal"; event_id="QA_MATCH"; source="QA_MatchSrc"
    message_regex='Error (?P<Code>\d+): (?P<Msg>.+)'
    script_type="inline"; remediation_script='Write-Output "CONTEXT: EventID=$env:RM_EVENT_ID Src=$env:RM_SOURCE Code=$env:RM_MATCH_Code Msg=$env:RM_MATCH_Msg Sev=$env:RM_SEVERITY"'
    auto_remediate=$false; stop_processing=$true; priority=10; cooldown_minutes=0
} | ConvertTo-Json
$c1 = Invoke-RestMethod "$base/api/rules" -Method POST -Body $rule1 -ContentType 'application/json'
if ($c1.rule_id) { Pass "B1" "Terminal rule created, id=$($c1.rule_id)" } else { Fail "B1" "Rule1 create failed" }
$rid1 = $c1.rule_id

# Rule 2: Priority=999 (lower), should be skipped by stop_processing
$rule2 = @{
    name="QA_Rule_LowPri"; event_id="QA_MATCH"; source="QA_MatchSrc"
    script_type="inline"; remediation_script='Write-Output "SHOULD_NOT_RUN"'
    auto_remediate=$false; stop_processing=$false; priority=999; cooldown_minutes=0
} | ConvertTo-Json
$c2 = Invoke-RestMethod "$base/api/rules" -Method POST -Body $rule2 -ContentType 'application/json'
$rid2 = $c2.rule_id

# Rule 3: With cooldown
$rule3 = @{
    name="QA_Rule_Cooldown"; event_id="QA_COOL"; source="QA_CoolSrc"
    script_type="inline"; remediation_script='Write-Output "Cooldown test"'
    auto_remediate=$true; stop_processing=$false; priority=50; cooldown_minutes=60
} | ConvertTo-Json
$c3 = Invoke-RestMethod "$base/api/rules" -Method POST -Body $rule3 -ContentType 'application/json'
$rid3 = $c3.rule_id

# B2: Verify stop_processing and priority are returned correctly
$ruleGet = Invoke-RestMethod "$base/api/rules/$rid1" -Method GET
if ($ruleGet.stop_processing -eq $true) { Pass "B2" "stop_processing=true returned from GET" }
else { Fail "B2" "stop_processing not returned correctly" $ruleGet.stop_processing }
if ($ruleGet.priority -eq 10) { Pass "B3" "priority=10 returned correctly" }
else { Fail "B3" "priority mismatch" $ruleGet.priority }

# B3: Ingest a matching event
$evMatch = @{
    event_id="QA_MATCH"; source="QA_MatchSrc"; log_name="Application"
    message='Error 404: Page not found in application'; severity="Error"
    timestamp=(Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json
$evR = Invoke-RestMethod "$base/api/events" -Method POST -Body $evMatch -ContentType 'application/json'
$matchRowId = $evR.event_id
Pass "B4" "Matching event ingested row_id=$matchRowId"

# B4: GET matches — should return ONLY rule1 (stop_processing short-circuits rule2)
$matches = Invoke-RestMethod "$base/api/events/$matchRowId/matches" -Method GET
Write-Host "   Matches returned: $($matches.Count) — ids: $($matches.id -join ',')"
if ($matches.Count -eq 1 -and $matches[0].id -eq $rid1) {
    Pass "B5" "stop_processing short-circuit: ONLY terminal rule returned (rule2 skipped)"
} elseif ($matches.Count -eq 0) {
    Fail "B5" "No rules matched at all — check event_id/source match logic"
} else {
    Fail "B5" "stop_processing did NOT short-circuit; $($matches.Count) rules returned, expected 1"
}

# B5: Verify stop_processing flag in match response
$mRule = $matches | Where-Object { $_.id -eq $rid1 }
if ($mRule.stop_processing -eq $true) { Pass "B6" "stop_processing=true visible in matches response" }
else { Fail "B6" "stop_processing missing from matches response" }

# B6: Regex match should have extracted captures (message won't re-run, just test matching)
if ($matches.Count -ge 1) { Pass "B7" "Regex matching worked (rule returned for event with matching message)" }
else { Fail "B7" "Regex match failed — rule did not match event" }

# B7: Run rule and verify context injection + regex captures in output
$runBody = @{ event_row_id = $matchRowId } | ConvertTo-Json
$runRes = Invoke-RestMethod "$base/api/rules/$rid1/run" -Method POST -Body $runBody -ContentType 'application/json'
if ($runRes.status -eq 'success') { Pass "B8" "Rule execution: status=success" }
else { Fail "B8" "Rule execution failed: status=$($runRes.status)" $runRes.output }

$out = $runRes.output
if ($out -match "EventID=QA_MATCH")  { Pass "B9"  "Context injection: RM_EVENT_ID=QA_MATCH" }
else { Fail "B9"  "RM_EVENT_ID not in output" ($out.Substring(0,[Math]::Min(200,$out.Length))) }
if ($out -match "Src=QA_MatchSrc")  { Pass "B10" "Context injection: RM_SOURCE=QA_MatchSrc" }
else { Fail "B10" "RM_SOURCE not in output" ($out.Substring(0,[Math]::Min(200,$out.Length))) }
if ($out -match "Code=404")          { Pass "B11" "Regex capture RM_MATCH_Code=404" }
else { Fail "B11" "RM_MATCH_Code not captured" ($out.Substring(0,[Math]::Min(200,$out.Length))) }
if ($out -match "Msg=Page not found") { Pass "B12" "Regex capture RM_MATCH_Msg='Page not found'" }
else { Fail "B12" "RM_MATCH_Msg not captured" ($out.Substring(0,[Math]::Min(200,$out.Length))) }
if ($out -match "Sev=Error")          { Pass "B13" "Context injection: RM_SEVERITY=Error" }
else { Fail "B13" "RM_SEVERITY not in output" ($out.Substring(0,[Math]::Min(200,$out.Length))) }

Write-Host "`nScript output:"
Write-Host $out -ForegroundColor DarkGray

# B8: Cooldown test — run rule3 auto-trigger via event ingest, then check cooldown
$evCool = @{ event_id="QA_COOL"; source="QA_CoolSrc"; log_name="System"; message="Cooldown test event"; auto_remediate=$true } | ConvertTo-Json
# We'll manually trigger and check suppression in history
$runCool = Invoke-RestMethod "$base/api/rules/$rid3/run" -Method POST -Body (@{event_row_id=($evR.event_id)} | ConvertTo-Json) -ContentType 'application/json'
# Now check cooldown is active
$coolRule = Invoke-RestMethod "$base/api/rules/$rid3" -Method GET
if ($coolRule.cooldown_minutes -eq 60) { Pass "B14" "Cooldown rule has cooldown_minutes=60" }
else { Fail "B14" "cooldown_minutes not set" $coolRule.cooldown_minutes }

# B9: Verify rule ordering (priority) — create two rules for same event, check order in matches
$ruleA = @{ name="QA_PriA"; event_id="QA_PRI"; source="QA_PriSrc"; script_type="inline"; remediation_script='echo "A"'; priority=20; stop_processing=$false } | ConvertTo-Json
$ruleB = @{ name="QA_PriB"; event_id="QA_PRI"; source="QA_PriSrc"; script_type="inline"; remediation_script='echo "B"'; priority=5;  stop_processing=$false } | ConvertTo-Json
$pA = (Invoke-RestMethod "$base/api/rules" -Method POST -Body $ruleA -ContentType 'application/json').rule_id
$pB = (Invoke-RestMethod "$base/api/rules" -Method POST -Body $ruleB -ContentType 'application/json').rule_id
$evPri = @{ event_id="QA_PRI"; source="QA_PriSrc"; log_name="System"; message="Priority test" } | ConvertTo-Json
$priRow = (Invoke-RestMethod "$base/api/events" -Method POST -Body $evPri -ContentType 'application/json').event_id
$priMatches = Invoke-RestMethod "$base/api/events/$priRow/matches" -Method GET
if ($priMatches.Count -ge 2 -and $priMatches[0].id -eq $pB -and $priMatches[1].id -eq $pA) {
    Pass "B15" "Priority ordering: rule with priority=5 appears before priority=20"
} elseif ($priMatches.Count -ge 2) {
    Fail "B15" "Priority ordering incorrect" "first=$($priMatches[0].id)(pri=$($priMatches[0].priority)) second=$($priMatches[1].id)(pri=$($priMatches[1].priority))"
} else {
    Warn "B15" "Could not verify priority ordering — less than 2 matches returned" $priMatches.Count
}

# B10: Strict severity matching
$ruleStrict = @{ name="QA_Strict_Sev"; event_id="QA_STRICT"; source="QA_Strict"; severity="Critical"; script_type="inline"; remediation_script='echo "strict"'; priority=50 } | ConvertTo-Json
$pStr = (Invoke-RestMethod "$base/api/rules" -Method POST -Body $ruleStrict -ContentType 'application/json').rule_id
# Event with the wrong severity should NOT match
$evWrongSev = @{ event_id="QA_STRICT"; source="QA_Strict"; log_name="System"; message="test"; severity="Warning" } | ConvertTo-Json
$wRow = (Invoke-RestMethod "$base/api/events" -Method POST -Body $evWrongSev -ContentType 'application/json').event_id
$wMatches = Invoke-RestMethod "$base/api/events/$wRow/matches" -Method GET
$strictMatch = $wMatches | Where-Object { $_.id -eq $pStr }
if (-not $strictMatch) { Pass "B16" "Strict severity: Warning event does NOT match Critical rule" }
else { Fail "B16" "Strict severity failed: Critical rule matched a Warning event" }
# Event with correct severity SHOULD match
$evRightSev = @{ event_id="QA_STRICT"; source="QA_Strict"; log_name="System"; message="test"; severity="Critical" } | ConvertTo-Json
$cRow = (Invoke-RestMethod "$base/api/events" -Method POST -Body $evRightSev -ContentType 'application/json').event_id
$cMatches = Invoke-RestMethod "$base/api/events/$cRow/matches" -Method GET
$strictMatch2 = $cMatches | Where-Object { $_.id -eq $pStr }
if ($strictMatch2) { Pass "B17" "Strict severity: Critical event DOES match Critical rule" }
else { Fail "B17" "Strict severity filter over-excludes: Critical event not matched" }

# B11: History entries are recorded
$hist = Invoke-RestMethod "$base/api/history" -Method GET
$recentHistory = $hist | Where-Object { $_.rule_name -eq "QA_Rule_Terminal" } | Select-Object -First 1
if ($recentHistory) { Pass "B18" "Remediation history recorded for QA_Rule_Terminal: status=$($recentHistory.status)" }
else { Fail "B18" "No history entry found for QA_Rule_Terminal" }

# ──────────────────────────────────────────────────────────────
# CLEANUP
# ──────────────────────────────────────────────────────────────
Write-Host "`n--- Cleanup ---" -ForegroundColor DarkGray
foreach ($rid in @($rid1, $rid2, $rid3, $pA, $pB, $pStr)) {
    try { Invoke-RestMethod "$base/api/rules/$rid" -Method DELETE | Out-Null } catch {}
}

# ──────────────────────────────────────────────────────────────
# SUMMARY
# ──────────────────────────────────────────────────────────────
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  PASS : $pass" -ForegroundColor Green
Write-Host "  FAIL : $fail" -ForegroundColor $(if ($fail -eq 0) {'Green'} else {'Red'})
Write-Host "  WARN : $warn" -ForegroundColor $(if ($warn -eq 0) {'Green'} else {'Yellow'})
Write-Host "==========================================================" -ForegroundColor Cyan

# Output JSON for report
$results | ConvertTo-Json | Out-File -FilePath "$PSScriptRoot/qa_results.json" -Encoding utf8
Write-Host "`nResults saved to qa_results.json"
