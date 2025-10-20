[CmdletBinding()]
param(
  [switch]$Run,
  [switch]$InstallHourly,
  [switch]$DryRun,
  [switch]$ForceClean,
  [switch]$IncludeLibraBalance,
  [string]$Channel='stable'
)

$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

# Paths
$Root='C:\GFL-System'
$Scripts=Join-Path $Root 'Scripts'
$Configs=Join-Path $Root 'Configs'
$Manifests=Join-Path $Root 'Manifests'
$Reports=Join-Path $Root 'Reports'
$Logs=Join-Path $Reports 'logs'
$Artifacts=Join-Path $Reports 'artifacts'
$Tmp=Join-Path $Reports 'tmp'
$null = New-Item -ItemType Directory -Force -Path $Manifests,$Reports,$Logs,$Artifacts,$Tmp -ErrorAction SilentlyContinue

# Logging / JSON
$LogFile=Join-Path $Logs ("fullupdate-{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))
function Write-Log($m,[string]$lvl='INFO'){ $ts=(Get-Date).ToString('s'); ("[{0}] [{1}] {2}" -f $ts,$lvl,$m) | Tee-Object -FilePath $LogFile -Append }
function Load-Json($p){ if(Test-Path $p){ try{ (Get-Content $p -Raw)|ConvertFrom-Json }catch{ $null } } }
function Save-Json($o,$p){ $o|ConvertTo-Json -Depth 10|Set-Content $p -Encoding UTF8 }

# Helpers
function Get-PreferredShell { $pw = Get-Command pwsh -ErrorAction SilentlyContinue; if($pw){return $pw.Source} (Get-Command powershell -ErrorAction SilentlyContinue).Source }
function Ping-Dashboard($note){ try{ Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 -Uri ("http://localhost:8791/api/status/ping?msg={0}" -f [Uri]::EscapeDataString($note))|Out-Null }catch{} }

function Invoke-HttpGet([string]$url,[string]$outFile){
  Write-Log ("Downloading: {0} -> {1}" -f $url,$outFile)
  if ($DryRun) { return $true }
  try {
    if ($url -match '^(?i)file://') { $p = [Uri]$url; Copy-Item $p.LocalPath -Destination $outFile -Force; return (Test-Path $outFile) }
    elseif (Test-Path $url)        { Copy-Item $url -Destination $outFile -Force; return (Test-Path $outFile) }
    else                           { Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing -TimeoutSec 3600; return (Test-Path $outFile) }
  } catch { Write-Log ("Download error: {0}" -f $_) 'WARN'; return $false }
}

function SHA256([string]$file){ if(!(Test-Path $file)){return $null}; $sha=[System.Security.Cryptography.SHA256]::Create(); $fs=[IO.File]::OpenRead($file); try{ ($sha.ComputeHash($fs)|ForEach-Object{ $_.ToString('x2') }) -join '' } finally{ $fs.Dispose(); $sha.Dispose() } }

function Expand-ArchiveAny([string]$archive,[string]$dest){
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  $ext=[IO.Path]::GetExtension($archive).ToLowerInvariant()
  if($DryRun){ Write-Log ("DryExpand {0} -> {1}" -f $archive,$dest); return }
  if($ext -eq '.zip'){
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($archive,$dest,$true)
  } elseif($ext -in @('.7z','.rar')){
    $cmd=Get-Command 7z -ErrorAction SilentlyContinue
    if(-not $cmd){ throw ("7z not found for {0}" -f $archive) }
    & $cmd.Source x '-y' ("-o{0}" -f $dest) $archive | Out-Null
  } else {
    Copy-Item $archive -Destination $dest -Force
  }
}

function Safe-SwapDir([string]$stagedDir,[string]$liveDir){
  Write-Log ("Safe swap: {0} -> {1}" -f $stagedDir,$liveDir)
  if($DryRun){ return }
  $parent   = Split-Path $liveDir -Parent
  $liveName = Split-Path $liveDir -Leaf
  $backup   = Join-Path $parent ($liveName + ".bak")

  if(-not (Test-Path $parent)){ New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  if(Test-Path $backup){ Remove-Item $backup -Recurse -Force -ErrorAction SilentlyContinue }
  if(Test-Path $liveDir){ Rename-Item -Path $liveDir -NewName ($liveName + ".bak") -Force }

  Move-Item -Path $stagedDir -Destination $liveDir -Force

  if(Test-Path $backup){ Remove-Item $backup -Recurse -Force -ErrorAction SilentlyContinue }
}

function Stop-GflServices{ Write-Log "Stopping GFL micro servers / jobs (best-effort)"; try{ Get-Job | ?{ $_.Name -like 'GFL-*' } | Stop-Job -Force -ErrorAction SilentlyContinue }catch{} }
function Start-GflServers{
  Write-Log "Starting AutoPulse & Panel-Tasks"
  $sh = Get-PreferredShell
  $ap=Join-Path $Scripts 'GFL-AutoPulse.ps1'
  $pt=Join-Path $Scripts 'GFL-Panel-Tasks.ps1'
  if(Test-Path $ap){ Start-Process $sh -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$ap,'-StartDashboard') -WindowStyle Hidden }
  Start-Sleep -Seconds 2
  if(Test-Path $pt){ Start-Process $sh -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$pt,'-StartServerOnly') -WindowStyle Hidden }
}

