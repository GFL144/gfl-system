param(
  [switch]$Generate,
  [switch]$RunImmediate,
  [switch]$RunIdle,
  [int]$MaxImmediate = 1
)

# Resolve all paths relative to this script
$Scripts = $PSScriptRoot
$GRoot   = Split-Path -Parent $Scripts
$Reports = Join-Path $GRoot 'Reports'
$Queues  = Join-Path $Reports 'queues'
$Plans   = Join-Path $Reports 'plans'
$Config  = Join-Path $GRoot 'Config'
New-Item -ItemType Directory -Force -Path $Reports,$Queues,$Plans | Out-Null
. "$PSScriptRoot\GFL-Common.ps1"

# concrete files
$QueueAuthIn   = Join-Path $Queues 'TASK_QUEUE_AUTH-INPUT.json'
$QueueAuth     = Join-Path $Queues 'TASK_QUEUE_AUTH.json'
$PlanPath      = Join-Path $Plans  'PLAN.json'
$PolicyPath    = Join-Path $Config 'policy.json'
$TaskMakerPath = Join-Path $Scripts 'GFL-TaskMaker.ps1'
$AuthPath      = Join-Path $Scripts 'GFL-TaskAuthority.ps1'
$SorterPath    = Join-Path $Scripts 'GFL-TaskSorter.ps1'
$AssignerPath  = Join-Path $Scripts 'GFL-TaskAssigner.ps1'
$RunnerPath    = Join-Path $Scripts 'GFL-TaskRunner.ps1'

# Bootstrap tasks if requested
if ($Generate) {
  if (Test-Path $TaskMakerPath) {
    & $TaskMakerPath -Out $QueueAuthIn
  }
  if (-not (Test-Path $QueueAuthIn)) {
    $tasks = @(
      @{ id='demo-1'; title='Sample high task'; risk='high' },
      @{ id='demo-2'; title='Sample low task';  risk='low'  }
    )
    JSave $tasks $QueueAuthIn
  }
  ALog 'Bootstrap queue created' 'SQMA'
}

# AUTH
& $AuthPath   -QueueIn $QueueAuthIn -QueueOut $QueueAuth -Policy $PolicyPath
$authCount  = (JLoad $QueueAuth  @()).Count
$inputCount = (JLoad $QueueAuthIn@()).Count
ALog ("Authorized {0}/{1}" -f $authCount,$inputCount) 'AUTH'

# SORT => Plan.json
& $SorterPath -QueueIn $QueueAuth -PlanOut $PlanPath -Policy $PolicyPath

# ASSIGN => split queues dir
$OutDir = Join-Path $Queues 'split'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
& $AssignerPath -PlanIn $PlanPath -OutDir $OutDir -MaxImmediate $MaxImmediate

# RUN immediate/idle
if ($RunImmediate) {
  $ImmediateQueue = Join-Path $OutDir 'QUEUE_Immediate.json'
  if (Test-Path $ImmediateQueue) { & $RunnerPath -QueueIn $ImmediateQueue -Policy $PolicyPath }
}
if ($RunIdle) {
  $IdleQueue = Join-Path $OutDir 'QUEUE_Idle.json'
  if (Test-Path $IdleQueue) { & $RunnerPath -QueueIn $IdleQueue -Policy $PolicyPath }
}

ALog 'SQMA flow complete' 'SQMA'

