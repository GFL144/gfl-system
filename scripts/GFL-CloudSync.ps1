[CmdletBinding()] param([switch]$Run)
$Root = "C:\GFL-System"
$Logs = Join-Path $Root "Reports\logs"
$tokenPath = Join-Path $env:USERPROFILE ".github_token"

function Get-GitHubTokenPlain {
  if(!(Test-Path $tokenPath)){return $null}
  try {
    $enc = Get-Content $tokenPath -Raw
    $sec = ConvertTo-SecureString $enc
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    return $plain
  } catch { return $null }
}

$token = Get-GitHubTokenPlain
if(-not $token){ Write-Warning "GitHub token not found or unreadable."; return }

$repo='GFL-System/Reports'
$Headers=@{Authorization="token $token";'User-Agent'='GFL-System'}

Get-ChildItem $Logs -File | ForEach-Object {
  $b64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($_.FullName))
  $body=@{message="Auto log sync";content=$b64}|ConvertTo-Json
  try {
    Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/logs/$($_.Name)" `
      -Headers $Headers -Method PUT -Body $body
    Write-Host " Uploaded $($_.Name)"
  } catch {
    Write-Warning "Upload failed for $($_.Name): $($_.Exception.Message)"
  }
}
