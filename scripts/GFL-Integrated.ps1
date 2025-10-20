$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Paths
$GflRoot   = "C:\GFL-System"
$Scripts   = Join-Path $GflRoot 'Scripts'
$Reports   = Join-Path $GflRoot 'Reports'
$HealthDir = Join-Path $Reports 'health'
$BGDir     = Join-Path $Reports 'backgrounds'
$BGCsv     = Join-Path $BGDir 'backgrounds_files.csv'
$BGHtml    = Join-Path $BGDir 'backgrounds_gallery.html'
$BGUrl     = Join-Path $env:USERPROFILE 'Desktop\GFL Backgrounds.url'
New-Item -ItemType Directory -Force -Path $GflRoot,$Scripts,$Reports,$HealthDir,$BGDir | Out-Null

function Write-Utf8NoBom([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$Text,$enc)
}
function Get-Command([string]$name){ (Get-Command $name -EA SilentlyContinue | Select-Object -First 1).Source }
function Say([string]$msg,[string]$color='Gray'){ Write-Host $msg -ForegroundColor $color }
function Short-Bytes([long]$B){ if($B -ge 1GB){ '{0:N1} GB' -f ($B/1GB) } elseif($B -ge 1MB){ '{0:N1} MB' -f ($B/1MB) } elseif($B -ge 1KB){ '{0:N1} KB' -f ($B/1KB) } else { "$B B" } }

