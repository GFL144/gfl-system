param([switch]$EnsureSchedules)
Import-Module (Join-Path $PSScriptRoot "GFL.Common.psm1") -Force
$ErrorActionPreference='Stop'
$Dash = Join-Path $PSScriptRoot 'GFL-Diagnostics-And-Dashboard.ps1'
if(Test-Path $Dash){ & $Dash }
$index = Join-Path (Join-Path $GflRoot 'Dashboards') 'Main\index.html'
if(Test-Path $index){ Start-Process $index }
if($EnsureSchedules){
  $ps='PowerShell.exe'
  schtasks /Create /TN "GFL-Dashboard-Rebuild" /TR "$ps -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$($Dash)`"" /SC HOURLY /RU SYSTEM /F | Out-Null
  Write-Host "Scheduled task ensured." -ForegroundColor Green
}
Write-Host "Mission complete." -ForegroundColor Green




