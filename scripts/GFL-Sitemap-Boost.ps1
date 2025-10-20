[CmdletBinding()]
param(
  [string]$Seeds='C:\GFL-System\Manifests\seeds.txt',
  [string]$OutAppend='C:\GFL-System\Manifests\seeds.txt',
  [int]$TimeoutSec=20
)
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$http=[System.Net.Http.HttpClient]::new(); $http.Timeout=[TimeSpan]::FromSeconds($TimeoutSec)

function Get-Text($url){
  try{ ($http.GetStringAsync($url)).GetAwaiter().GetResult() }catch{ $null }
}
function Get-Lines($s){ if([string]::IsNullOrWhiteSpace($s)){ @() } else { $s -split '\r?\n' } }

$seeds = Get-Content $Seeds | Where-Object { $_ -and ($_ -notmatch '^\s*#') }
$hosts = $seeds | ForEach-Object { try { ([Uri]$_).GetLeftPart([UriPartial]::Authority) } catch { $null } } | Sort-Object -Unique | Where-Object { $_ }

$acc = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)

foreach($root in $hosts){
  $site = $root.TrimEnd('/')
  $robots = Get-Text "$site/robots.txt"
  if($robots){
    foreach($ln in (Get-Lines $robots)){
      if($ln -match '^\s*Sitemap:\s*(\S+)\s*$'){ [void]$acc.Add($Matches[1]) }
    }
  }
  # common sitemap locations
  foreach($try in @("$site/sitemap.xml","$site/sitemap_index.xml")){ [void]$acc.Add($try) }
}

$urls = @()
foreach($sm in $acc){
  $xml = Get-Text $sm
  if(-not $xml){ continue }
  try{
    [xml]$doc = $xml
    $nsu = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
    $nsu.AddNamespace('sm','http://www.sitemaps.org/schemas/sitemap/0.9') | Out-Null
    # parent sitemaps
    $subs = $doc.SelectNodes('//sm:sitemap/sm:loc',$nsu)
    if($subs){ foreach($n in $subs){ $urls += $n.InnerText } }
    # direct URLs
    $locs = $doc.SelectNodes('//sm:url/sm:loc',$nsu)
    if($locs){ foreach($n in $locs){ $urls += $n.InnerText } }
  }catch{}
}

$urls = $urls | Where-Object { $_ } | Sort-Object -Unique
if($urls.Count -gt 0){
  Add-Content -Path $OutAppend -Value ($urls -join [Environment]::NewLine)
  Write-Host "Sitemap boost added $($urls.Count) URL(s) to $OutAppend"
}else{
  Write-Host "No sitemap URLs discovered."
}








