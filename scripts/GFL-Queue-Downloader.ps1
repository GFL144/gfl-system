[CmdletBinding()]
param(
  [string]$Root='C:\GFL-System',
  [string]$Queue='C:\GFL-System\Manifests\queue.txt',
  [string]$Registry='C:\GFL-System\Manifests\url-registry.json',
  [string]$Staging='C:\GFL-System\Staging\Discovery',
  [int]$Parallel=8,
  [int]$TimeoutSec=45,
  [int]$MaxRetries=3,
  [int]$DomainDelayMs=200,
  [switch]$UploadAfter
)

$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

function W { param([string]$m,[string]$lvl='INFO')
  $line = ('[{0}] {1}: {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$lvl,$m)
  $line | Tee-Object -FilePath $log -Append
}
function Get-Command { param([string]$n) Get-Command $n -ErrorAction SilentlyContinue }

$reports = Join-Path $Root 'Reports'
$logs    = Join-Path $reports 'logs'
$art     = Join-Path $reports 'artifacts'
$log     = Join-Path $logs 'queue-downloader.log'
$metaDir = Join-Path $Staging 'Meta'
$baseOut = Join-Path $Staging 'Fetched'
New-Item -ItemType Directory -Force -Path $reports,$logs,$art,$Staging,$metaDir,$baseOut | Out-Null

$HaveAria2  = [bool](Get-Command 'aria2c')
$HaveRclone = [bool](Get-Command 'rclone')

if(!(Test-Path $Queue)){ throw "Queue not found: $Queue" }
$reg=@{}; if(Test-Path $Registry){ $reg=Get-Content $Registry -Raw | ConvertFrom-Json }

$all = Get-Content $Queue | Where-Object { $_ -and ($_ -notmatch '^\s*#') } | Sort-Object -Unique
W ("Queue items: {0}" -f $all.Count)

# batch splitter
$chunks = @()
for($i=0; $i -lt $all.Count; $i += [Math]::Max($Parallel,1)){
  $chunks += ,($all[$i..([Math]::Min($i+$Parallel-1,$all.Count-1))])
}

$jobs = foreach($urls in $chunks){
  Start-ThreadJob -ArgumentList @($urls,$baseOut,$TimeoutSec,$HaveAria2,$MaxRetries,$DomainDelayMs,$metaDir) -ScriptBlock {
    param(,,,,,,)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# Ensure per-job folders (job scope doesn't always inherit)
New-Item -ItemType Directory -Force -Path , | Out-Null

# HttpClient with a friendly UA (GitHub/Learn/MSFT/CDNs dislike empty UA)
 = [System.Net.Http.HttpClientHandler]::new()
.AllowAutoRedirect = \True
\ = [System.Net.Http.HttpClient]::new(\)
\.Timeout = [TimeSpan]::FromSeconds(\)
\.DefaultRequestHeaders.UserAgent.ParseAdd('GFLFetcher/1.0 (+https://example.local)') | Out-Null

        $http.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
    $perDomainLast = @{}

    function Wait-Domain([string]$host){
      if(-not $perDomainLast.ContainsKey($host)){ $perDomainLast[$host] = Get-Date 0 }
      $delta = (Get-Date) - $perDomainLast[$host]
      if($delta.TotalMilliseconds -lt $DomainDelayMs){
        Start-Sleep -Milliseconds ($DomainDelayMs - [int]$delta.TotalMilliseconds)
      }
      $perDomainLast[$host] = Get-Date
    }

    function Get-Paths([string]\){
  # Normalize GitHub 'blob' to 'raw' for direct content
  try {
    if (\ -match '^https://github\.com/.+/blob/.+') {
      \ = \ -replace '/blob/','/raw/'
    }
  } catch {}

  \ = [Uri]\
  \ = (\.Host + \.AbsolutePath) -replace '/','\'
  if ([string]::IsNullOrWhiteSpace([IO.Path]::GetExtension(\))) { \ = Join-Path \ 'index.html' }
  \ = Join-Path \ \
  \ = \ + '.meta.json'
  \ = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(\)) -replace '=+\
      $out = Join-Path $baseOut $rel
      $sidecar = $out + '.meta.json'
      $metaKey = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Url)) -replace '=+$',''
      $central = Join-Path $metaDir ($metaKey + '.json')
      @{ out=$out; sidecar=$sidecar; central=$central; host=$u.Host }
    }

    function Load-Meta([string]$side,[string]$central){
      try{
        if(Test-Path $central){ return Get-Content $central -Raw | ConvertFrom-Json }
        if(Test-Path $side){ return Get-Content $side -Raw | ConvertFrom-Json }
      }catch{}
      $null
    }

    function Save-Meta([string]$side,[string]$central,[hashtable]$meta){
      $json = ($meta | ConvertTo-Json -Depth 6)
      New-Item -ItemType Directory -Force -Path (Split-Path $side) -ErrorAction SilentlyContinue | Out-Null
      $json | Set-Content -Path $side -Encoding UTF8
      $json | Set-Content -Path $central -Encoding UTF8 -ErrorAction SilentlyContinue
    }

    function Save-FileHttp([string]$Url,[string]$OutFile,[string]$side,[string]$central,[int]$MaxRetries){
      $meta = Load-Meta $side $central
      $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $Url)
      if($meta){
        if($meta.ETag){ $req.Headers.TryAddWithoutValidation('If-None-Match',$meta.ETag) | Out-Null }
        if($meta.LastModified){ $req.Headers.TryAddWithoutValidation('If-Modified-Since',$meta.LastModified) | Out-Null }
      }

      $attempt=0
      while($attempt -le $MaxRetries){
        try{
          $attempt++
          $resp = $http.SendAsync($req).GetAwaiter().GetResult()
          $status = [int]$resp.StatusCode
          if($status -eq 304){ return @{ ok=$true; skipped=$true; status=304 } }
          if($status -ge 200 -and $status -lt 300){
            $bytes = $resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null
            [IO.File]::WriteAllBytes($OutFile,$bytes)
            $newMeta = @{
              Url          = $Url
              Retrieved    = (Get-Date).ToString('o')
              ETag         = $resp.Headers.ETag.Tag
              LastModified = ($resp.Content.Headers.LastModified) ? ($resp.Content.Headers.LastModified.Value.ToString('r')) : $null
              ContentType  = $resp.Content.Headers.ContentType.ToString()
              Length       = $bytes.Length
              Status       = $status
            }
            Save-Meta $side $central $newMeta
            return @{ ok=$true; skipped=$false; status=$status }
          }
          if($attempt -le $MaxRetries){
            Start-Sleep -Milliseconds ([int][Math]::Min(30000, (200 * [Math]::Pow(2,$attempt))))
            continue
          }
          return @{ ok=$false; skipped=$false; status=$status }
        }catch{
          if($attempt -le $MaxRetries){
            Start-Sleep -Milliseconds ([int][Math]::Min(30000, (200 * [Math]::Pow(2,$attempt))))
            continue
          }
          return @{ ok=$false; skipped=$false; status=-1 }
        }
      }
    }

    function Save-File([string]$Url,[string]$OutFile,[string]$side,[string]$central,[string]$host){
      Wait-Domain $host
      if($HaveAria2){
        $args=@('--max-connection-per-server=8','--min-split-size=1M','--file-allocation=none','--allow-overwrite=true',
                '-d',(Split-Path $OutFile),'-o',(Split-Path -Leaf $OutFile),$Url)
        $p = Start-Process aria2c -ArgumentList $args -Wait -PassThru
        if($p.ExitCode -eq 0){
          $m=@{ Url=$Url; Retrieved=(Get-Date).ToString('o'); Tool='aria2c' }
          Save-Meta $side $central $m
          return @{ ok=$true; skipped=$false; status=200 }
        }
      }
      return (Save-FileHttp $Url $OutFile $side $central $MaxRetries)
    }

    $ok=0; $fail=0; $skip304=0
    foreach($u in $urls){
      try{
        $p = Get-Paths $u
        $res = Save-File $($p.url) $p.out $($p.sidecar) $($p.central) $($p.host)
        if($res.ok){ if($res.skipped){ $skip304++ } else { $ok++ } } else { $fail++ }
      }catch{ $fail++ }
    }
    [pscustomobject]@{ ok=$ok; fail=$fail; skip=$skip304 }
  }
}

