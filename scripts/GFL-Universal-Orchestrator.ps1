<# ================================================================================================
 GFL-Universal-Orchestrator.ps1 (v2.1-mini)
 Purpose: Diagnostics + CodeGen (templates) + TaskQueue + (optional) Cloud sync
 Notes:
    Updater is handled by Guardian; this script only supports -Updater if you want a quick check.
================================================================================================ #>

[CmdletBinding()]
param(
  [switch]$RunAll,
  [switch]$Diagnostics,
  [switch]$Repair,
  [switch]$MassUpgrade,
  [switch]$SyncClouds,
  [switch]$Updater
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Paths
$Root     = 'C:\GFL-System'
$Scripts  = Join-Path $Root 'Scripts'
$Reports  = Join-Path $Root 'Reports'
$Logs     = Join-Path $Reports 'logs'
$TasksDir = Join-Path $Root 'Tasks'
$Clouds   = Join-Path $Root 'CloudSync'
$Manifest = Join-Path $Root 'Manifests\system.json'

New-Item -ItemType Directory -Force -Path $Scripts,$Reports,$Logs,$TasksDir,$Clouds | Out-Null

function Write-Json($obj,$path){ $obj | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $path }

# 1) Diagnostics
function Invoke-GFLDiagnostics {
  Write-Host " Diagnostics..."
  $d = [ordered]@{}
  $d.RootExists      = Test-Path $Root
  $d.ScriptsExists   = Test-Path $Scripts
  $d.ReportsExists   = Test-Path $Reports
  $d.TasksExists     = Test-Path $TasksDir
  $d.FreeSpaceGB     = [math]::Round((Get-PSDrive C).Free/1GB,2)
  $d.PowerShell      = $PSVersionTable.PSVersion.ToString()
  $d.Timestamp       = Get-Date
  Write-Json $d (Join-Path $Logs 'diagnostics.json')
  Write-Host " Wrote $Logs\diagnostics.json"
}

# 2) Code Generator (Templates  .ps1)
function Invoke-GFLCodeGenerator {
  $tpl = Join-Path $Scripts 'Templates'
  if(-not (Test-Path $tpl)){ Write-Host "ℹ No Templates folder; skipping."; return }
  Get-ChildItem $tpl -Filter *.tpl -Recurse | ForEach-Object {
    $dest = $_.FullName -replace '\.tpl$','.ps1'
    (Get-Content $_ -Raw).
      Replace('<#=VERSION#>', (Get-Date -Format 'yyyy.MM.dd.HHmm')) |
      Set-Content -Encoding UTF8 $dest
  }
  Write-Host " Templates compiled."
}

# 3) Task Manager (queue.json)
function Invoke-GFLTaskManager {
  $q = Join-Path $TasksDir 'queue.json'
  if(-not (Test-Path $q)){ Write-Host "ℹ No task queue found."; return }
  $tasks = Get-Content $q -Raw | ConvertFrom-Json
  foreach($t in $tasks){
    Write-Host "  Task: $($t.name)"
    if($t.script -and (Test-Path $t.script)){
      & $t.script @($t.args)  # fire-and-forget in-proc
    } else {
      Write-Warning "Missing script for task '$($t.name)': $($t.script)"
    }
  }
}

# 4) Optional quick updater (just a fetch; Guardian does the safe path)
function Invoke-GFLUpdater {
  $url = "https://hopelinkdivinegfl.online/api/updates/system-manifest.json"
  try{
    $r = Invoke-RestMethod -Uri $url -UseBasicParsing
    Write-Host " Manifest version:" $r.version
    if($r.package){ Write-Host " Package URL available." } else { Write-Warning "No package URL in manifest." }
  } catch { Write-Warning "Updater check failed: $_" }
}

# 5) Cloud sync (rclone optional)
function Invoke-GFLCloudSync {
  $rclone = Get-Command rclone -ErrorAction SilentlyContinue
  if(-not $rclone){ Write-Warning "rclone not found; skipping cloud sync."; return }
  try {
    & rclone copy $Reports "GDrive:GFL-Backups/Reports" --progress
    if(Test-Path $Manifest){ & rclone copy $Manifest "GDrive:GFL-Backups" --progress }
    Write-Host " Cloud sync done."
  } catch { Write-Warning "Cloud sync failed: $_" }
}

# Switchboard
if($RunAll){
  Invoke-GFLDiagnostics
  Invoke-GFLCodeGenerator
  Invoke-GFLTaskManager
  if($Updater){ Invoke-GFLUpdater }
  Invoke-GFLCloudSync
  Write-Host "`n Orchestrator v2.1-mini cycle complete.`n"
} elseif($Diagnostics){ Invoke-GFLDiagnostics }
elseif($MassUpgrade){ Invoke-GFLUpdater }
elseif($SyncClouds){ Invoke-GFLCloudSync }
elseif($Repair){ Invoke-GFLDiagnostics; Invoke-GFLCodeGenerator }
else {
  Write-Host "Usage: -RunAll [-Updater]  |  -Diagnostics  |  -MassUpgrade  |  -SyncClouds  |  -Repair"
}
