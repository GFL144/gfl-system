<# =====================================================================
 GFL-Multi-Fix-Orchestrator.ps1  (PS5/PS7 safe)
 ===================================================================== #>

[CmdletBinding()]
param(
  [switch]$All,
  [switch]$Scan,
  [switch]$Repair,
  [switch]$Download,
  [switch]$Upload,
  [switch]$AndroidSync,
  [switch]$DryRun,

  # Paths / endpoints
  [string]$MirrorListPath = 'C:\GFL-System\Manifests\mirrors.txt',
  [string]$ManifestPath   = 'C:\GFL-System\Manifests\core-manifest.json',

  # Upload targets (use rclone if configured)
  [string]$RcloneRemote   = 'gfl-remote:reports',
  [string]$SftpHost       = 'sftp.example.com',
  [int]   $SftpPort       = 22,
  [string]$SftpUser       = 'gfl',
  [string]$SftpPass       = '',
  [string]$SftpRemoteDir  = '/uploads/reports',
  [string]$FtpHost        = 'ftp.example.com',
  [int]   $FtpPort        = 21,
  [string]$FtpUser        = 'gfl',
  [string]$FtpPass        = '',
  [string]$FtpRemoteDir   = '/uploads/reports',

  # Android bridge (optional)
  [string]$AndroidPushDir = '/sdcard/GFL-System/updates'
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$GflRoot   = 'C:\GFL-System'
$Scripts   = Join-Path $GflRoot 'Scripts'
$Reports   = Join-Path $GflRoot 'Reports'
$LogsDir   = Join-Path $Reports 'logs'
$Artifacts = Join-Path $Reports 'artifacts'
$Tmp       = Join-Path $GflRoot 'Staging'
$Health    = Join-Path $Reports 'health'
$LogFile   = Join-Path $Reports 'multi-fix.log'
$JsonOut   = Join-Path $Reports 'multi-fix.json'

$null = New-Item -ItemType Directory -Force -Path $GflRoot,$Scripts,$Reports,$LogsDir,$Artifacts,$Tmp,$Health

function Write-Log {
  param([string]$msg,[string]$level='INFO')
  $line = ('[{0}] {1}: {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $level, $msg)
  $line | Tee-Object -FilePath $LogFile -Append
}

function Ensure-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Log "Elevation required; relaunching as admin..." "WARN"
    $exe = if ($PSVersionTable.PSVersion.Major -ge 7) { 'pwsh' } else { 'powershell' }
    Start-Process $exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $($MyInvocation.UnboundArguments -join ' ')"
    exit
  }
}

function Get-Command { param([string]$Name) Get-Command $Name -ErrorAction SilentlyContinue }

$HaveAria2  = [bool](Get-Command 'aria2c')
$HaveRclone = [bool](Get-Command 'rclone')
$HaveAdb    = [bool](Get-Command 'adb')

function Invoke-Download {
  param(
    [Parameter(Mandatory)] [string]$Url,
    [Parameter(Mandatory)] [string]$OutFile
  )
  Write-Log "Download: $Url -> $OutFile"
  if ($DryRun) { return $true }
  New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null

  if ($HaveAria2) {
    $args = @('--max-connection-per-server=8','--min-split-size=1M','--file-allocation=none','--allow-overwrite=true',
              '-d',(Split-Path $OutFile),'-o',(Split-Path -Leaf $OutFile), $Url)
    $p = Start-Process aria2c -ArgumentList $args -Wait -PassThru
    return ($p.ExitCode -eq 0)
  }

  try {
    Ensure-Admin
    $job = Start-BitsTransfer -Source $Url -Destination $OutFile -Asynchronous -Priority Foreground
    while ($job.JobState -in 'Connecting','Transferring') { Start-Sleep -Milliseconds 300; $job = Get-BitsTransfer -Id $job.Id }
    if ($job.JobState -eq 'Transferred') { Complete-BitsTransfer -BitsJob $job; return $true }
    throw "BITS state: $($job.JobState)"
  } catch {
    Write-Log "BITS failed: $($_.Exception.Message)" "WARN"
    try {
      Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 900
      return (Test-Path $OutFile)
    } catch {
      Write-Log "IWR failed: $($_.Exception.Message)" "ERROR"
      return $false
    }
  }
}

function Get-FileHashHex { param([string]$Path,[string]$Algo='SHA256')
  if (-not (Test-Path $Path)) { return $null }
  (Get-FileHash -Path $Path -Algorithm $Algo).Hash.ToLowerInvariant()
}

