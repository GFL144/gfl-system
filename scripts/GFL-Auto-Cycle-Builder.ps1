<# ===================== GFL-Auto-Cycle-Builder.ps1 (v2, PS5-safe) =====================
Runs GFL-OneBig-TesterFixer on a cadence with self-heal:
- Counts errors in latest onebig_*.log via '|ERROR|Exception'
- If any errors  run -AutoFix -RunPipeline; else  test-only
- Appends a compact status row to Reports\cycle_status.csv
- Cleans Temp items older than 72h
====================================================================================== #>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root    = 'C:\GFL-System'
$Script  = Join-Path $Root 'Scripts\GFL-OneBig-TesterFixer.ps1'
$Reports = Join-Path $Root 'Reports'
$Logs    = Join-Path $Root 'Logs'
$Temp    = Join-Path $Root 'Temp'
New-Item -ItemType Directory -Force -Path $Reports,$Logs,$Temp | Out-Null

# 1) Latest log + error count
$latest = Get-ChildItem $Logs -Filter 'onebig_*.log' -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1

$Errs = 0
if ($latest) {
  $Errs = (Select-String -Path $latest.FullName -Pattern '|ERROR|Exception' | Measure-Object).Count
  Write-Host ("Latest log: {0}  errors = {1}" -f $latest.Name, $Errs)
} else {
  Write-Host "No previous logs found."
}

# 2) Decide action
$Action = if ($Errs -gt 0) { 'AutoFix-Run' } else { 'Test-Only' }

# 3) Execute selected mode
try {
  if ($Action -eq 'AutoFix-Run') {
    & $Script -AutoFix -RunPipeline -Hours 48 -UseSevenZip -SplitMB 600 -PruneStage
  } else {
    & $Script
  }
} catch {
  Write-Host ("Runner error: {0}" -f $_.Exception.Message) -ForegroundColor Red
}

# 4) Append health summary
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$latestPath = if ($latest) { $latest.FullName } else { $null }
$summary = [pscustomobject]@{
  Timestamp   = $stamp
  Action      = $Action
  ErrorsFound = $Errs
  LatestLog   = $latestPath
}
$csv = Join-Path $Reports 'cycle_status.csv'
if (Test-Path $csv) {
  $summary | Export-Csv $csv -Append -NoTypeInformation
} else {
  $summary | Export-Csv $csv -NoTypeInformation
}

# 5) Clean staging & temp older than 72h
Get-ChildItem $Temp -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-72) } |
  Remove-Item -Recurse -Force

Write-Host "Cycle complete. Logged  $csv" -ForegroundColor Green








