[CmdletBinding()] param([switch]$Run)
if (-not $Run) { return }
Write-Host "[CoreBootstrap] Initializing GFL core folders and configs..."
$root = "C:\GFL-System"
$paths = "Configs","AI","Reports","Reports\logs","Reports\artifacts"
foreach($p in $paths){ New-Item -ItemType Directory -Force -Path (Join-Path $root $p) | Out-Null }
Write-Host "[CoreBootstrap]  Core structure ready."
