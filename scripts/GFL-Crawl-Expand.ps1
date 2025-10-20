[CmdletBinding()]
param(
  [string]$Root='C:\GFL-System',
  [string]$Seeds='C:\GFL-System\Manifests\seeds.txt',
  [string]$OutQueue='C:\GFL-System\Manifests\queue.txt',
  [int]$MaxPerHost=  800,
  [int]$TimeoutSec=  45
)
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$Reports = Join-Path $Root 'Reports'
$Logs    = Join-Path $Reports 'logs'
$Log     = Join-Path $Logs 'crawl-expand.log'
New-Item -ItemType Directory -Force -Path $Reports,$Logs | Out-Null

function W([string]$m,[string]$lvl='INFO'){
  ('[{0}] {1}: {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$lvl,$m) |
    Tee-Object -FilePath $Log -Append
}
if(!(Test-Path $Seeds)){ throw "Missing seeds: $Seeds" }

$rxHref = '<a\s+(?:[^>]*?\s+)?href\s*=\s*["'']([^"''#]+)["'']'
$http   = [System.Net.Http.HttpClient]::new()
$http.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)

# read seeds
$seedUrls = Get-Content $Seeds | Where-Object { $_ -and ($_ -notmatch '^\s*#') }
$frontier = New-Object System.Collections.Generic.Queue[string]
$seen     = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
$perHost  = @{}

foreach($s in $seedUrls){
  if($seen.Add($s)){ $frontier.Enqueue($s) }
}

$found = New-Object System.Collections.Generic.List[string]

while($frontier.Count -gt 0){
  $u = $frontier.Dequeue()
  try {
    W "GET $u"
    $resp = $http.GetAsync($u).GetAwaiter().GetResult()
    if(-not $resp.IsSuccessStatusCode){ continue }
    $html = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()

    # host limit
    $hHost = ([Uri]$u).Host.ToLowerInvariant()
    if(-not $perHost.ContainsKey($host)){ $perHost[\$hname] = 0 }

    # harvest links
    foreach($m in [regex]::Matches($html, $rxHref, [Text.RegularExpressions.RegexOptions]::IgnoreCase)){
      $href = $m.Groups[1].Value.Trim()
      # absolutize
      $abs = $href
      try { if(-not ([Uri]::IsWellFormedUriString($href,'Absolute'))){ $abs = [Uri]::new([Uri]$u,$href).AbsoluteUri } } catch { continue }

      # de-dupe + host budget
      if($seen.Contains($abs)){ continue }
      $absUri = [Uri]$abs
      $hHostTmp = $absUri.Host.ToLowerInvariant()
      if(-not $perHost.ContainsKey($h)){ $perHost[$hHostTmp] = 0 }
      if($perHost[$hHostTmp] -ge $MaxPerHost){ continue }

      $seen.Add($abs) | Out-Null
      $perHost[$hHostTmp]++
      $found.Add($abs)
    }
  } catch {
    W ("Fetch error: {0} => {1}" -f $u, $_.Exception.Message) 'WARN'
  }
}

# queue is seeds + discovered uniques
$queue = New-Object System.Collections.Generic.List[string]
foreach($s in $seedUrls){ if(-not [string]::IsNullOrWhiteSpace($s)){ $queue.Add($s) } }
foreach($x in $found){ $queue.Add($x) }

$queue = $queue | Sort-Object -Unique
$queue | Set-Content -Path $OutQueue -Encoding UTF8
W ("Wrote queue: {0} items -> {1}" -f $queue.Count,$OutQueue)









