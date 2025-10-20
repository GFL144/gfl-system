[CmdletBinding()] param([switch]$RunAll)
$Root="C:\GFL-System\Scripts"
$Steps=@(
  "GFL-CoreBootstrap.ps1",
  "GFL-FullAutoUpdate.ps1",
  "GFL-AutoUpdate.ps1",
  "GFL-CloudSync.ps1",
  "GFL-FutureAI.ps1"
)
foreach($s in $Steps){
  $p=Join-Path $Root $s
  if(Test-Path $p){
    Write-Host "  Running $s..."
    pwsh -NoProfile -ExecutionPolicy Bypass -File $p -Run
  } else {
    Write-Warning "$s missing!"
  }
}
Write-Host " Master orchestration cycle complete."
