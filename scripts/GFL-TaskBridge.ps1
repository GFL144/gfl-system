<# ============================================================================================================
   GFL-TaskBridge.ps1  (v1.0.3, PS5-safe)
   Queue + Worker + Live Feed for the micro-dashboard
============================================================================================================ #>

[CmdletBinding()]
param(
  # Queue ops
  [switch]$Init,
  [string]$EnqueueType,                         # FinalizeAll | PublishStatus | MassUpload | MassDownload | WalletExt | Diagnostics
  [hashtable]$EnqueueArgs = @{},                # <-- default so it never binds as Object[]
  [int]$Priority = 50,
  [string]$EnqueueFromFile,
  # Worker
  [switch]$RunWorker,
  [int]$MaxParallel = 1,
  [int]$MaxAttempts = 3,
  # Schedule (optional)
  [switch]$RegisterSchedule,
  [int]$EveryMinutes = 10
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Paths
$Root        = 'C:\GFL-System'
$Reports     = Join-Path $Root 'Reports'
$Logs        = Join-Path $Reports 'logs'
$TasksDir    = Join-Path $Reports 'tasks'
$QueueFile   = Join-Path $TasksDir 'queue.json'
$Timeline    = Join-Path $TasksDir 'timeline.json'
$RecentFeed  = Join-Path $TasksDir 'recent.json'
$StatusFile  = Join-Path $Reports  'status.json'
New-Item -ItemType Directory -Force -Path $Reports,$Logs,$TasksDir | Out-Null

# External scripts used by worker
$FinalizePath   = 'C:\GFL-System\Scripts\GFL-Finalize-Expansion.ps1'
$AutoPulsePath  = 'C:\GFL-System\Scripts\GFL-AutoPulse.ps1'

# --- Helpers -----------------------------------------------------------------------------------------------
function Log([string]$msg){
  $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  Add-Content -Path (Join-Path $Logs 'taskbridge.log') -Value $line
  Write-Host " $msg"
}

function Use-Lock([scriptblock]$Script){
  $lockPath = Join-Path $TasksDir '.queue.lock'
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  while(Test-Path $lockPath){ Start-Sleep -Milliseconds 120; if($sw.Elapsed.TotalSeconds -gt 10){ break } }
  try { New-Item -ItemType File -Path $lockPath -Force | Out-Null } catch {}
  try { & $Script } finally { Remove-Item $lockPath -ErrorAction SilentlyContinue }
}

function Read-JsonFile([string]$path, $fallback){
  if(Test-Path $path){ try { return (Get-Content $path -Raw | ConvertFrom-Json) } catch { return $fallback } }
  return $fallback
}
function Write-JsonFile([string]$path, $obj, [int]$depth=6){
  ($obj | ConvertTo-Json -Depth $depth) | Set-Content -Path $path -Encoding UTF8
}

# --- Init ---------------------------------------------------------------------------------------------------
function Initialize-Queue {
  Use-Lock {
    if(-not (Test-Path $QueueFile)){ Write-JsonFile $QueueFile @() }
    if(-not (Test-Path $Timeline)){  Write-JsonFile $Timeline  @() }
    if(-not (Test-Path $RecentFeed)){Write-JsonFile $RecentFeed @() }
  }
  Log "Queue storage initialized."
}

# --- Enqueue ------------------------------------------------------------------------------------------------
function New-TaskItem([string]$type,[hashtable]$args,[int]$prio=50){
  if(-not $args){ $args = @{} }
  return [ordered]@{
    id        = [guid]::NewGuid().ToString()
    type      = $type
    args      = $args
    priority  = $prio
    status    = 'queued'
    created   = (Get-Date).ToString('s')
    started   = $null
    finished  = $null
    attempts  = 0
    lastError = $null
    log       = @()
  }
}

function Enqueue-Task([string]$type,[hashtable]$args=@{},[int]$prio=50){
  if(-not $args){ $args = @{} }
  $task = New-TaskItem -type $type -args $args -prio $prio
  Use-Lock {
    $q = Read-JsonFile $QueueFile @()
    $q += $task
    $q = $q | Sort-Object @{Expression='priority';Descending=$true}, @{Expression='created';Descending=$false}
    Write-JsonFile $QueueFile $q
  }
  Log "Enqueued: $($task.id)  $type (priority $prio)"
  return $task
}

function Enqueue-FromFile([string]$file){
  if(-not (Test-Path $file)){ throw "File not found: $file" }
  $arr = Get-Content $file -Raw | ConvertFrom-Json
  foreach($t in $arr){
    $p = 50
    if($t.PSObject.Properties.Name -contains 'priority' -and ($t.priority -is [int])){ $p = [int]$t.priority }
    $a = @{}
    if($t.PSObject.Properties.Name -contains 'args' -and $t.args){ $a = [hashtable]$t.args }
    [void](Enqueue-Task -type $t.type -args $a -prio $p)
  }
  Log "Enqueued batch from file: $file"
}

# --- Feeds --------------------------------------------------------------------------------------------------
function Update-Feeds($record){
  Use-Lock {
    $tl = Read-JsonFile $Timeline @()
    $tl += $record
    Write-JsonFile $Timeline $tl
    $recent = $tl | Select-Object -Last 50
    Write-JsonFile $RecentFeed $recent
  }
}

# --- Worker -------------------------------------------------------------------------------------------------
function Invoke-Task([hashtable]$task){
  $id = $task.id; $type = $task.type; $args = $task.args; $log  = @()
  $append = { param($txt) $script:log += ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $txt) }
  &$append "Start task $type"

  switch -Regex ($type){
    '^FinalizeAll$'    { if(-not (Test-Path $FinalizePath)){ throw "Finalize not found: $FinalizePath" }
                         &$append "Finalize -GoAll"
                         & pwsh -NoProfile -ExecutionPolicy Bypass -File $FinalizePath -GoAll | ForEach-Object { &$append $_ } }
    '^PublishStatus$'  { if(-not (Test-Path $AutoPulsePath)){ throw "AutoPulse not found: $AutoPulsePath" }
                         &$append "AutoPulse -PublishNow"
                         & pwsh -NoProfile -ExecutionPolicy Bypass -File $AutoPulsePath -PublishNow | ForEach-Object { &$append $_ } }
    '^MassUpload$'     { & pwsh -NoProfile -ExecutionPolicy Bypass -File $FinalizePath -MassUpload    | ForEach-Object { &$append $_ } }
    '^MassDownload$'   { & pwsh -NoProfile -ExecutionPolicy Bypass -File $FinalizePath -MassDownload  | ForEach-Object { &$append $_ } }
    '^WalletExt$'      { & pwsh -NoProfile -ExecutionPolicy Bypass -File $FinalizePath -RebuildWalletExtension | ForEach-Object { &$append $_ } }
    '^Diagnostics$'    { & pwsh -NoProfile -ExecutionPolicy Bypass -File $FinalizePath -RunDiagnostics | ForEach-Object { &$append $_ } }
    default            { throw "Unsupported task type: $type" }
  }

  return ,$log
}

