[CmdletBinding()]
param([string]$Root='C:\GFL-System')

$ErrorActionPreference='Stop'

$Reports   = Join-Path $Root 'Reports'
$Health    = Join-Path $Reports 'health'
$Artifacts = Join-Path $Reports 'artifacts'
New-Item -ItemType Directory -Force -Path $Reports,$Health,$Artifacts | Out-Null

# Precompute values (no inline ifs inside the hashtable)
$mfPath        = Join-Path $Root 'Manifests\core-manifest.json'
$lastManifest  = if (Test-Path $mfPath) { (Get-Item $mfPath).LastWriteTimeUtc.ToString('o') } else { $null }
$totalFiles    = (Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
$stagingFiles  = (Get-ChildItem -Path (Join-Path $Root 'Staging') -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
$scriptsCount  = (Get-ChildItem -Path (Join-Path $Root 'Scripts') -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
$pwshVersion   = $PSVersionTable.PSVersion.ToString()

$stats = [ordered]@{
  time         = (Get-Date).ToString('o')
  pwsh         = $pwshVersion
  totalFiles   = $totalFiles
  stagingFiles = $stagingFiles
  scripts      = $scriptsCount
  lastManifest = $lastManifest
}

$path = Join-Path $Health 'health.json'
$stats | ConvertTo-Json -Depth 6 | Set-Content $path -Encoding UTF8
Copy-Item -Force $path (Join-Path $Artifacts 'health.json') -ErrorAction SilentlyContinue
Write-Host "Health written: $path"


