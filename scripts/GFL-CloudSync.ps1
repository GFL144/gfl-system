[CmdletBinding()] param()
# Compat wrapper: delegate to CloudSync-Plus (no token errors)
$p = Join-Path 'C:\GFL-System\Scripts' 'GFL-CloudSync-Plus.ps1'
if (!(Test-Path $p)) { throw "Missing CloudSync-Plus.ps1 at $p" }
# Upload logs and scripts by default; keep quiet on errors
try {
  pwsh -NoProfile -ExecutionPolicy Bypass -File "$p" -UploadLogs -UploadScripts | Out-Null
} catch {
  Write-Warning "CloudSync-Plus run failed: $(.Exception.Message)"
}