function Run-WorkerLoop([int]$maxParallel,[int]$maxAttempts){
  $now = (Get-Date).ToString('s')

  # Claim tasks
  $claimed = Use-Lock {
    $q = Read-JsonFile $QueueFile @()
    $take = @()
    foreach($t in $q){
      if($take.Count -ge $maxParallel){ break }
      if($t.status -eq 'queued'){
        $t.status  = 'running'
        $t.started = $now
        $t.log    += "[{0}] claimed by worker" -f (Get-Date -Format 'HH:mm:ss')
        $take += $t
      }
    }
    Write-JsonFile $QueueFile $q
    return $take
  }

  if(-not $claimed -or $claimed.Count -eq 0){ Log "No queued tasks."; return }
  Log ("Running {0} task(s)..." -f $claimed.Count)

  foreach($t in $claimed){
    try{
      $t.attempts++
      $logs = Invoke-Task -task $t
      $t.log += $logs
      $t.status   = 'done'
      $t.finished = (Get-Date).ToString('s')
      Update-Feeds $t
      Log " Completed: $($t.id)  $($t.type)"
    } catch {
      $t.lastError = $_.Exception.Message
      $t.log += ("[{0}] ERROR: {1}" -f (Get-Date -Format 'HH:mm:ss'), $t.lastError)
      if($t.attempts -ge $maxAttempts){
        $t.status = 'failed'
        $t.finished = (Get-Date).ToString('s')
        Update-Feeds $t
        Log " Failed (max attempts): $($t.id)  $($t.type) :: $($t.lastError)"
      } else {
        $t.status = 'queued'
        Log " Requeued: $($t.id) (attempt $($t.attempts))"
      }
    } finally {
      # Replace item (PS5-safe)
      Use-Lock {
        $q = Read-JsonFile $QueueFile @()
        $newQ = @()
        foreach($item in $q){ if($item.id -eq $t.id){ $newQ += $t } else { $newQ += $item } }
        Write-JsonFile $QueueFile $newQ
      }
    }
  }

  # Refresh status for panel
  try { if(Test-Path $AutoPulsePath){ & pwsh -NoProfile -ExecutionPolicy Bypass -File $AutoPulsePath -PublishNow | Out-Null } } catch { }
}

# --- Scheduler ----------------------------------------------------------------------------------------------
function Register-TaskBridgeSchedule([int]$mins){
  $taskName = 'GFL_TaskBridge_Worker'
  $pwshExe  = (Get-Command pwsh).Source
  $action   = New-ScheduledTaskAction -Execute $pwshExe -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -RunWorker -MaxParallel $MaxParallel -MaxAttempts $MaxAttempts"
  $trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $mins) -RepetitionDuration ([TimeSpan]::MaxValue)
  $principal= New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -RunLevel Highest -LogonType Interactive  # <-- fixed
  if(Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue){ Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal | Out-Null
  Log "Scheduled Task '$taskName' registered (every $mins min)"
}

# --- Entry --------------------------------------------------------------------------------------------------
if($Init){ Initialize-Queue }

if($EnqueueFromFile){ Enqueue-FromFile -file $EnqueueFromFile }
elseif($EnqueueType){  [void](Enqueue-Task -type $EnqueueType -args $EnqueueArgs -prio $Priority) }

if($RunWorker){ Run-WorkerLoop -maxParallel $MaxParallel -maxAttempts $MaxAttempts }

if($RegisterSchedule){ Register-TaskBridgeSchedule -mins $EveryMinutes }

Log " TaskBridge execution complete."
