<# GFL-Rotate-Backup.ps1
    Rotates logs > 20 MB
    Creates daily ZIP backups (7-day retention)
#>
param([int]$KeepDays = 7)
$Root    = "C:\GFL-System"
$Reports = Join-Path $Root "Reports"
$Logs    = Join-Path $Reports "logs"
$Backups = Join-Path $Reports "backups"
New-Item -ItemType Directory -Force -Path $Backups | Out-Null

# rotate big logs
Get-ChildItem $Logs -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 20MB } | ForEach-Object {
  $dst = Join-Path $Logs ("{0}-{1}.log" -f $_.BaseName, (Get-Date -Format "yyyyMMdd-HHmmss"))
  Move-Item $_.FullName $dst -Force
}

# make daily backup
$stamp = Get-Date -Format "yyyyMMdd"
$zip   = Join-Path $Backups "GFL-backup-$stamp.zip"
if(-not (Test-Path $zip)){
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  function ZipFolder($src,$dst){
    if(Test-Path $dst){ Remove-Item $dst -Force }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($src,$dst)
  }
  $tmp = Join-Path $Backups ("tmp-"+[guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  Copy-Item "C:\GFL-System\Scripts"  -Destination (Join-Path $tmp "Scripts")  -Recurse -Force -ErrorAction SilentlyContinue
  Copy-Item "C:\GFL-System\Configs"  -Destination (Join-Path $tmp "Configs")  -Recurse -Force -ErrorAction SilentlyContinue
  Copy-Item "C:\GFL-System\Reports"  -Destination (Join-Path $tmp "Reports")  -Recurse -Force -ErrorAction SilentlyContinue
  ZipFolder $tmp $zip
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
# prune old backups
Get-ChildItem $Backups -File | Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-1*$KeepDays) } | Remove-Item -Force -ErrorAction SilentlyContinue