function Bump-Manifest([string]$component,[string]$newVersion){
  $mfPath=Join-Path $Manifests 'manifest.json'
  $mf=Load-Json $mfPath
  if(-not $mf){ $mf=[pscustomobject]@{ version='0.0.0'; components=@{} } }

  # force components -> hashtable
  if(-not $mf.PSObject.Properties.Name -contains 'components'){
    $mf | Add-Member -NotePropertyName components -NotePropertyValue @{} -Force
  }
  if(-not ($mf.components -is [System.Collections.IDictionary])){
    $ht=@{}
    if($mf.components){
      foreach($p in $mf.components.PSObject.Properties){ $ht[$p.Name]=$p.Value }
    }
    $mf.components = $ht
  }

  $mf.components[$component] = $newVersion
  $mf.version = (Get-Date -Format 'yyyy.MM.dd.HHmm')
  Save-Json $mf $mfPath
  Write-Log ("Manifest updated: {0}={1}" -f $component,$newVersion)
}

function Run-PostScript([string]$scriptPath){
  if([string]::IsNullOrWhiteSpace($scriptPath)){ return }
  if(Test-Path $scriptPath){
    Write-Log ("Running post-update script: {0}" -f $scriptPath)
    if(-not $DryRun){
      $sh = Get-PreferredShell
      & $sh -NoProfile -ExecutionPolicy Bypass -File $scriptPath
    }
  } else { Write-Log ("Post script not found: {0}" -f $scriptPath) 'WARN' }
}

# Sources (create default if missing)
$SourcesFile=Join-Path $Configs 'update-sources.json'
$Sources=Load-Json $SourcesFile
if(-not $Sources){
  $Sources=[pscustomobject]@{
    gfl_os    = [pscustomobject]@{ urls=@("C:\GFL-System\Test\GFL-OS.zip");     sha256="" }
    righteous = [pscustomobject]@{ urls=@("C:\GFL-System\Test\RighteousAI.zip"); sha256="" }
    post      = [pscustomobject]@{ script = "C:\GFL-System\Scripts\post-update.ps1" }
  }
  Save-Json $Sources $SourcesFile
  Write-Log "Created default update-sources.json (local test)." 'WARN'
}