Receive-Job -Job $jobs -Wait -AutoRemoveJob | ForEach-Object {
  W ("Batch OK={0} FAIL={1} NOTMOD={2}" -f $_.ok,$_.fail,$_.skip)
}

Copy-Item -Force $log (Join-Path $art 'queue-downloader.log') -ErrorAction SilentlyContinue
if($UploadAfter -and $HaveRclone){
  W "Uploading artifacts via rclone..."
  $p=Start-Process rclone -ArgumentList @('copy',$art,'gfl-remote:reports','--progress') -Wait -PassThru
  if($p.ExitCode -ne 0){ W "rclone upload failed (non-zero exit)" 'WARN' }
}
W "Queue download complete."

,''
  \ = Join-Path \ (\ + '.json')
  @{ out=\; sidecar=\; central=\; host=\.Host; url=\ }
}
      $out = Join-Path $baseOut $rel
      $sidecar = $out + '.meta.json'
      $metaKey = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Url)) -replace '=+$',''
      $central = Join-Path $metaDir ($metaKey + '.json')
      @{ out=$out; sidecar=$sidecar; central=$central; host=$u.Host }
    }

    function Load-Meta([string]$side,[string]$central){
      try{
        if(Test-Path $central){ return Get-Content $central -Raw | ConvertFrom-Json }
        if(Test-Path $side){ return Get-Content $side -Raw | ConvertFrom-Json }
      }catch{}
      $null
    }

    function Save-Meta([string]$side,[string]$central,[hashtable]$meta){
      $json = ($meta | ConvertTo-Json -Depth 6)
      New-Item -ItemType Directory -Force -Path (Split-Path $side) -ErrorAction SilentlyContinue | Out-Null
      $json | Set-Content -Path $side -Encoding UTF8
      $json | Set-Content -Path $central -Encoding UTF8 -ErrorAction SilentlyContinue
    }

    function Save-FileHttp([string]$Url,[string]$OutFile,[string]$side,[string]$central,[int]$MaxRetries){
      $meta = Load-Meta $side $central
      $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $Url)
      if($meta){
        if($meta.ETag){ $req.Headers.TryAddWithoutValidation('If-None-Match',$meta.ETag) | Out-Null }
        if($meta.LastModified){ $req.Headers.TryAddWithoutValidation('If-Modified-Since',$meta.LastModified) | Out-Null }
      }

      $attempt=0
      while($attempt -le $MaxRetries){
        try{
          $attempt++
          $resp = $http.SendAsync($req).GetAwaiter().GetResult()
          $status = [int]$resp.StatusCode
          if($status -eq 304){ return @{ ok=$true; skipped=$true; status=304 } }
          if($status -ge 200 -and $status -lt 300){
            $bytes = $resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null
            [IO.File]::WriteAllBytes($OutFile,$bytes)
            $newMeta = @{
              Url          = $Url
              Retrieved    = (Get-Date).ToString('o')
              ETag         = $resp.Headers.ETag.Tag
              LastModified = ($resp.Content.Headers.LastModified) ? ($resp.Content.Headers.LastModified.Value.ToString('r')) : $null
              ContentType  = $resp.Content.Headers.ContentType.ToString()
              Length       = $bytes.Length
              Status       = $status
            }
            Save-Meta $side $central $newMeta
            return @{ ok=$true; skipped=$false; status=$status }
          }
          if($attempt -le $MaxRetries){
            Start-Sleep -Milliseconds ([int][Math]::Min(30000, (200 * [Math]::Pow(2,$attempt))))
            continue
          }
          return @{ ok=$false; skipped=$false; status=$status }
        }catch{
          if($attempt -le $MaxRetries){
            Start-Sleep -Milliseconds ([int][Math]::Min(30000, (200 * [Math]::Pow(2,$attempt))))
            continue
          }
          return @{ ok=$false; skipped=$false; status=-1 }
        }
      }
    }

    function Save-File([string]$Url,[string]$OutFile,[string]$side,[string]$central,[string]$host){
      Wait-Domain $host
      if($HaveAria2){
        $args=@('--max-connection-per-server=8','--min-split-size=1M','--file-allocation=none','--allow-overwrite=true',
                '-d',(Split-Path $OutFile),'-o',(Split-Path -Leaf $OutFile),$Url)
        $p = Start-Process aria2c -ArgumentList $args -Wait -PassThru
        if($p.ExitCode -eq 0){
          $m=@{ Url=$Url; Retrieved=(Get-Date).ToString('o'); Tool='aria2c' }
          Save-Meta $side $central $m
          return @{ ok=$true; skipped=$false; status=200 }
        }
      }
      return (Save-FileHttp $Url $OutFile $side $central $MaxRetries)
    }

    $ok=0; $fail=0; $skip304=0
    foreach($u in $urls){
      try{
        $p = Get-Paths $u
        $res = Save-File $($p.url) $p.out $($p.sidecar) $($p.central) $($p.host)
        if($res.ok){ if($res.skipped){ $skip304++ } else { $ok++ } } else { $fail++ }
      }catch{ $fail++ }
    }
    [pscustomobject]@{ ok=$ok; fail=$fail; skip=$skip304 }
  }
}

Receive-Job -Job $jobs -Wait -AutoRemoveJob | ForEach-Object {
  W ("Batch OK={0} FAIL={1} NOTMOD={2}" -f $_.ok,$_.fail,$_.skip)
}

Copy-Item -Force $log (Join-Path $art 'queue-downloader.log') -ErrorAction SilentlyContinue
if($UploadAfter -and $HaveRclone){
  W "Uploading artifacts via rclone..."
  $p=Start-Process rclone -ArgumentList @('copy',$art,'gfl-remote:reports','--progress') -Wait -PassThru
  if($p.ExitCode -ne 0){ W "rclone upload failed (non-zero exit)" 'WARN' }
}
W "Queue download complete."

















