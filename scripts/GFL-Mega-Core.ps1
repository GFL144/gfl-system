
<#
 GFL‑Mega‑Core.ps1 — Monolithic Edition (Basics + Phase 2)
 ──────────────────────────────────────────────────────────
 One "mess of script" that bootstraps the GFL‑System, ensures core tools,
 writes configs, provides ISO helpers, Android/FTP bridge stubs, a basic
 dashboard (static + HTTP server), auto‑heal (basic + advanced), an
 auto‑updater loop, rclone sync helpers, miner/trader bridge stubs, and
 convenient switches. Safe defaults. Non‑destructive.

 Run (Admin recommended):
   pwsh -NoProfile -ExecutionPolicy Bypass -File C:\GFL-System\Scripts\GFL-Mega-Core.ps1 -Everything

 Version: 2025‑10‑18
#>

[CmdletBinding()]
param(
  [switch]$Everything,
  [switch]$DoSetup,
  [switch]$DoTools,
  [switch]$DoConfigs,
  [switch]$DoAutostart,
  [switch]$DoISO,
  [switch]$DoAndroidBridge,
  [switch]$DoFTPBridge,
  [switch]$DoDashboard,
  [switch]$DoAutoHeal,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = 'GFL‑Mega‑Core — Monolithic'

function Say { param([string]$Msg,[ConsoleColor]$Color='Gray') Write-Host $Msg -ForegroundColor $Color }
function PathSafe([string]$p){ return [IO.Path]::GetFullPath($p) }
function Test-Admin { $id=[Security.Principal.WindowsIdentity]::GetCurrent(); $p=[Security.Principal.WindowsPrincipal]::new($id); return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator) }
function Get-Command($n){ (Get-Command $n -EA SilentlyContinue | Select-Object -First 1).Source }

# ─────────────────────────────────────────────────────────────────────────────
# Paths & logging
# ─────────────────────────────────────────────────────────────────────────────
$GflRoot    = 'C:\GFL-System'
$Dirs = [ordered]@{
  Root       = $GflRoot
  Bin        = "$GflRoot\Bin"
  Scripts    = "$GflRoot\Scripts"
  Logs       = "$GflRoot\Logs"
  Temp       = "$GflRoot\Temp"
  Config     = "$GflRoot\Config"
  Dashboards = "$GflRoot\Dashboards"
  Network    = "$GflRoot\Network"
  Android    = "$GflRoot\Android"
  ISO        = "$GflRoot\ISO"
  Staging    = "$GflRoot\Staging"
  Output     = "$GflRoot\Output"
}
$LogFile = "$($Dirs.Logs)\mega-core.log"
function Log([string]$t){ $ts=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); $line="[$ts] $t"; if(-not $DryRun){ New-Item -ItemType Directory -Force -Path $Dirs.Logs -EA SilentlyContinue | Out-Null; Add-Content -Path $LogFile -Value $line }; Say $t }

# ─────────────────────────────────────────────────────────────────────────────
# Folder structure & Core Tools
# ─────────────────────────────────────────────────────────────────────────────
function New-GFLStructure {
  Say 'Creating GFL folder structure…' Cyan
  foreach($k in $Dirs.Keys){ $path = $Dirs[$k]; if(-not (Test-Path $path)){ if($DryRun){ Say "[Dry] New-Item $path" DarkGray } else { New-Item -ItemType Directory -Force -Path $path | Out-Null; Log "Created: $path" } } }
}

