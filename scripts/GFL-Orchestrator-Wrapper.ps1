[CmdletBinding()] param()
$ErrorActionPreference='Stop'
function Supports-Run([string]$Path){
  if (!(Test-Path $Path)) { return $false }
  try {
    $head = Get-Content $Path -TotalCount 120 -ErrorAction Stop | Out-String
    return [bool]($head -match '\[CmdletBinding\(\)\]\s*param\(\s*\[switch\]\')
  } catch { return $false }
}
function Safe-Run([string]$Name){
  $path = Join-Path 'C:\GFL-System\Scripts' $Name
  if (!(Test-Path $path)) { Write-Host " skip missing $Name"; return }
  $withRun = Supports-Run $path
  Write-Host " " -NoNewline
  try {
    if ($withRun) {
      Write-Host "  (-Run)"; pwsh -NoProfile -ExecutionPolicy Bypass -File "$path" -Run
    } else {
      Write-Host ""; pwsh -NoProfile -ExecutionPolicy Bypass -File "$path"
    }
  } catch { Write-Warning " failed: $(.Exception.Message)" }
}
Safe-Run 'GFL-CoreBootstrap.ps1'
Safe-Run 'GFL-FullAutoUpdate.ps1'
Safe-Run 'GFL-AutoUpdate.ps1'
# Use our compat wrapper instead of the legacy one’s internals
Safe-Run 'GFL-CloudSync.ps1'
Safe-Run 'GFL-FutureAI.ps1'
