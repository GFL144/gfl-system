[CmdletBinding()]
param(
  [switch]$Run,
  [switch]$InstallSchedule,
  [int]$KeepBackups = 3,
  [int]$RotateLogsDays = 7
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Paths ---
$Root      = 'C:\GFL-System'
$Scripts   = Join-Path $Root 'Scripts'
$Reports   = Join-Path $Root 'Reports'
$LogsDir   = Join-Path $Reports 'logs'
$Artifacts = Join-Path $Reports 'artifacts'
$Backups   = Join-Path $Root 'Backups'
$Staging   = Join-Path $Root 'Staging'
$Manifest  = Join-Path $Root 'Manifests\system.json'
$Status    = Join-Path $Reports 'status.json'
$Orch      = Join-Path $Scripts 'GFL-Universal-Orchestrator.ps1'
New-Item -ItemType Directory -Force -Path $Reports,$LogsDir,$Artifacts,$Backups,$Staging | Out-Null

function Write-Status($obj){ $obj.time = Get-Date; $obj | ConvertTo-Json -Depth 6 | Set-Content -Enc UTF8 $Status }
function Rotate-Logs { try { Get-ChildItem $LogsDir -File -Rec -EA SilentlyContinue | ?{ $_.LastWriteTime -lt (Get-Date).AddDays(-$RotateLogsDays) } | Remove-Item -Force -EA SilentlyContinue }catch{} }
function Get-FileHashHex($p){ if(!(Test-Path $p)){return $null}; (Get-FileHash -Alg SHA256 -Path $p).Hash.ToLower() }
function New-Backup {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $dest  = Join-Path $Backups "backup-$stamp.zip"
  if(Test-Path $dest){ Remove-Item $dest -Force }
  Compress-Archive -Path "$Root\*" -DestinationPath $dest -Force -CompressionLevel Optimal `
    -Exclude 'Backups\*','Staging\*','Reports\logs\*','Reports\artifacts\*','update.zip'
  Get-ChildItem $Backups -Filter 'backup-*.zip' | Sort-Object LastWriteTime -Desc | Select-Object -Skip $KeepBackups | Remove-Item -Force -EA SilentlyContinue
  return $dest
}
function Restore-Backup($zip){ if(Test-Path $zip){ Write-Host " Restoring from $zip ..."; Expand-Archive -Path $zip -DestinationPath $Root -Force } }

function Invoke-SafeUpdate {
  $status = [ordered]@{ phase='update'; step='start' }; Write-Status $status
  $manifestUrl = 'https://hopelinkdivinegfl.online/api/updates/system-manifest.json'
  try {
    $remote = Invoke-RestMethod -UseBasicParsing -Uri $manifestUrl
    if(-not $remote){ Write-Warning "No remote manifest."; $status.step='no-manifest'; Write-Status $status; return }
    if([string]::IsNullOrWhiteSpace($remote.package)){ Write-Warning "Manifest missing package URL."; $status.step='bad-manifest'; Write-Status $status; return }
    $status.remoteVersion = $remote.version; $status.package = $remote.package; $status.sha256 = $remote.sha256; Write-Status $status

    $localVersion = if(Test-Path $Manifest){ (Get-Content $Manifest -Raw | ConvertFrom-Json).version } else { '0' }
    if($localVersion -eq $remote.version){ Write-Host " Up-to-date ($localVersion)."; $status.step='noop'; Write-Status $status; return }

    # download
    $pkg = Join-Path $Artifacts 'update.zip'
    if(Test-Path $pkg){ Remove-Item $pkg -Force }
    Write-Host " Downloading package via BITS"
    Start-BitsTransfer -Source $remote.package -Destination $pkg -Description 'GFL Update' -DisplayName 'GFL Update' -RetryInterval 5 -EA Stop
    $status.step='downloaded'; Write-Status $status

    # hash
    $hash = Get-FileHashHex $pkg
    if(-not $hash){ throw "Hash read failed." }
    if($remote.sha256 -and ($hash -ne $remote.sha256.ToLower())){ throw "SHA256 mismatch. Expected $($remote.sha256), got $hash" }
    Write-Host " Hash OK: $hash"
    $status.step='hash-ok'; $status.hash=$hash; Write-Status $status

    # backup
    $backupZip = New-Backup
    $status.step='backup-made'; $status.backup=$backupZip; Write-Status $status

    # stage+deploy
    if(Test-Path $Staging){ Remove-Item $Staging -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $Staging | Out-Null
    Expand-Archive -Path $pkg -DestinationPath $Staging -Force
    Write-Host " Deploying staged files"
    robocopy $Staging $Root /MIR /XD "Backups" "Reports\logs" "Reports\artifacts" "Staging" | Out-Null

    # manifest
    $remote | ConvertTo-Json -Depth 6 | Set-Content -Enc UTF8 $Manifest
    $status.step='deployed'; Write-Status $status
    Write-Host " Update to $($remote.version) complete."
  } catch {
    $status.step='error'; $status.error="$_"; Write-Status $status
    Write-Warning "Update failed: $_"
    $lastBackup = Get-ChildItem $Backups -Filter 'backup-*.zip' | Sort-Object LastWriteTime -Desc | Select-Object -First 1
    if($lastBackup){ Restore-Backup $lastBackup.FullName } else { Write-Warning "No backups found to restore." }
  } finally {
    if(Test-Path $Staging){ Remove-Item $Staging -Recurse -Force -EA SilentlyContinue }
  }
}

function Ensure-Rclone { $exists = Get-Command rclone -EA SilentlyContinue; if(-not $exists){ Write-Warning "rclone not found; skipping cloud sync."; return $false }
function Has-RcloneRemote([string]){
  try {
    \ = rclone listremotes 2>\
    return (\ -match "^\Q\\E:$")
  } catch { return \False }
}; return $true }
function\ Try-CloudSync\ \{\n\ \ if\(Test-Path\ Env:GFL_NO_CLOUD\)\{\ Write-Host\ "☁️\ Cloud\ sync\ disabled\ via\ GFL_NO_CLOUD";\ return\ }\n\ \ if\(-not\ \(Ensure-Rclone\)\)\{\ return\ }\n\ \ if\(-not\ \(Has-RcloneRemote\ 'GDrive'\)\)\{\n\ \ \ \ Write-Warning\ "rclone\ remote\ 'GDrive'\ not\ configured;\ using\ local\ fallback\."\n\ \ \ \ try\ \{\n\ \ \ \ \ \ \\\ =\ 'C:\\GFL-Backups'\n\ \ \ \ \ \ New-Item\ -ItemType\ Directory\ -Force\ -Path\ "\\\\Reports"\ \|\ Out-Null\n\ \ \ \ \ \ Copy-Item\ -Recurse\ -Force\ -Path\ \(Join-Path\ 'C:\\GFL-System'\ 'Reports'\)\ -Destination\ "\\\\Reports"\n\ \ \ \ \ \ \\\ =\ 'C:\\GFL-System\\Manifests\\system\.json'\n\ \ \ \ \ \ if\(Test-Path\ \\\)\{\ Copy-Item\ -Force\ \\\ "\\\\"\ }\n\ \ \ \ \ \ Write-Host\ "☁️\ Local\ fallback\ backup\ written\ to\ \\"\n\ \ \ \ }\ catch\ \{\ Write-Warning\ "Local\ fallback\ failed:\ "\ }\n\ \ \ \ return\n\ \ }\n\ \ try\ \{\n\ \ \ \ &\ rclone\ sync\ \(Join-Path\ 'C:\\GFL-System'\ 'Reports'\)\ "GDrive:GFL-Backups/Reports"\ --progress\n\ \ \ \ \\\ =\ 'C:\\GFL-System\\Manifests\\system\.json'\n\ \ \ \ if\(Test-Path\ \\\)\{\ &\ rclone\ copy\ \\\ "GDrive:GFL-Backups"\ --progress\ }\n\ \ }\ catch\ \{\ Write-Warning\ "Cloud\ sync\ warning:\ "\ }\n}; try { & rclone sync $Reports "GDrive:GFL-Backups/Reports" --progress; if(Test-Path $Manifest){ & rclone copy $Manifest "GDrive:GFL-Backups" --progress } } catch { Write-Warning "Cloud sync warning: $_" } }

function Invoke-Orchestrator-Cycle {
  $status = [ordered]@{ phase='orchestrator'; step='start' }; Write-Status $status
  & $Orch -Diagnostics; $status.step='diagnostics'; Write-Status $status
  & $Orch -RunAll;      $status.step='runall';      Write-Status $status
  Invoke-SafeUpdate;    $status.step='safe-update'; Write-Status $status
  Try-CloudSync;        $status.step='cloud';       Write-Status $status
  $status.step='done';  Write-Status $status
}

function Install-Schedule {
  $taskName = 'GFL-Orchestrator-Hourly'
  $exe = (Get-Command pwsh).Source
  $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Run"
  $trig1 = New-ScheduledTaskTrigger -Daily -At (Get-Date).Date.AddMinutes(5).TimeOfDay
  $trig1.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date)).Repetition
  $trig1.Repetition.Interval = (New-TimeSpan -Hours 1)
  $act = New-ScheduledTaskAction -Execute $exe -Argument $args
  try{ Register-ScheduledTask -TaskName $taskName -Action $act -Trigger $trig1 -Description "Run GFL Guardian hourly" -RunLevel Highest -Force | Out-Null; Write-Host " Scheduled task '$taskName' installed (hourly)." } catch { Write-Warning "Failed to register task: $_" }
}

# single-instance
$mutex = New-Object System.Threading.Mutex($false,'Global\GFL-Orchestrator-Guardian')
$hasHandle = $false
try {
  $hasHandle = $mutex.WaitOne(0)
  if(-not $hasHandle){ Write-Host " Another Guardian instance is running. Exiting."; return }
  Rotate-Logs
  if($InstallSchedule){ Install-Schedule; return }
  if($Run){ Invoke-Orchestrator-Cycle } else { Write-Host "Usage: -Run  or  -InstallSchedule" }
} finally { if($hasHandle){ $mutex.ReleaseMutex() | Out-Null } }