function Ensure-Tool {
  param(
    [Parameter(Mandatory)] [string]$Name,
    [string]$WingetId,
    [string]$ChocoId,
    [string]$PostCheckCmd
  )
  if(Get-Command $Name){ Log "$Name present"; return $true }
  Say "$Name not found. Attempting install…" Yellow
  $wg = Get-Command 'winget'
  if($wg -and $WingetId){ try{ if(-not $DryRun){ & $wg install -e --id $WingetId --accept-source-agreements --accept-package-agreements | Out-Null }; Log "winget installed $Name" }catch{ Log "winget failed $Name: $($_.Exception.Message)" } }
  if((Get-Command $Name) -eq $null -and $ChocoId){ $ch=Get-Command 'choco'; if($ch){ try{ if(-not $DryRun){ & $ch install $ChocoId -y --no-progress | Out-Null }; Log "choco installed $Name" }catch{ Log "choco failed $Name: $($_.Exception.Message)" } } }
  if($PostCheckCmd){ try{ if(-not $DryRun){ Invoke-Expression $PostCheckCmd | Out-Null } }catch{} }
  if(Get-Command $Name){ Log "$Name ready"; return $true } else { Say "Could not install $Name automatically. Install manually later." Red; return $false }
}

function Ensure-CoreTools {
  Say 'Checking core tools…' Cyan
  $ok = @()
  $ok += Ensure-Tool -Name 'pwsh'   -WingetId 'Microsoft.PowerShell'                    -ChocoId 'powershell'
  $ok += Ensure-Tool -Name '7z'     -WingetId '7zip.7zip'                                -ChocoId '7zip'
  $ok += Ensure-Tool -Name 'git'    -WingetId 'Git.Git'                                  -ChocoId 'git'
  $ok += Ensure-Tool -Name 'rclone' -WingetId 'Rclone.Rclone'                            -ChocoId 'rclone'
  $ok += Ensure-Tool -Name 'curl'   -WingetId 'GnuWin32.Curl'                            -ChocoId 'curl'
  $ok += Ensure-Tool -Name 'adb'    -WingetId 'Google.AndroidSDK.PlatformTools'          -ChocoId 'adb'
  $ok += Ensure-Tool -Name 'ffmpeg' -WingetId 'Gyan.FFmpeg'                              -ChocoId 'ffmpeg'
  $ok += Ensure-Tool -Name 'aria2c' -WingetId 'aria2.aria2'                              -ChocoId 'aria2'
  if($ok -notcontains $false){ Log 'All core tools present or attempted.' }
}

# ─────────────────────────────────────────────────────────────────────────────
# Configs
# ─────────────────────────────────────────────────────────────────────────────
$WalletConfigPath = "$($Dirs.Config)\wallets.json"
$AppConfigPath    = "$($Dirs.Config)\appsettings.json"

$DefaultWallets = [ordered]@{
  BTC  = 'bc1qcgy276lwmmp78h4gu4kv5psfa9drshmx574q0c'
  ETH  = '0x923A68317A182cC9E6a5ad490d8641759BD94eFe'
  ETHF = '0x8d23E729de7030EE845bC09CC80E404C4Ea4AD61'
  BNB  = '0x923A68317A182cC9E6a5ad490d8641759BD94eFe'
  LTC  = 'ltc1qrkr2ny5gj82ckl5vqj6g5fvm3cmg6wn8g94dj2'
  XRP  = 'rhWZfEpj6syq55AGVRdn1z1VGurEVoFUBJ'
  SOL  = 'ED1Qqr9fERPF4GmJRy6CDH7E37dGEUMSBRzmM5nu4XsC'
  TRX  = 'TNdV8iT1zcr4EaQkMLUXbvLyyAqMMRaAjT'
  DOGE = 'DCii7et1Vbtjf19ASxGniJtxKB9V9qWZq4'
}

$DefaultAppSettings = [ordered]@{
  Commander = 'Commander Grego'
  HyphenNaming = $true
  AutoUpdateMinutes = 10
  LogsKeepDays = 14
  Dashboards = @{ Enabled = $true; Port = 8080 }
  AndroidBridge = @{ WifiEnabled = $true; CableAutoDetect = $true }
  ISO = @{ SplitMB = 500; MaxParts = 50 }
}

