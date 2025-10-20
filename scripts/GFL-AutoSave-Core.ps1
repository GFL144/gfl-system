<# =====================================================================
   GFL-AutoSave-Core.ps1  (FIXED)
   - Uses Register-ObjectEvent -EventName Elapsed (no Add_Tick)
   - Uses [System.Text.Encoding] type
   - Auto-snapshot, exit-save, atomic writes, change-watcher
   ===================================================================== #>

[CmdletBinding()]
param(
  [string]$Root = 'C:\GFL-System',
  [string]$ProjectPath = 'C:\GFL-System\Games\Starspin',
  [string]$StatePath   = 'C:\GFL-System\Reports\state\gfl-state.json',
  [int]$SnapshotMinutes = 5,
  [int]$KeepSnapshots   = 12,
  [switch]$EnableWatcher,
  [string[]]$WatchGlobs = @('*.ps1','*.js','*.css','*.html','*.json')
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Paths
$Reports     = Join-Path $Root 'Reports'
$StateDir    = Join-Path $Reports 'state'
$AutosaveDir = Join-Path $Reports 'autosave'
$LogPath     = Join-Path $Reports 'autosave.log'
foreach($p in @($Reports,$StateDir,$AutosaveDir)){ if(-not (Test-Path $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }

function Write-Log($msg,[string]$lvl='INFO'){
  $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$lvl,$msg
  $line | Tee-Object -FilePath $LogPath -Append
}

# -------- Atomic write helpers (Encoding fixed) --------
function Set-GflAtomicText {
  param(
    [Parameter(Mandatory)] [string]$Path,
    [Parameter(Mandatory)] [string]$Content,
    [System.Text.Encoding]$Encoding = [System.Text.UTF8Encoding]::new($true)
  )
  $dir = Split-Path $Path -Parent
  if(-not (Test-Path $dir)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $tmp = Join-Path $dir ('.' + [IO.Path]::GetFileName($Path) + '.tmp_' + [guid]::NewGuid().ToString('N'))
  [IO.File]::WriteAllText($tmp, $Content, $Encoding)
  if(Test-Path $Path){ Remove-Item $Path -Force }
  Move-Item $tmp $Path -Force
}

function Set-GflAtomicJson {
  param([Parameter(Mandatory)] [string]$Path, [Parameter(Mandatory)] $Object)
  $json = $Object | ConvertTo-Json -Depth 8
  Set-GflAtomicText -Path $Path -Content $json
}

# -------- State save ----------
if(-not $Global:GflState){ $Global:GflState = [ordered]@{ started=(Get-Date).ToString('s'); counters=@{} } }

function Save-GflState {
  try {
    Set-GflAtomicJson -Path $StatePath -Object $Global:GflState
    Write-Log "Saved state: $StatePath"
  } catch { Write-Log "Save-GflState error: $($_.Exception.Message)" 'ERR' }
}

# -------- Snapshot & rotate ----------
function New-GflSnapshot {
  param([string]$Source = $ProjectPath)
  try{
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $zip = Join-Path $AutosaveDir ("autosnap_${stamp}.zip")
    if(Test-Path $zip){ Remove-Item $zip -Force }
    $ex = @('node_modules','dist','bin','logs','artifacts','Backups','.git')
    $items = Get-ChildItem $Source -Force -ErrorAction SilentlyContinue
    $temp = Join-Path $env:TEMP ("gfl_autosnap_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    foreach($i in $items){
      if($i -and ($ex -contains $i.Name)){ continue }
      try { Copy-Item $i.FullName -Destination (Join-Path $temp $i.Name) -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
    if(Test-Path $temp){
      Compress-Archive -Path (Join-Path $temp '*') -DestinationPath $zip -Force -ErrorAction SilentlyContinue
      Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Log "Snapshot saved: $zip"
    Get-ChildItem $AutosaveDir -Filter 'autosnap_*.zip' | Sort-Object LastWriteTime -Descending | Select-Object -Skip $KeepSnapshots | Remove-Item -Force -ErrorAction SilentlyContinue
  }catch{ Write-Log "Snapshot error: $($_.Exception.Message)" 'ERR' }
}

# -------- Exit hooks ----------
$script:ExitSub = Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PSEngineEvent]::Exiting) -Action {
  try { Save-GflState; New-GflSnapshot } catch {}
} -SupportEvent

$script:ErrSub = Register-EngineEvent -SourceIdentifier 'GFL.Unhandled' -Action {
  try { Save-GflState; New-GflSnapshot } catch {}
}

$Global:Error.Clear()
$ExecutionContext.SessionState.PSVariable.Set('ErrorActionPreference','Continue')

# -------- Timers (Register-ObjectEvent) ----------
# Main autosave timer
$script:Timer = New-Object System.Timers.Timer
$script:Timer.Interval = [Math]::Max(60000, $SnapshotMinutes * 60000)  # >= 1 minute
$script:Timer.AutoReset = $true
$null = Register-ObjectEvent -InputObject $script:Timer -EventName Elapsed -SourceIdentifier 'GFL.AutoSave.Elapsed' -Action {
  Save-GflState; New-GflSnapshot
}
$script:Timer.Start()
Write-Log "AutoSave timer started (${SnapshotMinutes} min)."

# Heartbeat counter
if(-not $Global:GflState.counters.heartbeat){ $Global:GflState.counters.heartbeat = 0 }
$script:Heartbeat = New-Object System.Timers.Timer
$script:Heartbeat.Interval = 15000
$script:Heartbeat.AutoReset = $true
$null = Register-ObjectEvent -InputObject $script:Heartbeat -EventName Elapsed -SourceIdentifier 'GFL.AutoSave.Heartbeat' -Action {
  $Global:GflState.counters.heartbeat++
}
$script:Heartbeat.Start()

# -------- Optional file change watcher ----------
if($EnableWatcher){
  $script:Watchers = @()
  foreach($glob in $WatchGlobs){
    $fsw = New-Object IO.FileSystemWatcher $ProjectPath, $glob
    $fsw.IncludeSubdirectories = $true
    $fsw.EnableRaisingEvents = $true
    Register-ObjectEvent $fsw Changed -SourceIdentifier ("GFL.AutoSave.Watch."+($glob -replace '[^\w]','_')) -Action {
      try{
        $root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("$using:ProjectPath")
        $autosave = Join-Path "$using:Root" 'Reports\autosave'
        $rel = $Event.SourceEventArgs.FullPath.Substring($root.Length).TrimStart('\')
        $bakDir = Join-Path $autosave 'onchange'
        if(-not (Test-Path $bakDir)){ New-Item -ItemType Directory -Force -Path $bakDir | Out-Null }
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmssfff'
        $dest  = Join-Path $bakDir ($rel -replace '[\\/]', '__') + ".${stamp}.bak"
        Copy-Item $Event.SourceEventArgs.FullPath $dest -Force
        Write-Log "OnChange backup: $rel -> $(Split-Path $dest -Leaf)"
      }catch{ Write-Log "OnChange error: $($_.Exception.Message)" 'ERR' }
    } | Out-Null
    $script:Watchers += $fsw
  }
  Write-Log "File watcher ON."
}

function Register-GflAutoSave {
  param([string]$Note)
  Write-Log ("AutoSave registered" + ($(if($Note){"  " + $Note}else{""})))
  Save-GflState
}

Write-Log "GFL-AutoSave-Core FIXED loaded. Exit saving enabled."






























