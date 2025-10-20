<# GFL-Dashboard-Server.ps1
   Serves:
     /           -> redirects to /dashboard
     /dashboard  -> Admin 3D UI (needs ?token=ADMIN_TOKEN)
     /public     -> Public 3D UI (no token)
     /api/snap   -> current metrics.json
     /api/hist   -> metrics.jsonl (tail=NN)
     /api/heal   -> triggers AutoHeal (admin token)
#>
param(
  [string]$ConfigPath = "C:\GFL-System\Configs\dashboard-config.json"
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Web
$cfg     = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$Root    = "C:\GFL-System"
$Reports = Join-Path $Root "Reports"
$Snap    = Join-Path $Reports "metrics.json"
$Hist    = Join-Path $Reports "metrics.jsonl"
$WWW     = Join-Path $Root "Dashboards\Network-3D"
$Admin   = Join-Path $WWW "admin.html"
$Public  = Join-Path $WWW "public.html"

$prefix = "http://localhost:{0}/" -f $cfg.port
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($prefix)
try { $listener.Start() } catch {
  Write-Host "Port in use or ACL missing. Try: netsh http add urlacl url=$prefix user=Everyone"
  throw
}
Write-Host "GFL Dashboard listening at $prefix"

function Read-Query($ctx){ [System.Web.HttpUtility]::ParseQueryString($ctx.Request.Url.Query) }
function Write-Json($ctx,$obj){
  $json = $obj | ConvertTo-Json -Depth 10
  $buf  = [System.Text.Encoding]::UTF8.GetBytes($json)
  $ctx.Response.ContentType = "application/json"
  $ctx.Response.ContentLength64 = $buf.Length
  $ctx.Response.OutputStream.Write($buf,0,$buf.Length)
  $ctx.Response.OutputStream.Close()
}
function Write-File($ctx,$path,$contentType="text/html"){
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $ctx.Response.ContentType = $contentType
  $ctx.Response.ContentLength64 = $bytes.Length
  $ctx.Response.OutputStream.Write($bytes,0,$bytes.Length)
  $ctx.Response.OutputStream.Close()
}
function Is-Admin($ctx){
  $q = Read-Query $ctx
  ($q["token"] -eq $cfg.adminToken)
}

while($listener.IsListening){
  $ctx = $listener.GetContext()
  try{
    $path = $ctx.Request.Url.AbsolutePath.TrimEnd("/")
    switch($path){
      "/" { $ctx.Response.Redirect("/dashboard"); $ctx.Response.Close() }
      "/dashboard" {
        if(Is-Admin $ctx){ Write-File $ctx $Admin "text/html" }
        else { $ctx.Response.StatusCode = 403; $ctx.Response.Close() }
      }
      "/public" { Write-File $ctx $Public "text/html" }

      "/api/snap" {
        if(Test-Path $Snap){ Write-File $ctx $Snap "application/json" }
        else { Write-Json $ctx @{ error="No metrics yet" } }
      }
      "/api/hist" {
        $q = Read-Query $ctx
        $tail = [int]($q["tail"] ? $q["tail"] : 200)
        if(Test-Path $Hist){
          $lines = Get-Content $Hist -Tail $tail
          Write-Json $ctx (@{ lines=$lines })
        } else { Write-Json $ctx @{ lines=@() } }
      }
      "/api/heal" {
        if(Is-Admin $ctx){
          Start-Process pwsh -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","C:\GFL-System\Scripts\GFL-AutoHeal.ps1" | Out-Null
          Write-Json $ctx @{ status="started" }
        } else { $ctx.Response.StatusCode = 403; $ctx.Response.Close() }
      }
      default {
        $ctx.Response.StatusCode = 404; $ctx.Response.Close()
      }
    }
  } catch {
    try{ $ctx.Response.StatusCode = 500; $ctx.Response.Close() } catch {}
  }
}