function Write-Json($obj,$path){ $json=($obj|ConvertTo-Json -Depth 8); if(-not $DryRun){ $json | Out-File -FilePath $path -Encoding utf8 }; Log "Wrote JSON: $path" }

function Ensure-Configs {
  Say 'Writing base configs…' Cyan
  if(-not (Test-Path $WalletConfigPath)){ Write-Json $DefaultWallets $WalletConfigPath } else { Log 'wallets.json exists (left as is).' }
  if(-not (Test-Path $AppConfigPath)){ Write-Json $DefaultAppSettings $AppConfigPath } else { Log 'appsettings.json exists (left as is).' }
}

# ─────────────────────────────────────────────────────────────────────────────
# Scheduled Tasks
# ─────────────────────────────────────────────────────────────────────────────
function Register-GFLTask {
  param([string]$Name,[string]$Script,[int]$Minutes=10,[switch]$Enabled)
  if(-not (Test-Admin)) { Say "Register-GFLTask requires Admin. Skipping $Name." Yellow; return }
  $taskName = "GFL-$Name"
  $action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$Script`""
  $trig = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
  $trig.Repetition = New-ScheduledTaskRepetitionSettings -Interval (New-TimeSpan -Minutes $Minutes) -Duration ([TimeSpan]::MaxValue)
  if(-not $DryRun){ Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trig -RunLevel Highest -Force | Out-Null }
  Log "Scheduled task $taskName registered (every $Minutes min). Enabled=$Enabled"
}

# ─────────────────────────────────────────────────────────────────────────────
# ISO + ZIP helpers
# ─────────────────────────────────────────────────────────────────────────────
function Split-File7z {
  param([Parameter(Mandatory)][string]$Source,[int]$PartMB=500,[string]$OutDir)
  $OutDir = $OutDir ?? $Dirs.Output
  if(-not (Test-Path $Source)){ throw "Source not found: $Source" }
  if(-not (Test-Path $OutDir)){ New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
  $cmd = "7z a -v${PartMB}m -mx=1 `"$OutDir\$(Split-Path $Source -Leaf).7z`" `"$Source`""
  if($DryRun){ Say "[Dry] $cmd" DarkGray } else { & cmd /c $cmd | Out-Null }
  Log "Split complete → $OutDir"
}