function Build-BackgroundsGallery {
  Say "`n[BG] Scanning for backgrounds..." Cyan
  $exts='*.jpg','*.jpeg','*.png','*.bmp','*.gif','*.webp','*.heic'
  $names='background','wallpaper','bg','backdrop'
  $roots=@("$env:USERPROFILE\Pictures","$env:USERPROFILE\Desktop","C:\Windows\Web\Wallpaper","C:\Windows\Web\Screen","$env:PUBLIC\Pictures") | ? { Test-Path $_ }
  $files = foreach($r in $roots){ foreach($e in $exts){ Get-ChildItem -Path $r -Recurse -File -Include $e -EA SilentlyContinue } }
  $files = $files | Sort-Object LastWriteTime -Descending | Select-Object -Unique FullName,Name,Directory,Length,LastWriteTime
  $filesNamed = $files | Where-Object { $n=$_.Name.ToLower(); ($names | ForEach-Object { $n -like "*$_*" }) -contains $true }
  if(-not $filesNamed){ $filesNamed = $files }
  $filesNamed | Select-Object @{n='File';e={$_.FullName}},@{n='Folder';e={$_.Directory}},@{n='Name';e={$_.Name}},@{n='SizeBytes';e={$_.Length}},@{n='Size';e={ Short-Bytes $_.Length }},@{n='Modified';e={$_.LastWriteTime}} | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $BGCsv
  $rows = $filesNamed | ForEach-Object { $p = $_.FullName -replace '\\','/'; "<div class='card'><img loading='lazy' src='file:///$p'/><div class='meta'><div>$($_.Name)</div><div class='small'>$($_.Directory)</div></div></div>" }
  $count = ($filesNamed|Measure-Object).Count
  $css = @"
body{font-family:Segoe UI,Arial,sans-serif;background:#0b0f14;color:#e5e7eb;margin:0}
h2{margin:16px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px;padding:16px}
.card{background:#0e1622;border:1px solid #1f2a3a;border-radius:12px;overflow:hidden}
.card img{width:100%;height:140px;object-fit:cover;display:block;background:#111826}
.meta{padding:8px;font-size:12px;color:#cbd5e1}
.small{color:#94a3b8}
footer{padding:12px;color:#94a3b8;font-size:12px}
"@
  $html = @"
<!doctype html><meta charset='utf-8'/><title>GFL Backgrounds</title>
<style>$css</style>
<h2>Backgrounds found ($count)</h2>
<div class='grid'>
$($rows -join "`n")
</div>
<footer>CSV: $BGCsv</footer>
"@
  Write-Utf8NoBom $BGHtml $html
  $url = "file:///$($BGHtml -replace '\\','/')"
  $lnk = "[InternetShortcut]`r`nURL=$url`r`nIconIndex=0"
  Write-Utf8NoBom $BGUrl $lnk
  Say "[BG] Wrote: $BGHtml" Green
}

function Verify-Stack {
  Say "`n[VERIFY] Checking tools & GPhotos" Cyan
  $csv = Join-Path $HealthDir ("verify_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
  $rows = New-Object System.Collections.Generic.List[Object]
  foreach($t in 'rclone','adb','pwsh','powershell','winget','choco'){
    $p = Get-Command $t
    $rows.Add([pscustomobject]@{Section='Tool'; Name=$t; Present=[bool]$p; Path=$p})
  }
  $rclone = Get-Command 'rclone'
  $present=$false; $top=''
  if($rclone){
    $rem = & $rclone listremotes 2>$null
    if(($rem -join "`n") -match "^\QGPhotos:\E"){
      $present=$true
      try{ $albums = & $rclone lsf "GPhotos:album" 2>$null; if($albums){ $top = ($albums | Select-Object -First 5) -join '; ' } }catch{}
    }
  }
  $rows.Add([pscustomobject]@{Section='Rclone'; Name='Remote:GPhotos'; Present=$present; Path=$top})
  $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csv
  Say "[VERIFY] CSV: $csv" Green
}

function Sweep-EventLogs([int]$Days=7){
  Say "`n[EVENTS] Sweeping last $Days day(s)..." Cyan
  $since = (Get-Date).AddDays(-[math]::Abs($Days))
  $outCsv = Join-Path $HealthDir ("event_errors_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
  $logs = @(@{Log='Application'; Level=@('Error','Warning')}, @{Log='System'; Level=@('Error','Warning')})
  $rows = New-Object System.Collections.Generic.List[Object]
  foreach($l in $logs){
    foreach($lvl in $l.Level){
      try{
        $lvlCode = if($lvl -eq 'Error'){ 2 } else { 3 }
        $ev = Get-WinEvent -FilterHashtable @{ LogName=$l.Log; Level=$lvlCode; StartTime=$since } -ErrorAction SilentlyContinue
        foreach($e in $ev){
          $rows.Add([pscustomobject]@{
            TimeCreated=$e.TimeCreated; Log=$l.Log; Level=$lvl; Id=$e.Id; Provider=$e.ProviderName
            Message=($e.Message -replace '\s+',' ' -replace '[\u0000-\u001F]','').Trim()
          })
        }
      }catch{}
    }
  }
  $rows | Sort-Object TimeCreated -Desc | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $outCsv
  Say "[EVENTS] CSV: $outCsv" Green
}

function Deep-FileScan([string[]]$Roots=@("$env:USERPROFILE","C:\GFL-System","C:\Windows\Logs"),[int]$MaxFiles=200000){
  Say "`n[SCAN] Deep file scan..." Cyan
  $outCsv = Join-Path $HealthDir ("filescan_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
  $rows = New-Object System.Collections.Generic.List[Object]
  $scanned=0
  foreach($root in $Roots){
    if(-not (Test-Path $root)){ continue }
    try{
      $files = Get-ChildItem -LiteralPath $root -Recurse -File -EA SilentlyContinue
      foreach($f in $files){
        $scanned++; if($scanned -gt $MaxFiles){ break }
        $ok=$true; $err=$null
        try{ $fs=[IO.File]::Open($f.FullName,'Open','Read','Read'); if($fs.Length -gt 0){ $buf=New-Object byte[] 1; [void]$fs.Read($buf,0,1) }; $fs.Close() }catch{ $ok=$false; $err=$_.Exception.Message }
        $rows.Add([pscustomobject]@{ File=$f.FullName; SizeBytes=$f.Length; SizeLabel=(Short-Bytes $f.Length); Modified=$f.LastWriteTime; Readable=$ok; Error=$err })
      }
    }catch{
      $rows.Add([pscustomobject]@{ File=$root; SizeBytes=$null; SizeLabel=$null; Modified=$null; Readable=$false; Error=$_.Exception.Message })
    }
  }
  $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $outCsv
  Say "[SCAN] CSV: $outCsv" Green
}

function Build-HealthReport {
  Say "`n[REPORT] Building health HTML..." Cyan
  $latestVerify = Get-ChildItem $HealthDir -Filter 'verify_*.csv' -File -EA SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1
  $latestEvents = Get-ChildItem $HealthDir -Filter 'event_errors_*.csv' -File -EA SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1
  $latestFiles  = Get-ChildItem $HealthDir -Filter 'filescan_*.csv' -File -EA SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1
  $verifyRows = if($latestVerify){ Import-Csv $latestVerify.FullName } else { @() }
  $eventRows  = if($latestEvents){ Import-Csv $latestEvents.FullName } else { @() }
  $fileRows   = if($latestFiles ){ Import-Csv $latestFiles.FullName  } else { @() }
  $okTools   = ($verifyRows | ? { $_.Section -eq 'Tool' -and $_.Present -eq 'True' }).Count
  $missTools = ($verifyRows | ? { $_.Section -eq 'Tool' -and $_.Present -ne 'True' }).Count
  $evErrs    = ($eventRows  | ? { $_.Level -eq 'Error' }).Count
  $evWarn    = ($eventRows  | ? { $_.Level -eq 'Warning' }).Count
  $fsErrs    = ($fileRows   | ? { $_.Readable -eq 'False' }).Count
  $fsScanned = $fileRows.Count
  $css="body{font-family:Segoe UI,Arial,sans-serif;background:#0b0f14;color:#e8eef7;margin:0}.header{padding:16px 20px;background:#111826;border-bottom:1px solid #1e293b}.wrap{padding:20px;display:grid;grid-template-columns:1fr 1fr;gap:16px}.card{background:#0e1622;border:1px solid #1f2a3a;border-radius:14px;padding:16px}.small{font-size:12px;color:#94a3b8}"
  function Href($p){ if(-not $p){ return '' } 'file:///{0}' -f ($p -replace '\\','/') }
  $now = Get-Date
  $html = @"
<!doctype html><meta charset='utf-8'/><title>GFL Health</title>
<style>$css</style>
<div class='header'><h2 style='margin:0'>GFL Health</h2><span style='margin-left:8px;border:1px solid #334155;padding:2px 8px;border-radius:999px;font-size:12px;color:#cbd5e1'>Updated: $($now.ToString('yyyy-MM-dd HH:mm:ss'))</span></div>
<div class='wrap'>
  <div class='card'><h3>Verification</h3><div class='small'>Tools ok: $okTools | Missing: $missTools</div><div class='small'><a style='color:#60a5fa' href='$(Href($latestVerify.FullName))'>Open verify CSV</a></div></div>
  <div class='card'><h3>Event Logs</h3><div class='small'>Errors: $evErrs | Warnings: $evWarn</div><div class='small'><a style='color:#60a5fa' href='$(Href($latestEvents.FullName))'>Open events CSV</a></div></div>
  <div class='card' style='grid-column:1 / -1'><h3>File Scan</h3><div class='small'>Files scanned: $fsScanned | Read errors: $fsErrs</div><div class='small'><a style='color:#60a5fa' href='$(Href($latestFiles.FullName))'>Open files CSV</a></div></div>
</div>
"@
  $index = Join-Path $HealthDir 'index.html'
  Write-Utf8NoBom $index $html
  Start-Process $index
  Say "[REPORT] HTML: $index" Green
}

function Ensure-Schedule([string]$TaskName='GFL-Health-Nightly',[string]$ScriptToRun,[string]$Time='02:00'){
  $ps = (Get-Command 'pwsh'); if(-not $ps){ $ps=(Get-Command 'powershell'); if(-not $ps){ $ps='PowerShell.exe' } }
  if(-not (Test-Path $ScriptToRun)){ throw "Script not found: $ScriptToRun" }
  schtasks /Create /TN $TaskName /TR "$ps -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$ScriptToRun`"" /SC DAILY /ST $Time /RU SYSTEM /F | Out-Null
  Say "[TASK] $TaskName scheduled @ $Time" Green
}

# ADB Wi-Fi helper (optional)
function Connect-ADBWifi { param([string]$PhoneIp,[int]$Port=5555)
  $adb = Get-Command 'adb' ; if(-not $adb){ throw "adb not found. Install Android platform tools." }
  Say ("[ADB] Trying {0}:{1} ..." -f $PhoneIp,$Port) Cyan
  & $adb connect "$($PhoneIp):$Port"
  Start-Sleep 1
  & $adb devices
}

# Simple pull loop (optional)
function Start-MobilePullLoop { param([string]$PhonePath="/sdcard/GFLSync",[string]$PcPath="C:\GFL-System\MobileSync",[int]$IntervalSec=7)
  New-Item -ItemType Directory -Force -Path $PcPath | Out-Null
  $adb = Get-Command 'adb' ; if(-not $adb){ throw "adb not found." }
  Say "[PULL] Looping; Ctrl+C to stop" Cyan
  while($true){
    try{ & $adb pull "$PhonePath/." $PcPath | Out-Null; Say "[PULL] tick" DarkGray }catch{ Say "[PULL] No device; retrying." Yellow }
    Start-Sleep -Seconds $IntervalSec
  }
}

# ---------------- MAIN ----------------
Say "`n=== G F L   I N T E G R A T E D ===" DarkCyan
Build-BackgroundsGallery
Verify-Stack
Sweep-EventLogs -Days 7
Deep-FileScan -Roots @("$env:USERPROFILE","C:\GFL-System","C:\Windows\Logs") -MaxFiles 200000
Build-HealthReport
Ensure-Schedule -TaskName 'GFL-Health-Nightly' -ScriptToRun 'C:\GFL-System\Scripts\GFL-Nightly.ps1' -Time '02:00'
Say "`nDone. Opened health report; backgrounds gallery is ready on the desktop shortcut." Green


































