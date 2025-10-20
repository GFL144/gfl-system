param([string]$QueueIn,[string]$QueueOut,[string]$Policy)

# Resolve all paths relative to this script
$Scripts = $PSScriptRoot
$GRoot   = Split-Path -Parent $Scripts
$Reports = Join-Path $GRoot 'Reports'
$Queues  = Join-Path $Reports 'queues'
$Plans   = Join-Path $Reports 'plans'
$Config  = Join-Path $GRoot 'Config'
New-Item -ItemType Directory -Force -Path $Reports,$Queues,$Plans | Out-Null
. "$PSScriptRoot\GFL-Common.ps1"
if(-not $QueueIn){  $QueueIn  = Join-Path $Queues 'TASK_QUEUE_AUTH-INPUT.json' }
if(-not $QueueOut){ $QueueOut = Join-Path $Queues 'TASK_QUEUE_AUTH.json' }
if(-not $Policy){   $Policy   = Join-Path $Config 'task_policies.json' }

$p = JLoad $Policy; $q = JLoad $QueueIn @(); $allowed=@(); if(-not $p){ ALog 'No policy' 'AUTH'; exit 1 }
$roleAll=@(); $p.roles.PSObject.Properties | % { $roleAll += $_.Value }
foreach($t in $q){
  if($p.forbidden_actions -contains $t.action){ ALog ("DENY forbidden {0}" -f [string]$t.action) 'AUTH'; continue }
  if($p.locks.global -and -not ($roleAll -contains $t.action)){ ALog ("LOCKED global for {0}" -f [string]$t.action) 'AUTH'; continue }
  $t | Add-Member -NotePropertyName authorized -NotePropertyValue $true -Force
  $t | Add-Member -NotePropertyName risk -NotePropertyValue ($p.risk_levels[$t.action]) -Force
  $allowed += $t
}
JSave $allowed $QueueOut; ALog ("Authorized {0}/{1}" -f $allowed.Count,$q.Count) 'AUTH'






