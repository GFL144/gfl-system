[CmdletBinding()] param([switch]$Run)
if (-not $Run) { Write-Host "`nUsage:`n pwsh -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Run`n"; return }

Write-Host "=== Phase-Delta: scanning for missing scripts ==="
$root = "C:\GFL-System\Scripts"
$needed = "GFL-FullAutoUpdate.ps1","GFL-AutoUpdate.ps1","GFL-CloudSync.ps1","GFL-FutureAI.ps1",
           "GFL-Master-Orchestrator.ps1","GFL-TaskBridge.ps1","GFL-Dashboard-Micro.ps1","GFL-IconGalaxy.ps1"
$missing = @()
foreach($n in $needed){ if(!(Test-Path (Join-Path $root $n))){ $missing += $n } }
if($missing.Count -eq 0){ Write-Host " All key scripts present."; exit }

Write-Host "Missing scripts:`n $($missing -join "`n ")`nAttempting repair..."
foreach($m in $missing){
  $url = "https://raw.githubusercontent.com/GregoGFL/SystemScripts/main/$m"
  try{
    Invoke-WebRequest -Uri $url -OutFile (Join-Path $root $m) -UseBasicParsing -TimeoutSec 90
    Write-Host "  Restored $m"
  }catch{
    Write-Warning "  Failed $m : $($_.Exception.Message)"
  }
}
Write-Host "=== Phase-Delta complete ==="
