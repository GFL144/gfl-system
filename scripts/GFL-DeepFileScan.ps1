param(
  [string[]]$Roots = @("$env:USERPROFILE","C:\GFL-System","C:\Windows\Logs"),
  [int]$MaxFiles = 250000,
  [switch]$Hash
)
$ErrorActionPreference='Stop'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outCsv = Join-Path "C:\GFL-System\Reports\health" ("filescan_{0}.csv" -f $stamp)
$sumCsv = Join-Path "C:\GFL-System\Reports\health" ("filescan_summary_{0}.csv" -f $stamp)

function SHA256($p){
  try{
    $s = [System.IO.File]::Open($p,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::Read)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($s); $s.Close()
    -join ($hash | ForEach-Object { $_.ToString('x2') })
  }catch{ $null }
}

$rows = New-Object System.Collections.Generic.List[Object]
$scanned = 0; $errors = 0
foreach($root in $Roots){
  if(-not (Test-Path $root)){ continue }
  try{
    $files = Get-ChildItem -LiteralPath $root -Recurse -File -EA SilentlyContinue
    foreach($f in $files){
      $scanned++
      if($scanned -gt $MaxFiles){ break }
      $h = $null; $err = $null; $ok=$true; $len=$null
      try{
        $fs=[System.IO.File]::Open($f.FullName,'Open','Read','Read'); $len=$fs.Length
        # touch first byte if non-empty
        if($fs.Length -gt 0){ $buf = New-Object byte[] 1; [void]$fs.Read($buf,0,1) }
        $fs.Close()
        if($Hash){ $h = SHA256 $f.FullName }
      }catch{
        $ok=$false; $err = $_.Exception.Message; $errors++
      }
      $rows.Add([pscustomobject]@{
        File         = $f.FullName
        SizeBytes    = $f.Length
        SizeLabel    = if($f.Length -ge 1GB){"{0:N1} GB" -f ($f.Length/1GB)} elseif($f.Length -ge 1MB){"{0:N1} MB" -f ($f.Length/1MB)} elseif($f.Length -ge 1KB){"{0:N1} KB" -f ($f.Length/1KB)} else {"$($f.Length) B"}
        Modified     = $f.LastWriteTime
        Readable     = $ok
        Error        = $err
        SHA256       = $h
      })
    }
  }catch{
    $rows.Add([pscustomobject]@{ File=$root; SizeBytes=$null; SizeLabel=$null; Modified=$null; Readable=$false; Error=$_.Exception.Message; SHA256=$null })
    $errors++
  }
}

$rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $outCsv

# Quick disk/volume health snapshot
$vols = Get-Volume 2>$null | Select-Object DriveLetter,FileSystem,HealthStatus,Size,SizeRemaining
$disks = Get-PhysicalDisk 2>$null | Select-Object FriendlyName,MediaType,HealthStatus,OperationalStatus,Size

$summary = [pscustomobject]@{
  Timestamp   = (Get-Date).ToString('s')
  Roots       = ($Roots -join '; ')
  Scanned     = $scanned
  Errors      = $errors
  FilesCsv    = $outCsv
  Volumes     = ($vols | ConvertTo-Json -Compress)
  Disks       = ($disks | ConvertTo-Json -Compress)
}
$summary | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $sumCsv
Write-Host "File scan: $outCsv" -ForegroundColor Green
Write-Host "Summary : $sumCsv" -ForegroundColor Green






