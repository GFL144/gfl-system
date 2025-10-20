param(
  [string]$RemoteName      = "GPhotos",
  [string]$MobileSyncPath  = "C:\GFL-System\MobileSync",
  [string]$TaskName        = "GFL-Backgrounds-Rebuild",
  [switch]$Json
)

$ErrorActionPreference='Stop'
function Get-Command($n){ (Get-Command $n -EA SilentlyContinue | Select-Object -First 1).Source }

$results = [ordered]@{
  Timestamp           = (Get-Date).ToString("s")
  PowerShellVersion   = $PSVersionTable.PSVersion.ToString()
  IsAdmin             = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  Paths               = @{
    Root      = "C:\GFL-System"
    Scripts   = "C:\GFL-System\Scripts"
    Reports   = "C:\GFL-System\Reports"
    Health    = "C:\GFL-System\Reports\health"
    Mobile    = $MobileSyncPath
  }
  Tools               = @()
  RcloneRemote        = @{
    Present = $false; ListedAlbumsTop = @(); Error = $null
  }
  ADB                 = @{
    Present = $false; Devices = @(); Error = $null
  }
  ScheduledTask       = @{
    Name=$TaskName; Present=$false; State=$null; Error=$null
  }
}

# Tools presence
foreach($t in 'rclone','adb','pwsh','powershell','winget','choco'){
  $p = Get-Command $t
  $results.Tools += [pscustomobject]@{ Tool=$t; Present=[bool]$p; Path=$p }
}

# Rclone remote quick test
try{
  $rclone = Get-Command 'rclone'
  if($rclone){
    # Check config has the remote
    $rem = & $rclone listremotes 2>$null
    if(($rem -join "`n") -match "^\Q$($RemoteName):\E"){
      $results.RcloneRemote.Present = $true
      try{
        $albums = & $rclone lsf "$RemoteName:album" 2>$null
        if($albums){ $results.RcloneRemote.ListedAlbumsTop = $albums | Select-Object -First 10 }
      } catch { $results.RcloneRemote.Error = $_.Exception.Message }
    }
  }
} catch { $results.RcloneRemote.Error = $_.Exception.Message }

# ADB device list
try{
  $adb = Get-Command 'adb'
  if($adb){
    $results.ADB.Present = $true
    $out = & $adb devices 2>$null
    $devs = @()
    foreach($line in $out){
      if($line -match '^\s*$' -or $line -like '*List of devices*'){ continue }
      $parts = $line -split '\s+'
      if($parts.Length -ge 2){ $devs += [pscustomobject]@{ Id=$parts[0]; State=$parts[1] } }
    }
    $results.ADB.Devices = $devs
  }
} catch { $results.ADB.Error = $_.Exception.Message }

# Scheduled task
try{
  $task = schtasks /Query /TN $TaskName /FO LIST /V 2>$null
  if($LASTEXITCODE -eq 0){
    $results.ScheduledTask.Present = $true
    $stateLine = ($task | Where-Object {$_ -like 'Status:*'}) -replace 'Status:\s*',''
    $results.ScheduledTask.State = $stateLine
  }
} catch { $results.ScheduledTask.Error = $_.Exception.Message }

# Output
if($Json){ $results | ConvertTo-Json -Depth 6 }
else{
  $csv = Join-Path "C:\GFL-System\Reports\health" ("verify_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
  $flat = @()
  foreach($t in $results.Tools){ $flat += [pscustomobject]@{ Section='Tool'; Name=$t.Tool; Present=$t.Present; Path=$t.Path } }
  foreach($d in $results.ADB.Devices){ $flat += [pscustomobject]@{ Section='ADB'; Name=$d.Id; Present=($d.State -eq 'device'); Path=$d.State } }
  $flat += [pscustomobject]@{ Section='Rclone'; Name='Remote:'+ $RemoteName; Present=$results.RcloneRemote.Present; Path=($results.RcloneRemote.ListedAlbumsTop -join '; ') }
  $flat += [pscustomobject]@{ Section='Task'; Name=$results.ScheduledTask.Name; Present=$results.ScheduledTask.Present; Path=$results.ScheduledTask.State }
  $flat | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csv
  Write-Host "Verify report: $csv" -ForegroundColor Green
}


