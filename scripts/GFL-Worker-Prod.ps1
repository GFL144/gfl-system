param([string]$TaskJson)
$t = $TaskJson | ConvertFrom-Json
function Ping-Url($u){ try{ (Invoke-WebRequest -UseBasicParsing -Uri $u -TimeoutSec 3).StatusCode }catch{ 0 } }
switch($t.kind){
  'http-probe' {
    $u = $t.args.url
    @{ url=$u; status=(Ping-Url $u); ts=(Get-Date).ToString('o') } | ConvertTo-Json
  }
  default { 'unsupported' }
}
