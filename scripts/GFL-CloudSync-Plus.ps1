[CmdletBinding()]
param(
  [switch]$UploadLogs,
  [switch]$UploadScripts,
  [switch]$DownloadScripts,
  [string]$Owner = 'GFL144',
  [string]$Repo  = 'GFL-System'
)

$ErrorActionPreference = 'Stop'
function Get-GFLTokenPlain {
  $plainPath = Join-Path $env:APPDATA 'GFL\.github_token_plain'
  if (Test-Path $plainPath) { return (Get-Content $plainPath -Raw).Trim() }
  $dpapiPath = Join-Path $env:USERPROFILE '.github_token'
  if (Test-Path $dpapiPath) {
    try {
      $enc = Get-Content $dpapiPath -Raw
      $sec = ConvertTo-SecureString $enc
      $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
      try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
      finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    } catch {}
  }
  return $null
}

$token = Get-GFLTokenPlain
if (-not $token) { throw "GitHub token not found." }
$Headers = @{ Authorization = "token $token"; 'User-Agent' = 'GFL-System' }
$OwnerRepo = "$Owner/$Repo"

function Set-GitHubContent {
  param([string]$OwnerRepo,[string]$Path,[byte[]]$Bytes,[string]$Message,[string]$Branch)
  $b64 = [Convert]::ToBase64String($Bytes)
  $uri = "https://api.github.com/repos/$OwnerRepo/contents/$Path"
  if ($Branch) { $uri += "?ref=$Branch" }
  $sha = $null
  try {
    $existing = Invoke-RestMethod -Uri $uri -Headers $Headers -ErrorAction Stop
    $sha = $existing.sha
  } catch {
    if ($_.Exception.Response.StatusCode.value__ -ne 404) { throw }
  }
  $payload = @{ message = $Message; content = $b64 }
  if ($sha) { $payload.sha = $sha }
  if ($Branch) { $payload.branch = $Branch }
  $json = $payload | ConvertTo-Json
  Invoke-RestMethod -Uri $uri -Headers $Headers -Method PUT -Body $json -ErrorAction Stop
}

function Get-GitHubFileBytes { param([string]$OwnerRepo,[string]$Path)
  $uri = "https://api.github.com/repos/$OwnerRepo/contents/$Path"
  $resp = Invoke-RestMethod -Uri $uri -Headers $Headers -ErrorAction Stop
  [Convert]::FromBase64String($resp.content)
}
function Get-GitHubDir { param([string]$OwnerRepo,[string]$Path)
  Invoke-RestMethod -Uri "https://api.github.com/repos/$OwnerRepo/contents/$Path" -Headers $Headers -ErrorAction Stop
}

$Root = "C:\GFL-System"
$LogsDir = Join-Path $Root "Reports\logs"
$ScriptsDir = Join-Path $Root "Scripts"
New-Item -ItemType Directory -Force -Path $LogsDir,$ScriptsDir | Out-Null

if ($UploadLogs) {
  $files = Get-ChildItem $LogsDir -File
  foreach ($f in $files) {
    try {
      Set-GitHubContent -OwnerRepo $OwnerRepo -Path "logs/$($f.Name)" -Bytes ([IO.File]::ReadAllBytes($f.FullName)) -Message "CloudSync: $($f.Name)" | Out-Null
      Write-Host " Logs: $($f.Name)"
    } catch { Write-Warning "Log upload failed $($f.Name): $($_.Exception.Message)" }
  }
}

if ($UploadScripts) {
  $files = Get-ChildItem $ScriptsDir -Filter *.ps1 -File
  foreach ($f in $files) {
    if ($f.Name -match 'token' -and $f.Name -match '\.ps1$') { Write-Host " Skipping $($f.Name)"; continue }
    try {
      Set-GitHubContent -OwnerRepo $OwnerRepo -Path "scripts/$($f.Name)" -Bytes ([IO.File]::ReadAllBytes($f.FullName)) -Message "CloudSync: $($f.Name)" | Out-Null
      Write-Host " Script: $($f.Name)"
    } catch { Write-Warning "Script upload failed $($f.Name): $($_.Exception.Message)" }
  }
}

if ($DownloadScripts) {
  try {
    $items = Get-GitHubDir -OwnerRepo $OwnerRepo -Path 'scripts'
  } catch {
    Write-Warning "No 'scripts' folder found in repo $OwnerRepo."
    return
  }
  foreach ($it in $items) {
    if ($it.type -ne 'file' -or -not ($it.name -like '*.ps1')) { continue }
    try {
      $bytes = Get-GitHubFileBytes -OwnerRepo $OwnerRepo -Path $it.path
      $local = Join-Path $ScriptsDir $it.name
      if (Test-Path $local) { Copy-Item $local "$local.bak" -Force }
      [IO.File]::WriteAllBytes($local, $bytes)
      Write-Host " Script: $($it.name)  $local"
    } catch { Write-Warning "Script download failed $($it.name): $($_.Exception.Message)" }
  }
  Write-Host " Scripts downloaded. Re-run your orchestrator if needed."
}
