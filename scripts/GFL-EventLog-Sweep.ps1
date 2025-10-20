param([int]$Days=7)
$ErrorActionPreference='Stop'

$since = (Get-Date).AddDays(-[math]::Abs($Days))
$outCsv = Join-Path "C:\GFL-System\Reports\health" ("event_errors_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

$logs = @(
  @{Log='Application'; Level=@('Error','Warning')},
  @{Log='System';      Level=@('Error','Warning')},
  @{Log='Security';    Level=@('Error') } # warnings here are noisy
)

$rows = New-Object System.Collections.Generic.List[Object]
foreach($l in $logs){
  foreach($lvl in $l.Level){
    try{
      $ev = Get-WinEvent -FilterHashtable @{ LogName=$l.Log; Level=(if($lvl -eq 'Error'){2}else{3}); StartTime=$since } -ErrorAction SilentlyContinue
      foreach($e in $ev){
        $rows.Add([pscustomobject]@{
          TimeCreated = $e.TimeCreated
          Log         = $l.Log
          Level       = $lvl
          Id          = $e.Id
          Provider    = $e.ProviderName
          Machine     = $e.MachineName
          Message     = ($e.Message -replace '\s+',' ' -replace '[\u0000-\u001F]','').Trim()
        })
      }
    }catch{}
  }
}

$rows | Sort-Object TimeCreated -Descending | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $outCsv
Write-Host "Event log sweep: $outCsv" -ForegroundColor Green




