param([string]$ConfigPath = 'C:\GFL-System\Configs\hypermill.json')
Add-Type -AssemblyName System.Web
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
if([string]::IsNullOrWhiteSpace($cfg.api.adminToken)){ $cfg.api.adminToken = [guid]::NewGuid().ToString('N'); ($cfg|ConvertTo-Json -Depth 10) | Out-File $ConfigPath -Encoding utf8 }
$port = [int]$cfg.api.port
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:/")
try{ $listener.Start() }catch{ Write-Host "Port busy: "; throw }
Write-Host "HyperMill API @ http://localhost:/"
function Read-Body($ctx){ try{ =New-Object IO.StreamReader($ctx.Request.InputStream,$ctx.Request.ContentEncoding); $b=.ReadToEnd(); if($b){ $b | ConvertFrom-Json } }catch{} }
function WriteJson($ctx,$obj){ $js=$obj|ConvertTo-Json -Depth 20; $buf=[Text.Encoding]::UTF8.GetBytes($js); $ctx.Response.ContentType="application/json"; $ctx.Response.ContentLength64=$buf.Length; $ctx.Response.OutputStream.Write($buf,0,$buf.Length); $ctx.Response.OutputStream.Close() }
function Auth($ctx){ $qs=[System.Web.HttpUtility]::ParseQueryString($ctx.Request.Url.Query); return ($qs["token"] -eq $cfg.api.adminToken) }

while(.IsListening){
  $ctx = $listener.GetContext()
  try{
    switch($ctx.Request.Url.AbsolutePath){
      '/status' { WriteJson $ctx (Get-Content 'C:\GFL-System\Reports\hypermill-status.json' -Raw | ConvertFrom-Json) }
      '/enqueue' {
        if(-not (Auth $ctx)){ $ctx.Response.StatusCode=403; $ctx.Response.Close(); break }
        $j = Read-Body $ctx
        if(-not $j -or -not $j.lane -or -not $j.kind){ WriteJson $ctx @{ ok=False; error="bad task" }; break }
        $laneDir = Join-Path 'C:\GFL-System\HyperMill\Queue' $j.lane
        if(-not (Test-Path $laneDir)){ WriteJson $ctx @{ ok=False; error="unknown lane" }; break }
        $id = ("{0:yyyyMMddHHmmssfff}-{1}.json" -f (Get-Date),[guid]::NewGuid().ToString('N'))
        $path = Join-Path $laneDir $id
        ($j | ConvertTo-Json -Depth 10) | Out-File $path -Encoding utf8
        WriteJson $ctx @{ ok=True; id=$id }
      }
      default { $ctx.Response.StatusCode=404; $ctx.Response.Close() }
    }
  } catch { try{ $ctx.Response.StatusCode=500; $ctx.Response.Close() }catch{} }
}
