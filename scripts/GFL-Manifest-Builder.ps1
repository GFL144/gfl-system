[CmdletBinding()]
param(
  [string]$Root = 'C:\GFL-System',
  [string]$Out  = 'C:\GFL-System\Manifests\core-manifest.json'
)
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$exclude = @('\Staging\','\Reports\logs\','\Reports\artifacts\','\Reports\health\')
$files = Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
  ($exclude | ForEach-Object { $_ }) -notcontains ($_.FullName -replace [regex]::Escape($Root),'') -and
  ($_.FullName -notmatch '\\Reports\\(logs|artifacts|health)\\')
}

$items = @()
foreach($f in $files){
  $rel = $f.FullName.Substring($Root.Length).TrimStart('\') -replace '\\','/'
  $sha = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  $items += [ordered]@{ path=$rel; sha256=$sha; source=$rel; size=$f.Length; mtime=$f.LastWriteTimeUtc.ToString('o') }
}

$obj = [ordered]@{ generated=(Get-Date).ToString('o'); root=$Root; files=$items }
$obj | ConvertTo-Json -Depth 6 | Set-Content -Path $Out -Encoding UTF8
Write-Host "Wrote manifest: $Out (files: $($items.Count))"


