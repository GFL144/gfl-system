# ==========================================================================================================
# GFL-Mega-Orchestrator.ps1  (PS5-safe edition)
# Sets up core folders, ensures tools, installs/runs Background Agent, starts local API, registers tasks.
# ==========================================================================================================

[CmdletBinding()]
param(
  [switch]$Everything,

  [switch]$SetupFolders,
  [switch]$EnsureTools,
  [switch]$Upgrades,
  [switch]$InstallBackgroundAgent,
  [switch]$StartDashboardApi,
  [switch]$CreateTasks,

  [int]$AgentIntervalSec = 5,
  [int]$AgentSpeedtestMins = 30,
  [int]$ApiPort = 8787,
  [string]$BindPrefix = "http://127.0.0.1",
  [string]$Root = "C:\GFL-System"
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Say([string]$t,[string]$c="Gray"){ Write-Host $t -ForegroundColor $c }
function Get-CmdPath([string]$n){ $cmd = Get-Command $n -ErrorAction SilentlyContinue; if($cmd){ $cmd.Source } else { $null } }
function New-Dirs([string[]]$paths){ foreach($p in $paths){ if(-not (Test-Path $p)){ New-Item -ItemType Directory -Path $p | Out-Null } } }

if($Everything){
  $SetupFolders=$true; $EnsureTools=$true; $Upgrades=$true;
  $InstallBackgroundAgent=$true; $StartDashboardApi=$true; $CreateTasks=$true
}

$Dirs = @{
  Root     = $Root
  Scripts  = Join-Path $Root "Scripts"
  Logs     = Join-Path $Root "Logs"
  State    = Join-Path $Root "State"
  Config   = Join-Path $Root "Config"
  Network  = Join-Path $Root "Network"
  Monitor  = Join-Path $Root "Monitor"
  Temp     = Join-Path $Root "Temp"
}

# ---------- SetupFolders ----------
if($SetupFolders){
  Say "Setting up folder tree under $($Dirs.Root) ..." Cyan
  New-Dirs @($Dirs.Root,$Dirs.Scripts,$Dirs.Logs,$Dirs.State,$Dirs.Config,$Dirs.Network,$Dirs.Monitor,$Dirs.Temp)
  if(-not (Test-Path (Join-Path $Dirs.State 'status.json'))){
    '{ "note":"Background agent will update this file" }' | Set-Content (Join-Path $Dirs.State 'status.json') -Encoding UTF8
  }
  if(-not (Test-Path (Join-Path $Dirs.Logs 'nic_stats.csv'))){
    'TimeUTC,Name,Rx_Bps,Tx_Bps,Rx_Mbps,Tx_Mbps' | Set-Content (Join-Path $Dirs.Logs 'nic_stats.csv') -Encoding UTF8
  }
  Say "Folder setup complete." Green
}

# ---------- EnsureTools ----------
function Ensure-Tool([string]$exe,[string]$wingetId=$null,[string]$chocoId=$null){
  $found = Get-CmdPath $exe; if($found){ return $found }
  $wg = Get-CmdPath 'winget'
  if($wg -and $wingetId){
    try{ & $wg install -e --id $wingetId --accept-source-agreements --accept-package-agreements | Out-Null }catch{}
    $found = Get-CmdPath $exe; if($found){ return $found }
  }
  $ch = Get-CmdPath 'choco'
  if($ch -and $chocoId){
    try{ & $ch install $chocoId -y --no-progress | Out-Null }catch{}
    $found = Get-CmdPath $exe; if($found){ return $found }
  }
  return $null
}

if($EnsureTools){
  Say "Ensuring tools (git, 7zip, node, python, rclone, winscp, speedtest) ..." Cyan
  $tools = @(
    @{ exe="git";      winget="Git.Git";             choco="git" },
    @{ exe="7z";       winget="7zip.7zip";           choco="7zip" },
    @{ exe="node";     winget="OpenJS.NodeJS.LTS";   choco="nodejs-lts" },
    @{ exe="python";   winget="Python.Python.3.12";  choco="python" },
    @{ exe="rclone";   winget="Rclone.Rclone";       choco="rclone" },
    @{ exe="winscp";   winget="WinSCP.WinSCP";       choco="winscp" },
    @{ exe="speedtest";winget="Ookla.Speedtest";     choco="speedtest" }
  )
  foreach($t in $tools){
    $res = Ensure-Tool -exe $t.exe -wingetId $t.winget -chocoId $t.choco
    if($res){ Say ("OK: {0}  {1}" -f $t.exe,$res) Green } else { Say ("MISSING: {0}" -f $t.exe) Yellow }
  }
}

# ---------- Upgrades ----------
function Do-Upgrades {
  $out=@()
  $wg = Get-CmdPath 'winget'
  if($wg){ try{ & $wg upgrade --all --silent --accept-source-agreements --accept-package-agreements | Out-Null; $out+='winget: upgrade attempted' }catch{ $out+="winget: $_" } }
  $ch = Get-CmdPath 'choco'
  if($ch){ try{ & $ch upgrade all -y --no-progress | Out-Null; $out+='choco: upgrade attempted' }catch{ $out+="choco: $_" } }
  $out -join '; '
}
if($Upgrades){
  Say "Running upgrade pass..." Cyan
  Say (Do-Upgrades) Gray
}

# ---------- Background Agent (writes status.json + nic_stats.csv) ----------
if($InstallBackgroundAgent){
  $AgentPath = Join-Path $Dirs.Monitor 'GFL-Background-Agent.ps1'
  if(-not (Test-Path $AgentPath)){
    Say "Writing minimal Background Agent..." Yellow
@"
[CmdletBinding()]
param([switch]$Install,[switch]$Run,[int]$IntervalSec=5,[int]$SpeedtestMins=30,[string]$LogRoot="$($Dirs.Logs)",[string]$StateRoot="$($Dirs.State)")
\$ErrorActionPreference='Stop'
function Get-CmdPath([string]\$n){ \$c=Get-Command \$n -ErrorAction SilentlyContinue; if(\$c){ \$c.Source } else { \$null } }
function Ensure-Dirs([string[]]\$p){ foreach(\$x in \$p){ if(-not (Test-Path \$x)){ New-Item -ItemType Directory -Path \$x | Out-Null } } }
function Snap(){ Get-NetAdapterStatistics | ForEach-Object { [pscustomobject]@{ TimeUTC=(Get-Date).ToUniversalTime().ToString('o'); Name=\$_.Name; RX=\$_.ReceivedBytes; TX=\$_.SentBytes } } }
function Rates([int]\$s){ \$a=Snap; Start-Sleep -Seconds \$s; \$b=Snap; for(\$i=0; \$i -lt \$b.Count; \$i++){ [pscustomobject]@{ TimeUTC=(Get-Date).ToUniversalTime().ToString('o'); Name=\$b[\$i].Name; Rx_Mbps=[math]::Round((\$b[\$i].RX-\$a[\$i].RX)*8.0/\$s/1MB,3); Tx_Mbps=[math]::Round((\$b[\$i].TX-\$a[\$i].TX)*8.0/\$s/1MB,3) } } }
function J(\$o,\$p){ \$j=\$o|ConvertTo-Json -Depth 6; \$t="\$p.tmp"; \$j|Set-Content \$t -Encoding UTF8; Move-Item \$t \$p -Force }
if(\$Install){
  Ensure-Dirs @("$($Dirs.Logs)","$($Dirs.State)")
  \$ps = Get-CmdPath 'pwsh'; if(-not \$ps){ \$ps = Get-CmdPath 'powershell' }
  \$script = \$MyInvocation.MyCommand.Path
  \$act = New-ScheduledTaskAction -Execute \$ps -Argument "-NoProfile -ExecutionPolicy Bypass -File `"\$script`" -Run -IntervalSec $AgentIntervalSec -SpeedtestMins $AgentSpeedtestMins"
  \$trg = New-ScheduledTaskTrigger -AtStartup
  \$set = New-ScheduledTaskSettingsSet -RestartCount 9999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName "GFL-Background-Agent" -Action \$act -Trigger \$trg -Settings \$set -Description "GFL realtime monitor" -Force | Out-Null
  return
}
if(\$Run){
  Ensure-Dirs @("$($Dirs.Logs)","$($Dirs.State)")
  \$csv = Join-Path "$($Dirs.Logs)" 'nic_stats.csv'
  if(-not (Test-Path \$csv)){ "TimeUTC,Name,Rx_Mbps,Tx_Mbps"|Set-Content \$csv -Encoding UTF8 }
  while(\$true){
    \$r = Rates -s $AgentIntervalSec
    foreach(\$x in \$r){ "\$([datetime]::UtcNow.ToString('o')),\$(\$x.Name),\$(\$x.Rx_Mbps),\$(\$x.Tx_Mbps)" | Add-Content \$csv -Encoding UTF8 }
    J ([pscustomobject]@{ time_utc=[datetime]::UtcNow.ToString('o'); nic_samples=\$r }) (Join-Path "$($Dirs.State)" 'status.json')
  }
}
"@ | Set-Content $AgentPath -Encoding UTF8
  }
  Say "Installing Background Agent scheduled task..." Cyan
  $pw = Get-CmdPath 'pwsh'; if(-not $pw){ $pw = Get-CmdPath 'powershell' }
  & $pw -NoProfile -ExecutionPolicy Bypass -File $AgentPath -Install -IntervalSec $AgentIntervalSec -SpeedtestMins $AgentSpeedtestMins
  Say "Background Agent installed." Green
}

# ---------- StartDashboardApi ----------
if($StartDashboardApi){
  $prefix = "$BindPrefix`:$ApiPort/"
  Say "Starting local Dashboard API at $prefix (Ctrl+C to stop) ..." Cyan
  Add-Type -AssemblyName System.Net.HttpListener
  $listener = New-Object System.Net.HttpListener
  $listener.Prefixes.Add($prefix)
  try{ $listener.Start() }catch{ Say "Failed to bind $prefix. Try as Admin or change port." Red; throw }

  $indexHtml = @"
<!doctype html><html><head><meta charset='utf-8'><title>GFL Dashboard API</title>
<style>body{font-family:Segoe UI,system-ui,Arial;margin:2rem;}code{background:#f3f3f3;padding:.2rem .4rem;border-radius:.3rem}</style>
</head><body>
<h1>GFL Dashboard API</h1>
<ul>
<li><a href="/api/health">/api/health</a></li>
<li><a href="/api/status">/api/status</a></li>
<li><a href="/api/nic">/api/nic</a></li>
</ul>
<p>Status: <code>$($Dirs.State)\status.json</code><br>NIC CSV: <code>$($Dirs.Logs)\nic_stats.csv</code></p>
</body></html>
"@

  while($listener.IsListening){
    $ctx = $listener.GetContext()
    Start-Job -ScriptBlock {
      param($ctx,$Dirs,$indexHtml)
      try{
        $req = $ctx.Request; $res = $ctx.Response
        $path = $req.RawUrl.ToLowerInvariant()
        switch -Regex ($path) {
          '^/$' {
            $buf = [Text.Encoding]::UTF8.GetBytes($indexHtml)
            $res.ContentType = "text/html; charset=utf-8"; $res.OutputStream.Write($buf,0,$buf.Length); break
          }
          '^/api/health' {
            $obj = @{ ok = $true; time_utc = [datetime]::UtcNow.ToString("o") }
            $buf = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Depth 4))
            $res.ContentType = "application/json"; $res.OutputStream.Write($buf,0,$buf.Length); break
          }
          '^/api/status' {
            $p = Join-Path $Dirs.State "status.json"
            if(Test-Path $p){ $raw = [IO.File]::ReadAllBytes($p); $res.ContentType = "application/json"; $res.OutputStream.Write($raw,0,$raw.Length) } else { $res.StatusCode = 404 }
            break
          }
          '^/api/nic' {
            $p = Join-Path $Dirs.Logs "nic_stats.csv"
            if(Test-Path $p){ $raw = [IO.File]::ReadAllBytes($p); $res.ContentType = "text/csv"; $res.OutputStream.Write($raw,0,$raw.Length) } else { $res.StatusCode = 404 }
            break
          }
          default { $res.StatusCode = 404 }
        }
      } catch { try{ $ctx.Response.StatusCode = 500 }catch{} }
      finally { try{ $ctx.Response.OutputStream.Close() }catch{} }
    } -ArgumentList $ctx,$Dirs,$indexHtml | Out-Null
  }
}

# ---------- CreateTasks ----------
if($CreateTasks){
  Say "Registering Scheduled Tasks (Agent + API) ..." Cyan
  $pw = Get-CmdPath 'pwsh'; if(-not $pw){ $pw = Get-CmdPath 'powershell' }

  # Agent task (re-register to ensure present)
  $agent = Join-Path $Dirs.Monitor "GFL-Background-Agent.ps1"
  if(Test-Path $agent){
    try{
      $aAction = New-ScheduledTaskAction -Execute $pw -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$agent`" -Run -IntervalSec $AgentIntervalSec -SpeedtestMins $AgentSpeedtestMins"
      $aTrig   = New-ScheduledTaskTrigger -AtStartup
      $aSet    = New-ScheduledTaskSettingsSet -RestartCount 9999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
      Register-ScheduledTask -TaskName "GFL-Background-Agent" -Action $aAction -Trigger $aTrig -Settings $aSet -Description "GFL realtime monitor" -Force | Out-Null
      Say "Task: GFL-Background-Agent registered." Green
    }catch{ Say "Agent task error: $_" Yellow }
  } else { Say "Agent script not found, skipping agent task." Yellow }

  # API task (hidden window at startup)
  $thisScript = $MyInvocation.MyCommand.Path
  try{
    $apiAction = New-ScheduledTaskAction -Execute $pw -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$thisScript`" -StartDashboardApi -ApiPort $ApiPort -BindPrefix `"$BindPrefix`""
    $apiTrig   = New-ScheduledTaskTrigger -AtStartup
    $apiSet    = New-ScheduledTaskSettingsSet -RestartCount 9999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName "GFL-Dashboard-API" -Action $apiAction -Trigger $apiTrig -Settings $apiSet -Description "Local API for dashboard" -Force | Out-Null
    Say "Task: GFL-Dashboard-API registered." Green
  }catch{ Say "API task error: $_" Yellow }
}

Say "All requested modules completed. " Cyan
# ==========================================================================================================


























