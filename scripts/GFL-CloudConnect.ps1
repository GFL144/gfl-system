[CmdletBinding()]
param(
  [switch]$SetupAll,
  [switch]$SetupGitHub,
  [switch]$SetupGoogle,
  [string]$GoogleCredentialsPath = 'C:\GFL-System\Configs\google\credentials.json'
)

function Save-GitHubToken {
  $tokenSecure = Read-Host 'Enter GitHub Personal Access Token (PAT)' -AsSecureString
  if (-not $tokenSecure) { Write-Warning 'No token entered.'; return }
  $enc = $tokenSecure | ConvertFrom-SecureString
  $store = Join-Path $env:USERPROFILE '.github_token'
  $enc | Set-Content $store
  Write-Host "Saved encrypted GitHub token -> $store"
}

function Get-GitHubTokenPlain {
  $p = Join-Path $env:USERPROFILE '.github_token'
  if (!(Test-Path $p)) { return $null }
  try {
    return (Get-Content $p) | ConvertTo-SecureString | ConvertFrom-SecureString -AsPlainText
  } catch { return $null }
}

function Test-GitHubAuth {
  $token = Get-GitHubTokenPlain
  if (-not $token) { Write-Warning 'No stored GitHub token.'; return $false }
  try {
    $h = @{ Authorization = "token $token"; 'User-Agent'='GFL-System' }
    $me = Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers $h -ErrorAction Stop
    Write-Host "GitHub OK: $($me.login)"
    return $true
  } catch {
    Write-Warning "GitHub auth failed: $($_.Exception.Message)"
    return $false
  }
}

function Ensure-PSGoogleDrive {
  if (-not (Get-Module -ListAvailable | Where-Object { $_.Name -eq 'PSGoogleDrive' })) {
    try { Install-Module PSGoogleDrive -Scope CurrentUser -Force -AllowClobber } catch { Write-Warning "Install-Module PSGoogleDrive failed: $($_.Exception.Message)" }
  }
  Import-Module PSGoogleDrive -ErrorAction SilentlyContinue
}

function Setup-GoogleDrive {
  Ensure-PSGoogleDrive
  if (!(Get-Module | Where-Object { $_.Name -eq 'PSGoogleDrive' })) { Write-Warning 'PSGoogleDrive not available.'; return }
  if (!(Test-Path $GoogleCredentialsPath)) {
    Write-Host "Place your OAuth client credentials at: $GoogleCredentialsPath"
    Write-Host "Console: https://console.cloud.google.com/apis/library/drive.googleapis.com"
    return
  }
  try {
    Initialize-PSGoogleDrive -CredentialPath $GoogleCredentialsPath
    Write-Host 'Google Drive OAuth complete (token stored by module).'
  } catch {
    Write-Warning "Google Drive init failed: $($_.Exception.Message)"
  }
}

if ($SetupGitHub -or $SetupAll) { Save-GitHubToken; Test-GitHubAuth | Out-Null }
if ($SetupGoogle -or $SetupAll) { Setup-GoogleDrive }
