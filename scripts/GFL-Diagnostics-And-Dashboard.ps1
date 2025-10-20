param()
Import-Module (Join-Path $PSScriptRoot "GFL.Common.psm1") -Force
$ErrorActionPreference='Stop'

$Reports = Join-Path $GflRoot 'Reports'
$DashRoot= Join-Path $GflRoot 'Dashboards'
$Main    = Join-Path $DashRoot 'Main'
$OutHtml = Join-Path $Main 'index.html'
New-Item -ItemType Directory -Force -Path $Reports,$DashRoot,$Main | Out-Null

$sys = Get-ComputerInfo | Select-Object CsName,OsName,OsVersion,WindowsVersion,OsArchitecture,CsNumberOfLogicalProcessors,OsInstallDate,OsUptime
$data = @{ system=$sys } | ConvertTo-Json -Depth 4

$now=Get-Date
$css='body{font-family:Segoe UI,Arial,sans-serif;background:#0b0f14;color:#e8eef7;margin:0} .wrap{padding:20px} .card{background:#0e1622;border:1px solid #1f2a3a;border-radius:14px;padding:16px;margin-bottom:16px}'
$html=@"
<!doctype html><html><meta charset='utf-8'/>
<title>GFL Dashboard $($now.ToString('yyyy-MM-dd HH:mm:ss'))</title>
<style>$css</style>
<div class='wrap'>
  <div class='card'><h2>GFL System Dashboard</h2>
    <div>Updated: $($now.ToString('yyyy-MM-dd HH:mm:ss'))</div>
  </div>
  <div class='card' id='sys'></div>
</div>
<script>
const D=$($data);
const s=D.system.[0]||{};
document.getElementById('sys').innerHTML =
  `<b>Machine:</b> \${s.CsName||''}<br><b>OS:</b> \${s.OsName||''}<br><b>Version:</b> \${s.OsVersion||''}<br><b>Windows:</b> \${s.WindowsVersion||''}<br><b>Arch:</b> \${s.OsArchitecture||''}<br><b>CPU Logical:</b> \${s.CsNumberOfLogicalProcessors||''}<br><b>Uptime:</b> \${s.OsUptime||''}`;
</script>
</html>
"@
$html | Set-Content -Encoding UTF8 $OutHtml
Write-Host "Dashboard written: $OutHtml" -ForegroundColor Green



