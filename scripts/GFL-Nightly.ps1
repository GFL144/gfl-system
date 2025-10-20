$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Short-Bytes([long]$B){ if($B -ge 1GB){ '{0:N1} GB' -f ($B/1GB) } elseif($B -ge 1MB){ '{0:N1} MB' -f ($B/1MB) } elseif($B -ge 1KB){ '{0:N1} KB' -f ($B/1KB) } else { "$B B" } }
$HealthDir = "C:\GFL-System\Reports\health"
$GflRoot   = "C:\GFL-System"
New-Item -ItemType Directory -Force -Path $HealthDir | Out-Null
function Write-Utf8NoBom([string]$Path,[string]$Text){ $enc=[Text.UTF8Encoding]::new($false); [IO.File]::WriteAllText($Path,$Text,$enc) }

# Verify core tools
$verifyCsv = Join-Path $HealthDir ("verify_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$rows = New-Object 'System.Collections.Generic.List[object]'
foreach($t in 'rclone','adb','pwsh','powershell'){
  $p=(Get-Command $t -EA SilentlyContinue | Select-Object -First 1).Source
  $rows.Add([pscustomobject]@{Section='Tool';Name=$t;Present=[bool]$p;Path=$p})
}
$rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $verifyCsv

# Event errors & warnings (7 days)
$since=(Get-Date).AddDays(-7)
$evCsv=Join-Path $HealthDir ("event_errors_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$evRows=New-Object 'System.Collections.Generic.List[object]'
foreach($pair in @(@{L='Application';C=2,3},@{L='System';C=2,3})){
  foreach($c in $pair.C){
    try{
      $ev=Get-WinEvent -FilterHashtable @{LogName=$pair.L;Level=$c;StartTime=$since} -EA SilentlyContinue
      foreach($e in $ev){
        $evRows.Add([pscustomobject]@{
          TimeCreated=$e.TimeCreated;Log=$pair.L;Level=if($c -eq 2){'Error'}else{'Warning'}
          Id=$e.Id;Provider=$e.ProviderName;Message=($e.Message -replace '\s+',' ').Trim()
        })
      }
    }catch{}
  }
}
$evRows | Sort-Object TimeCreated -Desc | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $evCsv

# Deep file scan (readable check)  USERPROFILE + GFL
$scanCsv=Join-Path $HealthDir ("filescan_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$rows=@()
foreach($root in @("$env:USERPROFILE","C:\GFL-System")){
  if(Test-Path $root){
    Get-ChildItem -LiteralPath $root -Recurse -File -EA SilentlyContinue | Select-Object -First 100000 | ForEach-Object {
      try{ $fs=[IO.File]::Open($_.FullName,'Open','Read','Read'); if($fs.Length -gt 0){ $buf=New-Object byte[] 1; [void]$fs.Read($buf,0,1) }; $fs.Close(); $ok=$true; $err=$null }catch{ $ok=$false; $err=$_.Exception.Message }
      [pscustomobject]@{File=$_.FullName;SizeBytes=$_.Length;SizeLabel=(Short-Bytes $_.Length);Modified=$_.LastWriteTime;Readable=$ok;Error=$err}
    } | ForEach-Object { $rows += $_ }
  }
}
$rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $scanCsv

# Tiny HTML summary
$index = Join-Path $HealthDir 'index.html'
$now = Get-Date
$html = @"
<!doctype html><meta charset='utf-8'/><title>GFL Nightly</title>
<body style='font-family:Segoe UI;background:#0b0f14;color:#e8eef7'>
<h2>GFL Nightly</h2>
<div>Updated: $($now.ToString('yyyy-MM-dd HH:mm:ss'))</div>
<ul>
  <li>Verify: $verifyCsv</li>
  <li>Events: $evCsv</li>
  <li>Files:  $scanCsv</li>
</ul>
</body>
"@
Write-Utf8NoBom $index $html








