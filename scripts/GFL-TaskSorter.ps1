param([string]$QueueIn,[string]$PlanOut,[string]$Policy)

# Resolve all paths relative to this script
$Scripts = $PSScriptRoot
$GRoot   = Split-Path -Parent $Scripts
$Reports = Join-Path $GRoot 'Reports'
$Queues  = Join-Path $Reports 'queues'
$Plans   = Join-Path $Reports 'plans'
$Config  = Join-Path $GRoot 'Config'
New-Item -ItemType Directory -Force -Path $Reports,$Queues,$Plans | Out-Null
. "$PSScriptRoot\GFL-Common.ps1"

$p    = JLoad $Policy
$q    = JLoad $QueueIn @()
$plan = @()

foreach($t in $q){
  $risk = $t.risk; if (-not $risk) { $risk = 'low' }
  $w = $p.priority_weights[$risk]; if (-not $w) { $w = 1 }
  $score = [int]$w + (Get-Random -Min 0 -Max 3)

  $t | Add-Member -NotePropertyName score -NotePropertyValue $score -Force

  if     ($score -ge 10) { $priority = 'high' }
  elseif ($score -ge 5)  { $priority = 'medium' }
  else                   { $priority = 'low' }

  $t | Add-Member -NotePropertyName priority -NotePropertyValue $priority -Force
  $plan += $t
}

$plan = @($plan) | Sort-Object -Property score -Descending
if (-not $plan) { $plan = @() }
JSave $plan $PlanOut
ALog ("Planned {0}" -f $plan.Count) 'SORT'



