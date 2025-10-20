function Ensure-Dir([string]$p){
  if ([string]::IsNullOrWhiteSpace($p)) { return }
  if (-not (Test-Path -Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

function JLoad([string]$path,[object]$default=$null){
  if ([string]::IsNullOrWhiteSpace($path)) { return $default }
  if (-not (Test-Path -Path $path))        { return $default }
  $s = Get-Content -Path $path -Raw -ErrorAction SilentlyContinue
  if ([string]::IsNullOrWhiteSpace($s))     { return $default }
  try { return ($s | ConvertFrom-Json -Depth 50) } catch { return $default }
}

function JSave($o,[string]$path){
  if ([string]::IsNullOrWhiteSpace($path)) { throw "JSave: path is empty" }
  $dir = Split-Path -Path $path -Parent
  if (-not [string]::IsNullOrWhiteSpace($dir)) { Ensure-Dir $dir }
  ($o | ConvertTo-Json -Depth 50) | Set-Content -Path $path -Encoding UTF8
}

function ALog([string]$msg,[string]$tag='APP'){
  $ts = [DateTimeOffset]::Now.ToString('yyyy-MM-ddTHH:mm:ss.ffffK')
  $line = "$ts [$tag] $msg"
  Write-Host $line
  $base = $PSScriptRoot
  if ([string]::IsNullOrWhiteSpace($base)) {
    try { $base = Split-Path -Parent $MyInvocation.MyCommand.Path } catch { $base = $null }
  }
  if (-not [string]::IsNullOrWhiteSpace($base)) {
    $groot   = Split-Path -Parent $base
    $reports = Join-Path $groot 'Reports'
    $audit   = Join-Path $reports 'audit'
    Ensure-Dir $audit
    $logFile = Join-Path $audit ("{0}_{1}.log" -f $tag.ToUpper(),(Get-Date -UFormat %Y%m%d))
    Add-Content -Path $logFile -Value $line
  }
}




