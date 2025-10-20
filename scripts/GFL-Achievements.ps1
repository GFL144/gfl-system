<# GFL-Achievements.ps1
   Calculates badges & health score from metrics.json(l) and auto-heal logs
   Outputs: Reports\achievements.json
#>
$Root    = "C:\GFL-System"
$Reports = Join-Path $Root "Reports"
$Logs    = Join-Path $Reports "logs"
$Hist    = Join-Path $Reports "metrics.jsonl"
$Snap    = Join-Path $Reports "metrics.json"
$Out     = Join-Path $Reports "achievements.json"

function Safe-ReadLines($p,$tail=2000){ if(Test-Path $p){ Get-Content $p -Tail $tail } else { @() } }
function Safe-ReadSnap($p){ if(Test-Path $p){ try{ Get-Content $p -Raw | ConvertFrom-Json }catch{ $null } } }

$lines = Safe-ReadLines $Hist 3000 | ForEach-Object { try{ $_ | ConvertFrom-Json }catch{} } | Where-Object { $_ }
$snap  = Safe-ReadSnap $Snap

# aggregations
$uptime = $snap?.uptimeSec
$cpuAvg = if($lines){ [math]::Round((($lines | Select-Object -ExpandProperty cpuPct) | Measure-Object -Average).Average,1) } else { $snap?.cpuPct }
$downGood = ($lines | Where-Object { $_.speed.downMbps -ge 50 }).Count
$autoHealFixes = 0
Get-ChildItem (Join-Path $Logs 'autoheal-*.log') -ErrorAction SilentlyContinue | ForEach-Object {
  $txt = Get-Content $_.FullName -Raw
  if($txt -match 'Fixes applied:\s*(\d+)'){ $autoHealFixes += [int]$matches[1] }
}

$badges = New-Object System.Collections.ArrayList
function AddBadge($id,$label){ [void]$badges.Add([pscustomobject]@{ id=$id; label=$label }) }

if($uptime -ge 86400){ AddBadge "uptime24h" "Uptime > 24h" }
if($uptime -ge 604800){ AddBadge "uptime7d"  "Uptime > 7 days" }
if(($cpuAvg -as [double]) -le 50){ AddBadge "coolCPU" "CPU avg  50%" }
if($downGood -ge 10){ AddBadge "fastNet" "Good download 10+ samples" }
if($autoHealFixes -ge 5){ AddBadge "selfHealing" "Auto-Heal 5+ fixes" }

# health score 0..100
$score = 100
if($cpuAvg -gt 80){ $score -= 15 }
if($uptime -lt 3600){ $score -= 10 }
if($downGood -lt 3){ $score -= 10 }
if($autoHealFixes -eq 0){ $score -= 5 }
if($score -lt 0){ $score = 0 }

$payload = [pscustomobject]@{
  ts = (Get-Date).ToString("o")
  health = $score
  badges = $badges
  facts  = [pscustomobject]@{
    uptimeSec = $uptime
    cpuAvgPct = $cpuAvg
    goodDownSamples = $downGood
    autoHealFixes = $autoHealFixes
  }
}

($payload | ConvertTo-Json -Depth 8) | Out-File $Out -Encoding utf8