function Apply-Package{
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string[]]$Urls,
    [string]$Sha256="",
    [Parameter(Mandatory=$true)][string]$TargetDir
  )
  $work=Join-Path $Tmp ("{0}-{1}" -f $Name,(Get-Date -Format 'yyyyMMddHHmmss'))
  $dl=Join-Path $work 'dl'; $stg=Join-Path $work 'stage'
  New-Item -ItemType Directory -Force -Path $work,$dl,$stg | Out-Null

  $payload=Join-Path $dl "$Name.pkg"; $downloaded=$false
  foreach($u in $Urls){ try{ if(Invoke-HttpGet $u $payload){ $downloaded=$true; break } }catch{ Write-Log ("Download failed {0} : {1}" -f $u,$_ ) 'WARN' } }
  if(-not $downloaded){ throw ("No reachable URL for {0}" -f $Name) }

  if($Sha256 -and $Sha256.Trim().Length -gt 0){
    $actual=SHA256 $payload
    if($actual -ne $Sha256.ToLower()){ throw ("SHA256 mismatch for {0}. Expected={1}, Actual={2}" -f $Name,$Sha256,$actual) }
    Write-Log ("{0} hash OK" -f $Name)
  } else { Write-Log ("{0} hash not provided; continuing" -f $Name) 'WARN' }

  Expand-ArchiveAny $payload $stg

  if(-not (Test-Path (Split-Path $TargetDir -Parent))){ New-Item -ItemType Directory -Force -Path (Split-Path $TargetDir -Parent) | Out-Null }
  if($ForceClean -and (Test-Path $TargetDir)){
    Write-Log ("ForceClean: {0}" -f $TargetDir)
    if(-not $DryRun){ Get-ChildItem $TargetDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
  }
  Safe-SwapDir $stg $TargetDir

  try{
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
    $zip=Join-Path $Artifacts ("{0}-applied-{1}.zip" -f $Name,$stamp)
    if(-not $DryRun){
      Add-Type -AssemblyName System.IO.Compression.FileSystem
      [IO.Compression.ZipFile]::CreateFromDirectory($TargetDir,$zip)
    }
    Write-Log ("{0} artifact stored: {1}" -f $Name,$zip)
  }catch{
    Write-Log ("Artifact save error for {0}: {1}" -f $Name,$_ ) 'WARN'
  }
}

function Invoke-FullUpdate{
  Write-Log "=== GFL Full Update Start ==="
  Stop-GflServices

  $gflUrls = @(); if($Sources.gfl_os.urls){ $gflUrls += $Sources.gfl_os.urls }
  if($gflUrls.Count -eq 0){ throw "No GFL OS URLs configured" }
  Apply-Package -Name 'gfl_os' -Urls $gflUrls -Sha256 ($Sources.gfl_os.sha256) -TargetDir (Join-Path $Root 'GFL-OS')

  $raiUrls = @(); if($Sources.righteous.urls){ $raiUrls += $Sources.righteous.urls }
  if($raiUrls.Count -eq 0){ throw "No Righteous AI URLs configured" }
  Apply-Package -Name 'righteous' -Urls $raiUrls -Sha256 ($Sources.righteous.sha256) -TargetDir (Join-Path $Root 'AI\RighteousAI')

  Bump-Manifest 'gfl_os' (Get-Date -Format 'yyyy.MM.dd')
  Bump-Manifest 'righteous' (Get-Date -Format 'yyyy.MM.dd')

  if($Sources.post -and $Sources.post.script){ 
    if(Test-Path $Sources.post.script){ & (Get-PreferredShell) -NoProfile -ExecutionPolicy Bypass -File $Sources.post.script }
  }

  Start-GflServers
  Write-Log "=== GFL Full Update End ==="
}

function Install-HourlyTask{
  $taskName='GFL Full AutoUpdate (Hourly)'
  $sh = Get-PreferredShell
  $args="-NoProfile -ExecutionPolicy Bypass -File `"$Scripts\GFL-FullAutoUpdate.ps1`" -Run"
  try{
    $act=New-ScheduledTaskAction -Execute $sh -Argument $args
    $trig=New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
    Register-ScheduledTask -TaskName $taskName -Action $act -Trigger $trig -Description "Updates GFL OS + Righteous AI hourly" -User "$env:UserName" -RunLevel Highest -Force | Out-Null
    Write-Log ("Scheduled task installed: {0}" -f $taskName)
  }catch{ Write-Log ("Failed to install scheduled task: {0}" -f $_) 'WARN' }
}

try{
  if($InstallHourly){ Install-HourlyTask }
  if($Run){ Invoke-FullUpdate }
  elseif(-not $InstallHourly){
    Write-Log "Nothing to do. Use -Run or -InstallHourly."
    Write-Host "Usage:`n  pwsh -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Run`n  pwsh -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -InstallHourly"
  }
}catch{
  Write-Log ("FATAL: {0}" -f $_.Exception.Message) 'ERROR'
  throw
}