function Load-Manifest {
  if ([string]::IsNullOrWhiteSpace($ManifestPath)) { return $null }
  if (Test-Path $ManifestPath) {
    try { return Get-Content $ManifestPath -Raw | ConvertFrom-Json } catch { Write-Log "Bad manifest JSON: $ManifestPath" "WARN"; return $null }
  }
  Write-Log "No manifest found at $ManifestPath; continuing without it." "WARN"
  return $null
}

function Load-Mirrors {
  if ([string]::IsNullOrWhiteSpace($MirrorListPath)) { return @() }
  if (Test-Path $MirrorListPath) { return Get-Content $MirrorListPath | Where-Object { $_ -and ($_ -notmatch '^\s*#') } }
  return @()
}

function Fix-LineEndings { param([string]$Path)
  $ext = [io.path]::GetExtension($Path).ToLowerInvariant()
  if ($ext -in '.ps1','.psm1','.psd1','.sh','.cfg','.json','.yml','.yaml','.txt','.ini') {
    $c = Get-Content $Path -Raw -ErrorAction SilentlyContinue
    if ($null -ne $c -and $c.Contains("`r`n") -eq $false) {
      $fixed = $c -replace "`n","`r`n"
      if (-not $DryRun) { $fixed | Set-Content -Path $Path -Encoding UTF8 }
      return @{ action='Fix-LineEndings'; path=$Path }
    }
  }
  return $null
}

function Fix-PsCompat { param([string]$Path)
  $ext = [io.path]::GetExtension($Path).ToLowerInvariant()
  if ($ext -ne '.ps1' -and $ext -ne '.psm1') { return $null }
  $t = Get-Content $Path -Raw -ErrorAction SilentlyContinue
  if ($null -eq $t) { return $null }
  $orig = $t
  $t = $t -replace '\?\.','.'   # remove null-conditional
  $t = $t -replace '(-not\(Get-Command \$Name\))','(-not (Get-Command $Name))'
  if ($t -ne $orig) {
    if (-not $DryRun) { $t | Set-Content -Path $Path -Encoding UTF8 }
    return @{ action='Fix-PsCompat'; path=$Path }
  }
  return $null
}

function Invoke-Scan {
  Write-Log "Scanning C:\GFL-System for issues..."
  $issues = @()
  Get-ChildItem -Path $GflRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\(Staging|Reports\\(artifacts|logs|health))\\' } |
    ForEach-Object {
      $fix1 = Fix-LineEndings -Path $_.FullName
      if ($fix1) { $issues += $fix1 }
      $fix2 = Fix-PsCompat     -Path $_.FullName
      if ($fix2) { $issues += $fix2 }
    }
  return ,$issues
}

function Restore-Missing { param($Manifest,$Mirrors)
  if ($null -eq $Manifest) { Write-Log "No manifest; skipping restore." "WARN"; return @() }
  $restored = @()
  foreach ($entry in $Manifest.files) {
    $target   = Join-Path $GflRoot $entry.path
    $expected = $entry.sha256
    if (-not (Test-Path $target) -or (($expected) -and ((Get-FileHashHex $target) -ne $expected))) {
      $ok = $false
      foreach ($m in $Mirrors) {
        $src = if ($entry.PSObject.Properties['source'] -and $entry.source) { $entry.source } else { $entry.path }
        $url = ($m.TrimEnd('/')) + '/' + $src
        $ok  = Invoke-Download -Url $url -OutFile $target
        if ($ok -and $expected) { $ok = ((Get-FileHashHex $target) -eq $expected.ToLowerInvariant()) }
        if ($ok) { break }
      }
      if ($ok) {
        Write-Log ("Restored: {0}" -f $entry.path)
        $restored += @{ path=$entry.path; ok=$true }
      } else {
        Write-Log ("Failed to restore: {0}" -f $entry.path) "ERROR"
        $restored += @{ path=$entry.path; ok=$false }
      }
    }
  }
  return ,$restored
}

