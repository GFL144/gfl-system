[CmdletBinding()] param([int]$Port=8791,[switch]$StartDashboard)

$Root   = "C:\GFL-System"
$Reports= Join-Path $Root "Reports"
$Logs   = Join-Path $Reports "logs"
$Status = Join-Path $Reports "status.json"
$Tasks  = Join-Path $Logs "tasks.json"

New-Item -ItemType Directory -Force -Path $Reports,$Logs | Out-Null
if (!(Test-Path $Status)) { '{"ok":true}' | Out-File $Status -Encoding UTF8 }

Add-Type -AssemblyName System.Net.HttpListener
$prefix = "http://+:$Port/"

function Ensure-UrlAcl([string]$u) {
  try { Start-Process cmd -Args "/c","netsh http add urlacl url=$u user=Everyone" -WindowStyle Hidden -Wait } catch {}
}

function Start-Server {
  Ensure-UrlAcl $prefix
  $h = New-Object System.Net.HttpListener
  $h.Prefixes.Add($prefix)
  try { $h.Start(); Write-Host "Dashboard -> http://localhost:$Port/" } catch { Write-Warning $_; return }
  while ($h.IsListening) {
    try {
      $ctx = $h.GetContext()
      $req = $ctx.Request
      $res = $ctx.Response
      $path = $req.Url.AbsolutePath.ToLowerInvariant()

      $bytes = $null
      $res.ContentType = 'application/json'

      if ($path -eq '/' -or $path -eq '/index.html') {
        $html = '<!doctype html><meta charset=utf-8><title>GFL</title><h1>GFL Micro</h1><ul><li><a href="/api/status">/api/status</a></li><li><a href="/api/tasks">/api/tasks</a></li></ul>'
        $bytes = [Text.Encoding]::UTF8.GetBytes($html)
        $res.ContentType = 'text/html'
      }
      elseif ($path -eq '/api/status') {
        $bytes = [Text.Encoding]::UTF8.GetBytes((Get-Content $Status -Raw))
      }
      elseif ($path -eq '/api/status/ping') {
        $msg = [Uri]::UnescapeDataString($req.QueryString['msg'])
        $now = (Get-Date).ToString('s')
        "{""ts"":""$now"",""msg"":""$msg""}" | Set-Content $Status -Encoding UTF8
        $bytes = [Text.Encoding]::UTF8.GetBytes('{"ok":true}')
      }
      elseif ($path -eq '/api/tasks') {
        if (!(Test-Path $Tasks)) { '[]' | Out-File $Tasks -Encoding UTF8 }
        $bytes = [Text.Encoding]::UTF8.GetBytes((Get-Content $Tasks -Raw))
      }
      else {
        $bytes = [Text.Encoding]::UTF8.GetBytes('{"ok":true}')
      }

      $res.OutputStream.Write($bytes,0,$bytes.Length)
      $res.Close()
    }
    catch { Start-Sleep -Milliseconds 150 }
  }
}

Start-Server
