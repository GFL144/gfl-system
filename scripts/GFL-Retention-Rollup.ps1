[CmdletBinding()]
param(
  [string]$Root='C:\GFL-System',
  [int]$KeepLogs=14,         # days
  [int]$KeepArtifacts=30     # days
)
$ErrorActionPreference='Stop'
$Reports = Join-Path $Root 'Reports'
$Logs    = Join-Path $Reports 'logs'
$Art     = Join-Path $Reports 'artifacts'
$Rollup  = Join-Path $Reports 'rollup.json'
New-Item -ItemType Directory -Force -Path $Reports,$Logs,$Art | Out-Null

# prune
Get-ChildItem $Logs -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$KeepLogs) } | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem $Art  -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$KeepArtifacts) } | Remove-Item -Force -ErrorAction SilentlyContinue

$sum = [ordered]@{
  time     = (Get-Date).ToString('o')
  logs     = (Get-ChildItem $Logs -File -ErrorAction SilentlyContinue | Measure-Object).Count
  artifacts= (Get-ChildItem $Art  -File -ErrorAction SilentlyContinue | Measure-Object).Count
}
$sum | ConvertTo-Json -Depth 4 | Set-Content -Path $Rollup -Encoding UTF8
Write-Host "Retention/Rollup complete."


