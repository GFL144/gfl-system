param([string]$PlanIn,[string]$OutDir,[int]$MaxImmediate=1)

# Resolve all paths relative to this script
$Scripts = $PSScriptRoot
$GRoot   = Split-Path -Parent $Scripts
$Reports = Join-Path $GRoot 'Reports'
$Queues  = Join-Path $Reports 'queues'
$Plans   = Join-Path $Reports 'plans'
$Config  = Join-Path $GRoot 'Config'
New-Item -ItemType Directory -Force -Path $Reports,$Queues,$Plans | Out-Null
. "$PSScriptRoot\GFL-Common.ps1"
if(-not $PlanIn){ $PlanIn = Join-Path $Plans 'PLAN.json' }
if(-not $OutDir){ $OutDir = $Queues }

$plan=JLoad $PlanIn @(); $imm=@(); $idle=@(); $man=@()
foreach($t in $plan){
  switch($t.priority){
    'high'   { if($imm.Count -lt $MaxImmediate){ $imm += $t } else { $idle += $t } }
    'medium' { $idle += $t }
    default  { $man  += $t }
  }
}
JSave $imm  (Join-Path $OutDir 'QUEUE_Immediate.json')
JSave $idle (Join-Path $OutDir 'QUEUE_Idle.json')
JSave $man  (Join-Path $OutDir 'QUEUE_Manual.json')
ALog ("Assign I:{0} Idle:{1} M:{2}" -f [int]$imm.Count,[int]$idle.Count,[int]$man.Count) 'ASSIGN'






