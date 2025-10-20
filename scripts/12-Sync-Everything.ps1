param(
  [switch]$Push,
  [switch]$Pull,
  [switch]$ZipBackup,
  [int]$SplitMB = 0
)
$log = "C:\GFL-System\logs\sync_$(Get-Date -Format yyyyMMdd_HHmmss).log"
"== $(Get-Date) ==" | Out-File $log

if($Push){ Add-Content $log "PUSH: rclone copy logs/config -> remote (stub)" }
if($Pull){ Add-Content $log "PULL: rclone copy remote -> staging (stub)" }
if($ZipBackup){
  $zip = "C:\GFL-System\logs\backup_$(Get-Date -Format yyyyMMdd_HHmmss).zip"
  Compress-Archive -Path C:\GFL-System\config,C:\GFL-System\logs -DestinationPath $zip -Force
  if($SplitMB -gt 0){
    $bytes = [IO.File]::ReadAllBytes($zip)
    $chunk = $SplitMB * 1MB
    for($i=0; $i -lt $bytes.Length; $i += $chunk){
      $out = "{0}.part{1:D3}" -f $zip,$i/$chunk
      [IO.File]::WriteAllBytes($out, $bytes[$i..([Math]::Min($i+$chunk-1,$bytes.Length-1))])
    }
  }
  Add-Content $log "BACKUP: created $zip"
}
"OK" | Add-Content $log
