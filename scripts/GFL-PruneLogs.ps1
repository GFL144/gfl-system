$ErrorActionPreference='Stop'
$Logs = Join-Path 'C:\GFL-System' 'Logs'
$keep = 30
$files = Get-ChildItem $Logs -File -EA SilentlyContinue | Sort-Object LastWriteTime -Descending
if($files.Count -gt $keep){ $files[$keep..($files.Count-1)] | Remove-Item -Force -EA SilentlyContinue }