function Invoke-Upload { param([string]$LocalPath)
  if ($DryRun) { Write-Log "DryRun: skip upload $LocalPath"; return $true }
  if (Test-Path $LocalPath -PathType Container) { $LocalPath = (Resolve-Path $LocalPath).Path }

  if ($HaveRclone) {
    Write-Log ("Uploading via rclone -> {0}" -f $RcloneRemote)
    $p = Start-Process rclone -ArgumentList @('copy',$LocalPath,$RcloneRemote,'--progress') -Wait -PassThru
    return ($p.ExitCode -eq 0)
  }

  try {
    Write-Log ("Uploading via SFTP fallback -> {0}:{1}" -f $SftpHost,$SftpPort)
    throw 'SSH.NET not available; falling back to FTP.'
  } catch {
    Write-Log ("SFTP unavailable: {0}" -f $_.Exception.Message) "WARN"
  }

  try {
    Write-Log ("Uploading via FTP fallback -> {0}:{1}" -f $FtpHost,$FtpPort)
    $client = New-Object System.Net.WebClient
    if ($FtpUser) { $client.Credentials = New-Object System.Net.NetworkCredential($FtpUser,$FtpPass) }
    $files = if (Test-Path $LocalPath -PathType Container) { Get-ChildItem -Path $LocalPath -File -Recurse } else { Get-Item $LocalPath }
    foreach ($f in $files) {
      $rel  = (Resolve-Path $f.FullName).Path.Substring($LocalPath.Length).TrimStart('\')
      $dest = ("ftp://{0}:{1}/{2}/{3}" -f $FtpHost,$FtpPort,($FtpRemoteDir.TrimStart('/')),($rel -replace '\\','/'))
      $client.UploadFile($dest,'STOR',$f.FullName)
      Write-Log ("Uploaded: {0}" -f $rel)
    }
    return $true
  } catch {
    Write-Log ("FTP upload failed: {0}" -f $_.Exception.Message) "ERROR"
    return $false
  }
}

function Sync-Android {
  if (-not $HaveAdb) { Write-Log "ADB not found; skipping Android sync." "WARN"; return $false }
  try {
    Write-Log ("Pushing artifacts to Android: {0}" -f $AndroidPushDir)
    Start-Process adb -ArgumentList @('shell','mkdir','-p',$AndroidPushDir) -Wait | Out-Null
    Start-Process adb -ArgumentList @('push',$Artifacts,$AndroidPushDir) -Wait | Out-Null
    Write-Log "Android sync complete."
    return $true
  } catch {
    Write-Log ("ADB sync failed: {0}" -f $_.Exception.Message) "ERROR"; return $false
  }
}

$started = Get-Date
$summary = [ordered]@{
  started   = $started
  psVersion = $PSVersionTable.PSVersion.ToString()
  actions   = @()
}

if ($All) { $Scan=$true; $Repair=$true; $Download=$true; $Upload=$true }

Write-Log ("=== GFL Multi-Fix start (PS {0}) ===" -f $PSVersionTable.PSVersion)
Write-Log ("Flags: Scan={0} Repair={1} Download={2} Upload={3} AndroidSync={4} DryRun={5}" -f $Scan,$Repair,$Download,$Upload,$AndroidSync,$DryRun)

$manifest = Load-Manifest
$mirrors  = Load-Mirrors

if ($Scan -or $Repair) {
  $issues = Invoke-Scan
  $summary.actions += @{ name='scan+repair'; count=$issues.Count }
  if ($issues.Count -gt 0) {
    $issues | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $LogsDir 'fixes.json') -Encoding UTF8
  }
}

if ($Download) {
  $restored = Restore-Missing -Manifest $manifest -Mirrors $mirrors
  $summary.actions += @{ name='restore-missing'; total=$restored.Count; ok=($restored | ? {$_.ok}).Count; fail=($restored | ? {-not $_.ok}).Count }
}

Copy-Item -Force $LogFile -Destination (Join-Path $Artifacts 'multi-fix.log') -ErrorAction SilentlyContinue
if (Test-Path $ManifestPath)   { Copy-Item -Force $ManifestPath   (Join-Path $Artifacts 'core-manifest.json') }
if (Test-Path $MirrorListPath) { Copy-Item -Force $MirrorListPath (Join-Path $Artifacts 'mirrors.txt') }

if ($Upload) {
  $uok = Invoke-Upload -LocalPath $Artifacts
  $summary.actions += @{ name='upload-artifacts'; ok=$uok }
}

if ($AndroidSync) {
  $aok = Sync-Android
  $summary.actions += @{ name='android-sync'; ok=$aok }
}

$summary.ended   = Get-Date
$summary.elapsed = (New-TimeSpan -Start $summary.started -End $summary.ended).ToString()
$summary | ConvertTo-Json -Depth 6 | Set-Content $JsonOut -Encoding UTF8

Write-Log ("=== GFL Multi-Fix finished in {0} ===" -f $summary.elapsed)
Write-Log ("JSON summary: {0}" -f $JsonOut)














































