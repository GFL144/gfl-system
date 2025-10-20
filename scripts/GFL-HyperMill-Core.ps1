param(
  [string]$ConfigPath = 'C:\GFL-System\Configs\hypermill.json',
  [string]$StatusPath = 'C:\GFL-System\Reports\hypermill-status.json',
  [string]$QueueRoot  = 'C:\GFL-System\HyperMill\Queue'
)
using namespace System.Collections.Concurrent
$ErrorActionPreference='Stop'

# --- Load config
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$maxPerMin = [int]$cfg.rate.maxPerMinute
$burst     = [int]$cfg.rate.burst
$minRS     = [int]$cfg.runspaces.min
$maxRS     = [int]$cfg.runspaces.max

# --- Token-bucket (refill 20x/sec)
$bucket = [System.Threading.Interlocked]::Add([ref]0,0) | Out-Null
$tokens = [ref]([int]$burst)
$sw     = [System.Diagnostics.Stopwatch]::StartNew()
$sync   = New-Object object

# thread-safe queue of files
$q = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$lanes = @('generate','test','prod','download','upload') | ForEach-Object { Join-Path $QueueRoot  }

# prime: enqueue any existing tasks
foreach($ln in $lanes){ Get-ChildItem $ln -File | ForEach-Object { $q.Enqueue($_.FullName) } }

# watchers
$watchers = @()
foreach($ln in $lanes){
  $w = New-Object IO.FileSystemWatcher $ln, '*.json'
  $w.EnableRaisingEvents = $true
  Register-ObjectEvent $w Created -Action { Start-Sleep -Milliseconds 120; $global:q.Enqueue($Event.SourceEventArgs.FullPath) } | Out-Null
  $watchers += $w
}

# runspace pool
$iss = [initialsessionstate]::CreateDefault()
$pool = [runspacefactory]::CreateRunspacePool($minRS, $maxRS, $iss, System.Management.Automation.Internal.Host.InternalHost)
$pool.Open()

# submit job
function Submit([string]$file){
  if(-not (Test-Path $file)){ return }
  $job = [powershell]::Create()
  $job.RunspacePool = $pool
  $taskJson = Get-Content $file -Raw
  $t = $taskJson | ConvertFrom-Json
  switch($t.lane){
    'generate' { $job.AddCommand('pwsh').AddArgument('-NoProfile').AddArgument('-File').AddArgument('C:\GFL-System\Scripts\GFL-Worker-Gen.ps1') | Out-Null }
    'download' { $job.AddCommand('pwsh').AddArgument('-NoProfile').AddArgument('-File').AddArgument('C:\GFL-System\Scripts\GFL-Worker-IO.ps1')  | Out-Null }
    'upload'   { $job.AddCommand('pwsh').AddArgument('-NoProfile').AddArgument('-File').AddArgument('C:\GFL-System\Scripts\GFL-Worker-IO.ps1')  | Out-Null }
    'test'     { $job.AddCommand('pwsh').AddArgument('-NoProfile').AddArgument('-File').AddArgument('C:\GFL-System\Scripts\GFL-Worker-Test.ps1')| Out-Null }
    'prod'     { $job.AddCommand('pwsh').AddArgument('-NoProfile').AddArgument('-File').AddArgument('C:\GFL-System\Scripts\GFL-Worker-Prod.ps1')| Out-Null }
    default    { return }
  }
  $job.AddArgument($taskJson) | Out-Null
  $as = $job.BeginInvoke()
  # when done, move to done/ and write a .out
  Register-ObjectEvent $as Completed -Action {
    try{
      $res = $job.EndInvoke($as)
      $out = [string]::Join("
",$res)
      $outPath = [io.path]::ChangeExtension($file,'.out')
      $out | Out-File $outPath -Encoding utf8
      Move-Item $file ('C:\GFL-System\HyperMill\Queue\done') -Force
    }catch{
      try{
        $errPath = [io.path]::ChangeExtension($file,'.err')
        "$_" | Out-File $errPath -Encoding utf8
        Move-Item $file ('C:\GFL-System\HyperMill\Queue\done') -Force
      }catch{}
    }finally{ $job.Dispose() }
  } | Out-Null
}

# refill loop
$refillMs = 50
$timer = [System.Timers.Timer]::new($refillMs)
$timer.AutoReset = $true
$timer.Add_Elapsed({
  $add = [math]::Ceiling(($maxPerMin/60.0) * ($refillMs/1000.0))
  [System.Threading.Monitor]::Enter($sync); try {
    $new = $tokens.Value + $add
    if($new -gt $burst){ $new = $burst }
    $tokens.Value = $new
  } finally { [System.Threading.Monitor]::Exit($sync) }
}) | Out-Null
$timer.Start()

# dispatcher
$stats = [ordered]@{ started=0; submitted=0; drained=0; last=$(Get-Date).ToString('o') }
while(True){
  # pull next file if tokens available
  if([System.Threading.Monitor]::TryEnter($sync)){
    try{
      if($tokens.Value -gt 0){
        if($q.TryDequeue([ref]$next)){
          $tokens.Value = $tokens.Value - 1
          Submit $next
          $stats.submitted++
        }
      }
    } finally { [System.Threading.Monitor]::Exit($sync) }
  }
  # status drop
  if(((Get-Date) - [datetime]::ParseExact($stats.last,'o',[Globalization.CultureInfo]::InvariantCulture)).TotalSeconds -ge 1){
    $stats.last = (Get-Date).ToString('o')
    $payload = [pscustomobject]@{
      ts = $stats.last
      tokens = $tokens.Value
      queue  = $q.Count
      submitted = $stats.submitted
      lanes = @('generate','test','prod','download','upload') | ForEach-Object { @{ lane = $_; count = (Get-ChildItem (Join-Path $QueueRoot $_) -File).Count } }
    }
    ($payload | ConvertTo-Json -Depth 8) | Out-File 'C:\GFL-System\Reports\hypermill-status.json' -Encoding utf8
  }
  Start-Sleep -Milliseconds 5
}