function Extract-All7z {
  param([Parameter(Mandatory)][string]$FromDir,[string]$ToDir)
  $ToDir = $ToDir ?? $Dirs.Staging
  if(-not (Test-Path $ToDir)){ New-Item -ItemType Directory -Force -Path $ToDir | Out-Null }
  Get-ChildItem -Path $FromDir -Filter '*.7z*' -File | ForEach-Object {
    $cmd = "7z x -y -o`"$ToDir`" `"$($_.FullName)`""
    if($DryRun){ Say "[Dry] $cmd" DarkGray } else { & cmd /c $cmd | Out-Null }
    Log "Extracted: $($_.Name)"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Android & FTP Bridges (stubs)
# ─────────────────────────────────────────────────────────────────────────────
function Android-Bridge {
  Say 'Android bridge: basic checks…' Cyan
  $adb = Get-Command 'adb'
  if(-not $adb){ Say 'adb missing; install via Tools step.' Yellow; return }
  try{ & adb devices | Out-Null; Log 'adb devices executed.' }catch{ Say 'adb error. Check USB debugging + drivers.' Red }
  Say 'Tip: Enable USB debugging + (optional) Wireless debugging in Developer options.' DarkGray
}

function FTP-Bridge {
  Say 'FTP bridge: installing FileZilla (if available)…' Cyan
  $ok = Ensure-Tool -Name 'filezilla-server' -WingetId 'FileZilla.Server' -ChocoId 'filezilla.server'
  if($ok){ Log 'FileZilla Server available. Configure users/ports in its UI.' } else { Say 'Skipped FTP server: installer not found.' Yellow }
}

# ─────────────────────────────────────────────────────────────────────────────
# Dashboard (static) seed files
# ─────────────────────────────────────────────────────────────────────────────
$DashIndex = @'
<!doctype html>
<html><head><meta charset="utf-8"/><title>GFL Dashboard</title>
<style>body{font-family:Segoe UI,Arial;max-width:900px;margin:40px auto} .card{padding:16px;border:1px solid #ddd;border-radius:12px;margin:12px 0}
small{color:#666}</style></head>
<body>
<h1>GFL Dashboard — Basics</h1>
<div class="card"><b>Status</b><br/><small>Bootstrap OK. Tools, configs, and folders are ready if green below.</small><pre id="status"></pre></div>
<div class="card"><b>Paths</b><pre id="paths"></pre></div>
<script>
fetch('status.json').then(r=>r.json()).then(j=>{ document.getElementById('status').textContent = JSON.stringify(j,null,2); });
fetch('paths.json').then(r=>r.json()).then(j=>{ document.getElementById('paths').textContent = JSON.stringify(j,null,2); });
</script>
</body></html>
'@

function Install-DashboardBasics {
  $root = $Dirs.Dashboards
  if(-not (Test-Path $root)){ New-Item -ItemType Directory -Force -Path $root | Out-Null }
  ($DashIndex) | Out-File -FilePath (Join-Path $root 'index.html') -Encoding utf8
  $statusObj = @{ time=(Get-Date); tools=@{ pwsh=!!(Get-Command 'pwsh'); _7z=!!(Get-Command '7z'); git=!!(Get-Command 'git'); rclone=!!(Get-Command 'rclone'); adb=!!(Get-Command 'adb'); aria2=!!(Get-Command 'aria2c') } }
  ($statusObj | ConvertTo-Json -Depth 4) | Out-File -FilePath (Join-Path $root 'status.json') -Encoding utf8
  ($Dirs | ConvertTo-Json -Depth 4) | Out-File -FilePath (Join-Path $root 'paths.json') -Encoding utf8
  Log 'Dashboard basics written to Dashboards\'
}

# ─────────────────────────────────────────────────────────────────────────────
# Auto‑Heal (basic + advanced)
# ─────────────────────────────────────────────────────────────────────────────
function Auto-HealBasics {
  Say 'Running basic self‑check…' Cyan
  $checks = @()
  foreach($k in $Dirs.Keys){ $checks += [pscustomobject]@{ Path=$Dirs[$k]; Exists=(Test-Path $Dirs[$k]) } }
  $checks += [pscustomobject]@{ Tool='pwsh'; Present= !!(Get-Command 'pwsh') }
  $checks += [pscustomobject]@{ Tool='7z';   Present= !!(Get-Command '7z') }
  $checks += [pscustomobject]@{ Tool='git';  Present= !!(Get-Command 'git') }
  $checks | ConvertTo-Json -Depth 5 | Out-File -FilePath (Join-Path $Dirs.Logs 'selfcheck.json') -Encoding utf8
  Log 'Selfcheck written → Logs\selfcheck.json'
}

function Auto-HealAdvanced {
  Say 'Auto‑Heal Advanced: scanning…' Cyan
  $report = [ordered]@{ time=(Get-Date); dirs=@{}; tools=@{}; notes=@() }
  foreach($k in $Dirs.Keys){
    $p = $Dirs[$k]
    $count = (Get-ChildItem -Path $p -Recurse -EA SilentlyContinue | Measure-Object).Count
    $report.dirs[$k] = @{ path=$p; exists=(Test-Path $p); items=$count }
  }
  foreach($t in 'pwsh','7z','git','rclone','adb','aria2c'){
    $report.tools[$t] = @{ present = !!(Get-Command $t) }
  }
  $orphans = @()
  $orphans += Get-ChildItem -Path $GflRoot -Recurse -Include '*.tmp','*.bak' -EA SilentlyContinue
  $report.notes += "Orphans candidates: $($orphans.Count) files (preview only)"
  $json = $report | ConvertTo-Json -Depth 8
  $json | Out-File -FilePath (Join-Path $Dirs.Logs 'autoheal-advanced.json') -Encoding utf8
  Log 'Auto‑Heal Advanced report written.'
}

# ─────────────────────────────────────────────────────────────────────────────
# HTTP Dashboard Server (HttpListener)
# ─────────────────────────────────────────────────────────────────────────────
function Start-GFLDashboardServer {
  param(
    [int]$Port = 8080,
    [string]$Root = $Dirs.Dashboards,
    [switch]$VerboseLog
  )
  if(-not ([System.Net.HttpListener]::IsSupported)) { throw 'HttpListener not supported on this OS.' }
  $prefix = "http://localhost:$Port/"
  $listener = [System.Net.HttpListener]::new()
  $listener.Prefixes.Add($prefix)
  try { $listener.Start(); Say "Dashboard listening on $prefix" Green }
  catch { throw "Could not start listener on $prefix — try another port or run as Admin." }

  function Send-Resp([System.Net.HttpListenerResponse]$resp,[byte[]]$bytes,[string]$mime){
    $resp.ContentType = $mime
    $resp.ContentLength64 = $bytes.Length
    $out = $resp.OutputStream
    $out.Write($bytes,0,$bytes.Length)
    $out.Close()
  }

  $mime = @{ '.html'='text/html'; '.json'='application/json'; '.js'='application/javascript'; '.css'='text/css'; '.png'='image/png'; '.ico'='image/x-icon' }

  if(-not (Test-Path (Join-Path $Root 'index.html'))){ Install-DashboardBasics }

  while($listener.IsListening){
    try {
      $ctx = $listener.GetContext()
      $req = $ctx.Request
      $res = $ctx.Response
      if($VerboseLog){ Log "HTTP ${($req.HttpMethod)} ${($req.Url.AbsolutePath)}" }

      $path = $req.Url.AbsolutePath.TrimStart('/')

      switch -Regex ($path){
        '^$' { $path = 'index.html' }
        '^api/status$' {
          $status = @{ time=(Get-Date); tools=@{ pwsh=!!(Get-Command 'pwsh'); _7z=!!(Get-Command '7z'); git=!!(Get-Command 'git'); rclone=!!(Get-Command 'rclone'); adb=!!(Get-Command 'adb'); aria2=!!(Get-Command 'aria2c') } ; dirs=$Dirs }
          $bytes = [Text.Encoding]::UTF8.GetBytes(($status | ConvertTo-Json -Depth 6))
          Send-Resp $res $bytes 'application/json'
          continue
        }
        '^api/logs/selfcheck$' {
          $file = Join-Path $Dirs.Logs 'selfcheck.json'
          if(Test-Path $file){ $bytes = [IO.File]::ReadAllBytes($file); Send-Resp $res $bytes 'application/json' } else { $res.StatusCode=404; Send-Resp $res ([Text.Encoding]::UTF8.GetBytes('{"error":"no selfcheck"}')) 'application/json' }
          continue
        }
        default {
          $full = Join-Path $Root $path
          if(Test-Path $full -PathType Leaf){
            $ext = [IO.Path]::GetExtension($full).ToLower()
            $mt  = $mime[$ext]; if(-not $mt){ $mt='application/octet-stream' }
            $bytes = [IO.File]::ReadAllBytes($full)
            Send-Resp $res $bytes $mt
          }
          else {
            $res.StatusCode = 404
            Send-Resp $res ([Text.Encoding]::UTF8.GetBytes('<h1>404</h1>')) 'text/html'
          }
        }
      }
    } catch {
      try{ $ctx.Response.StatusCode = 500; $msg=[Text.Encoding]::UTF8.GetBytes('internal error'); $ctx.Response.OutputStream.Write($msg,0,$msg.Length); $ctx.Response.OutputStream.Close() }catch{}
      Log "HTTP error: $($_.Exception.Message)"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Auto‑Updater (foreground loop) + Scheduled task helper
# ─────────────────────────────────────────────────────────────────────────────
function Start-GFLAutoUpdater {
  param([int]$Minutes = 10)
  Say "Auto‑Updater loop every $Minutes minute(s). Press Ctrl+C to exit." Cyan
  while($true){
    try{
      Log 'Updater tick: Self‑heal basics…'
      Auto-HealBasics
      $repo = Join-Path $GflRoot 'Repo'
      if(Test-Path $repo){
        try{ Push-Location $repo; git pull | Out-Null; Pop-Location; Log 'Repo pulled.' }catch{ Log "Git pull failed: $($_.Exception.Message)" }
      }
      Install-DashboardBasics
    }catch{ Log "Updater tick error: $($_.Exception.Message)" }
    Start-Sleep -Seconds ([int]([TimeSpan]::FromMinutes($Minutes)).TotalSeconds)
  }
}
function Enable-GFLAutoUpdaterTask { Register-GFLTask -Name 'AutoUpdater' -Script (Join-Path $Dirs.Scripts 'GFL-Mega-Core.ps1') -Minutes ((Get-Content $AppConfigPath | ConvertFrom-Json).AutoUpdateMinutes) -Enabled }

# ─────────────────────────────────────────────────────────────────────────────
# Miner / Trader Bridge stubs
# ─────────────────────────────────────────────────────────────────────────────
function Run-GFLMinerBridge {
  param([string]$ConfigJson = $WalletConfigPath)
  Say 'MinerBridge: starting (stub)…' Cyan
  $w = Get-Content $ConfigJson | ConvertFrom-Json
  Log "MinerBridge using BTC=$($w.BTC) ETH=$($w.ETH) ETHF=$($w.ETHF)"
  $tick=0; while($tick -lt 3){ Log "Miner tick $tick (stub)"; Start-Sleep 3; $tick++ }
  Say 'MinerBridge: stop (stub).' DarkGray
}
function Run-GFLTraderBridge {
  param([string]$ConfigJson = $WalletConfigPath)
  Say 'TraderBridge: starting (stub)…' Cyan
  $w = Get-Content $ConfigJson | ConvertFrom-Json
  Log "TraderBridge using wallets loaded; connecting to exchanges (placeholder)."
  $tick=0; while($tick -lt 3){ Log "Trader tick $tick (stub)"; Start-Sleep 3; $tick++ }
  Say 'TraderBridge: stop (stub).' DarkGray
}

# ─────────────────────────────────────────────────────────────────────────────
# Rclone sync helpers
# ─────────────────────────────────────────────────────────────────────────────
function Run-GFLRcloneSync {
  param(
    [string]$Remote = 'gdrive:',
    [string]$LocalPath = $GflRoot,
    [switch]$Upload,
    [switch]$Download
  )
  $r = Get-Command 'rclone'
  if(-not $r){ Say 'rclone missing; run Tools step.' Yellow; return }
  if($Upload){
    $cmd = "rclone sync `"$LocalPath`" `"$Remote/GFL-System`" --transfers=4 --checkers=8 --fast-list --log-file=`"$($Dirs.Logs)\rclone-upload.log`" --log-level INFO"
  } elseif($Download){
    $cmd = "rclone sync `"$Remote/GFL-System`" `"$LocalPath`" --transfers=4 --checkers=8 --fast-list --log-file=`"$($Dirs.Logs)\rclone-download.log`" --log-level INFO"
  } else {
    Say 'Specify -Upload or -Download' Yellow; return
  }
  Say "Rclone: $cmd" DarkGray
  if(-not $DryRun){ & cmd /c $cmd }
  Log 'Rclone sync job finished.'
}

# ─────────────────────────────────────────────────────────────────────────────
# One‑click launcher
# ─────────────────────────────────────────────────────────────────────────────
function Write-Launchers {
  $bat = @(
    '@echo off',
    'pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Scripts\\GFL-Mega-Core.ps1" -Everything',
    'pause'
  ) -join "`r`n"
  $file = Join-Path $GflRoot 'GFL-Launch-All.bat'
  $bat | Out-File -FilePath $file -Encoding ascii
  Log "Launcher written: $file"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN FLOW
# ─────────────────────────────────────────────────────────────────────────────
$doAllBasics = $Everything -or ($DoSetup -or $DoTools -or $DoConfigs -or $DoAutostart -or $DoISO -or $DoAndroidBridge -or $DoFTPBridge -or $DoDashboard -or $DoAutoHeal) -eq $false

try{
  Say '— GFL‑Mega‑Core: START —' Green
  if($doAllBasics -or $DoSetup){ New-GFLStructure }
  if($doAllBasics -or $DoTools){ Ensure-CoreTools }
  if($doAllBasics -or $DoConfigs){ Ensure-Configs }
  if($doAllBasics -or $DoDashboard){ Install-DashboardBasics }
  if($DoISO){ Say 'ISO basics ready (use Split-File7z, Extract-All7z functions).' }
  if($DoAndroidBridge){ Android-Bridge }
  if($DoFTPBridge){ FTP-Bridge }
  if($doAllBasics -or $DoAutoHeal){ Auto-HealBasics }
  Write-Launchers
  Log 'Basics complete.'

  if($Everything){
    # Start dashboard server (non-blocking via Start-Job is avoided to keep single-file simplicity)
    try { $cfg = Get-Content $AppConfigPath | ConvertFrom-Json; Start-GFLDashboardServer -Port $cfg.Dashboards.Port } catch { Log "Dashboard server error: $($_.Exception.Message)" }
    try { Auto-HealAdvanced } catch { Log "AutoHeal advanced err: $($_.Exception.Message)" }
    try { Run-GFLMinerBridge } catch { Log $_.Exception.Message }
    try { Run-GFLTraderBridge } catch { Log $_.Exception.Message }
  }

  Say '— GFL‑Mega‑Core: READY —' Green
  Say ("Root: " + $GflRoot) DarkGray
  Say ("Log : " + $LogFile) DarkGray

}catch{
  Say ("ERROR: " + $_.Exception.Message) Red
  Log ("ERROR: " + $_.ToString())
  exit 1
}

# Convenience flags after main parameter block (invoke script with these switches):
param(
  [switch]$RunDashboard,
  [switch]$RunUpdater,
  [switch]$RunMiner,
  [switch]$RunTrader,
  [switch]$RcloneUpload,
  [switch]$RcloneDownload,
  [switch]$BuildApk
)

if($RunDashboard){ $cfg = Get-Content $AppConfigPath | ConvertFrom-Json; Start-GFLDashboardServer -Port $cfg.Dashboards.Port }
if($RunUpdater){ $cfg = Get-Content $AppConfigPath | ConvertFrom-Json; Start-GFLAutoUpdater -Minutes $cfg.AutoUpdateMinutes }
if($RunMiner){ Run-GFLMinerBridge }
if($RunTrader){ Run-GFLTraderBridge }
if($RcloneUpload){ Run-GFLRcloneSync -Upload }
if($RcloneDownload){ Run-GFLRcloneSync -Download }
if($BuildApk){
  # Simple stub artifact writer
  $out = Join-Path $Dirs.Output 'GFL-OS-stub.apk'
  if(-not (Test-Path $Dirs.Output)){ New-Item -ItemType Directory -Force -Path $Dirs.Output | Out-Null }
  Set-Content -Path $out -Value 'This is a placeholder APK file (not installable). Replace with real build output.'
  Log "APK stub written: $out"
}























































