param(
  [string]$HealthDir = "C:\GFL-System\Reports\health"
)
$ErrorActionPreference='Stop'
$index = Join-Path $HealthDir "index.html"

function Short($b){
  if($b -ge 1GB){"{0:N1} GB" -f ($b/1GB)} elseif($b -ge 1MB){"{0:N1} MB" -f ($b/1MB)} elseif($b -ge 1KB){"{0:N1} KB" -f ($b/1KB)} else {"$b B"}
}

$latestVerify = Get-ChildItem $HealthDir -Filter 'verify_*.csv' -File -EA SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1
$latestEvents = Get-ChildItem $HealthDir -Filter 'event_errors_*.csv' -File -EA SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1
$latestFiles  = Get-ChildItem $HealthDir -Filter 'filescan_*.csv' -File -EA SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1
$latestSum    = Get-ChildItem $HealthDir -Filter 'filescan_summary_*.csv' -File -EA SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1

$verifyRows = if($latestVerify){ Import-Csv $latestVerify.FullName } else { @() }
$eventRows  = if($latestEvents){ Import-Csv $latestEvents.FullName } else { @() }
$fileRows   = if($latestFiles ){ Import-Csv $latestFiles.FullName  } else { @() }
$sumRow     = if($latestSum   ){ (Import-Csv $latestSum.FullName)[0] } else { $null }

$css = @"
body{font-family:Segoe UI,Arial,sans-serif;background:#0b0f14;color:#e8eef7;margin:0}
.header{padding:16px 20px;background:#111826;border-bottom:1px solid #1e293b}
.wrap{padding:20px;display:grid;grid-template-columns:1fr 1fr;gap:16px}
.card{background:#0e1622;border:1px solid #1f2a3a;border-radius:14px;padding:16px}
.ok{color:#34d399}.warn{color:#fbbf24}.err{color:#f87171}
table{width:100%;border-collapse:collapse;font-size:13px}
th,td{padding:8px;border-bottom:1px solid #1f2a3a;text-align:left}
.badge{display:inline-block;padding:2px 8px;border-radius:999px;font-size:12px;border:1px solid #334155;color:#cbd5e1;margin-left:8px}
.small{font-size:12px;color:#94a3b8}
"@

function Href($p){ if(-not $p){ return '' } 'file:///{0}' -f ($p -replace '\\','/') }

$okTools   = ($verifyRows | Where-Object { $_.Section -eq 'Tool' -and $_.Present -eq 'True' }).Count
$missTools = ($verifyRows | Where-Object { $_.Section -eq 'Tool' -and $_.Present -ne 'True' }).Count
$adbDevs   = ($verifyRows | Where-Object { $_.Section -eq 'ADB'  -and $_.Present -eq 'True' }).Count
$rcloneOK  = ($verifyRows | Where-Object { $_.Section -eq 'Rclone' -and $_.Present -eq 'True' }).Count
$taskOK    = ($verifyRows | Where-Object { $_.Section -eq 'Task' -and $_.Present -eq 'True' }).Count
$evErrs    = ($eventRows  | Where-Object { $_.Level -eq 'Error' }).Count
$evWarn    = ($eventRows  | Where-Object { $_.Level -eq 'Warning' }).Count
$fsErrs    = ($fileRows   | Where-Object { $_.Readable -eq 'False' }).Count
$fsScanned = $fileRows.Count

$now = Get-Date
$html = @"
<!doctype html><meta charset='utf-8'/>
<title>GFL Health Report</title>
<style>$css</style>
<div class='header'><h2 style='margin:0'>GFL Health Report</h2>
<span class='badge'>Updated: $($now.ToString('yyyy-MM-dd HH:mm:ss'))</span></div>
<div class='wrap'>
  <div class='card'>
    <h3>Verification</h3>
    <div class='small'>Tools ok: $okTools  |  Missing: $missTools  |  ADB devices: $adbDevs  |  Rclone remote ok: $rcloneOK  |  Task ok: $taskOK</div>
    <div class='small'><a style='color:#60a5fa' href='$(Href($latestVerify.FullName))'>Open verify CSV</a></div>
  </div>
  <div class='card'>
    <h3>Event Logs (last run)</h3>
    <div class='small'>Errors: $evErrs  |  Warnings: $evWarn</div>
    <div class='small'><a style='color:#60a5fa' href='$(Href($latestEvents.FullName))'>Open events CSV</a></div>
  </div>
  <div class='card' style='grid-column:1 / -1'>
    <h3>File Scan</h3>
    <div class='small'>Files scanned: $fsScanned  |  Read errors: <span class='$(if($fsErrs -gt 0){'err'}else{'ok'})'>$fsErrs</span></div>
    <div class='small'><a style='color:#60a5fa' href='$(Href($latestFiles.FullName))'>Open files CSV</a></div>
  </div>
</div>
"@
[IO.File]::WriteAllText($index,$html,[Text.UTF8Encoding]::new($false))
Write-Host "Health HTML: $index" -ForegroundColor Green
Start-Process $index




