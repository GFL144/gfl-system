[CmdletBinding()] param([int]$Port = 8791)
$Root='C:\GFL-System'
$Reports=Join-Path $Root 'Reports'
$Status=Join-Path $Reports 'status.json'
$listener=[System.Net.HttpListener]::new()
$prefix="http://localhost:$Port/"
$listener.Prefixes.Add($prefix)
try{ $listener.Start(); Write-Host "  Dashboard  $prefix" } catch { Write-Warning $_; return }

while($listener.IsListening){
    $ctx=$listener.GetContext()
    $req=$ctx.Request; $resp=$ctx.Response
    $data=(if(Test-Path $Status){Get-Content $Status -Raw}else{"{}"})
    $bytes=[Text.Encoding]::UTF8.GetBytes($data)
    $resp.ContentType='application/json'
    $resp.OutputStream.Write($bytes,0,$bytes.Length)
    $resp.Close()
}
