[CmdletBinding()]
param(
  [switch]$UploadLogs,
  [switch]$UploadScripts,
  [switch]$DownloadScripts,
  [string]$Owner = 'GFL144',
  [string]$Repo  = 'GFL-System'
)
$ErrorActionPreference='Stop'

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

function Set-GHFile([string]$Path,[byte[]]$Bytes,[string]$Message){
  if (($Bytes).Length -eq 0) { Write-Host "  skip 0-byte """; return }
  $b64=[Convert]::ToBase64String($Bytes)
  $uri="https://api.github.com/repos/$OwnerRepo/contents/$Path"
  $sha=$null
  try { $sha=(Invoke-RestMethod -Uri $uri -Headers $Headers -ErrorAction Stop).sha } catch {
    if ($_.Exception.Response.StatusCode.value__ -ne 404) { throw }
  }
  $payload=@{ message=$Message; content=$b64 }
  if ($sha) { $payload.sha=$sha }
  Invoke-RestMethod -Uri $uri -Headers $Headers -Method PUT -Body ($payload|ConvertTo-Json) | Out-Null
}
function Get-GHDir([string]$Path){ Invoke-RestMethod -Uri "https://api.github.com/repos/$OwnerRepo/contents/$Path" -Headers $Headers }
function Get-GHFileBytes([string]$Path){ $o=Invoke-RestMethod -Uri "https://api.github.com/repos/$OwnerRepo/contents/$Path" -Headers $Headers; [Convert]::FromBase64String($o.content -replace '\s','') }

$Root="C:\GFL-System"
$Logs=Join-Path $Root "Reports\logs"
$Scripts=Join-Path $Root "Scripts"
New-Item -ItemType Directory -Force -Path $Logs,$Scripts | Out-Null

if ($UploadLogs) {
  $ok=0; $fail=0
  Get-ChildItem $Logs -File -ErrorAction SilentlyContinue | ForEach-Object {
    try { Set-GHFile -Path "logs/$($_.Name)" -Bytes ([IO.File]::ReadAllBytes($_.FullName)) -Message "sync: logs/$($_.Name)"; $ok++ }
    catch { $fail++; Write-Warning "log $($_.Name): $($_.Exception.Message)" }
  }
  Write-Host "Logs uploaded: $ok (failed: $fail)"
}
if ($UploadScripts) {
  $ok=0; $fail=0
  Get-ChildItem $Scripts -Filter *.ps1 -File -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -match 'savegithubtoken' -and $_ -match '\.ps1$') { Write-Host "  skip $($_.Name)"; return }
    try { Set-GHFile -Path "scripts/$($_.Name)" -Bytes ([IO.File]::ReadAllBytes($_.FullName)) -Message "sync: scripts/$($_.Name)"; $ok++ }
    catch { $fail++; Write-Warning "ps1 $($_.Name): $($_.Exception.Message)" }
  }
  Write-Host "Scripts uploaded: $ok (failed: $fail)"
}
if ($DownloadScripts) {
  try { $remote = Get-GHDir -Path 'scripts' } catch { Write-Warning "repo/scripts not found"; return }
  $ok=0; $fail=0
  foreach ($f in $remote) {
    if ($f.type -ne 'file' -or ($f.name -notlike '*.ps1')) { continue }
    try {
      $bytes = Get-GHFileBytes -Path ("scripts/" + $f.name)
      [IO.File]::WriteAllBytes((Join-Path $Scripts $f.name), $bytes); $ok++
    } catch { $fail++; Write-Warning "get $($f.name): $($_.Exception.Message)" }
  }
  Write-Host "Scripts downloaded: $ok (failed: $fail)"
}
