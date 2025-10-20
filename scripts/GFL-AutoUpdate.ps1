[CmdletBinding()] param([switch]$Run)
$Root="C:\GFL-System"
$Log=Join-Path $Root "Reports\logs\autoupdate-$(Get-Date -Format yyyyMMddHHmmss).log"
function W($m){("[{0}] {1}" -f (Get-Date -Format s),$m)|Tee-Object -FilePath $Log -Append}
W "AutoUpdate started"
try{
  pwsh -NoProfile -ExecutionPolicy Bypass -File "$Root\Scripts\GFL-FullAutoUpdate.ps1" -Run
  W "FullAutoUpdate executed successfully."
}catch{W "Error: $($_.Exception.Message)"}
W "AutoUpdate finished"
