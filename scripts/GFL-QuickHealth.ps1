$ErrorActionPreference='Stop'
Import-Module (Join-Path 'C:\GFL-System\Scripts' 'GFL.Common.psm1') -Force
$ZipRoot = Join-Path $env:USERPROFILE 'Desktop\Zip Files'
$archives = Get-ChildItem $ZipRoot -File -Include *.zip,*.7z,*.7z.* -EA SilentlyContinue
$archCount = ($archives|Measure-Object).Count
$archBytes = ($archives|Measure-Object -Sum Length).Sum
$archSize  = Short-Bytes $archBytes
$logFiles  = Get-ChildItem $GflLogs -File -EA SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 20
$errCount  = 0; foreach($lf in $logFiles){ $errCount += (Select-String -Path $lf.FullName -Pattern '\|ERROR\|Exception' -EA SilentlyContinue | Measure-Object).Count }
$proc = Get-Process quantumminer* -EA SilentlyContinue
$miner = if($proc){ "ONLINE (PID $($proc.Id))" } else { "OFFLINE" }
$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$csv = Join-Path 'C:\GFL-System\Reports' 'quick_health.csv'
[pscustomobject]@{
  Timestamp=$ts; ArchivesCount=$archCount; ArchivesSize=$archSize; RecentErrorLines=$errCount; MinerState=$miner
} | Export-Csv -NoTypeInformation -Append -Encoding UTF8 -Path $csv
