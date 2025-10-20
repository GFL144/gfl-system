[CmdletBinding()]
param(
  [string]$Root='C:\GFL-System',
  [string]$ReportDir='C:\GFL-System\Reports',
  [string]$Staging='C:\GFL-System\Staging\Discovery',
  [string]$HarvestOut='C:\GFL-System\Manifests\harvested-urls.txt',
  [string]$ExtraQueue='C:\GFL-System\Manifests\extra-urls.txt',
  [string]$Mirrors='C:\GFL-System\Manifests\mirrors.txt',
  [switch]$Upload
)

$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

# Folders & logs
$Logs      = Join-Path $ReportDir 'logs'
$Artifacts = Join-Path $ReportDir 'artifacts'
$Log       = Join-Path $ReportDir 'discovery-fetch.log'
New-Item -ItemType Directory -Force -Path $ReportDir,$Logs,$Artifacts,$Staging | Out-Null

function W { param([string]$m,[string]$lvl='INFO')
  $line = ('[{0}] {1}: {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$lvl,$m)
  $line | Tee-Object -FilePath $Log -Append
}
function Get-Command { param([string]$n) Get-Command $n -ErrorAction SilentlyContinue }

$HaveAria2  = [bool](Get-Command 'aria2c')
$HaveGit    = [bool](Get-Command 'git')
$HaveRclone = [bool](Get-Command 'rclone')

# ------------------------
# 1) HARVEST URLS
# ------------------------
$urlPattern = '(https?://[^\s''"<>)\]]+)'
$urls = @()

Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object {
    $_.FullName -notlike '*\Reports\logs\*'      -and
    $_.FullName -notlike '*\Reports\artifacts\*' -and
    $_.FullName -notlike '*\Reports\health\*'    -and
    $_.FullName -notlike '*\Staging\*'
  } |
  ForEach-Object {
    $t = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
    if ($null -ne $t) {
      foreach ($m in [regex]::Matches($t,$urlPattern)) { $urls += $m.Value }
    }
  }

$urls = $urls | Sort-Object -Unique
$urls | Set-Content -Path $HarvestOut -Encoding UTF8
W ("Harvested {0} URL(s) -> {1}" -f $urls.Count,$HarvestOut)

# ------------------------
# 2) BUILD QUEUE
# ------------------------
$queue = @()
foreach ($p in @($HarvestOut,$ExtraQueue,$Mirrors)) {
  if (Test-Path $p) {
    $queue += (Get-Content $p | Where-Object { $_ -and ($_ -notmatch '^\s*#') })
  }
}
$queue = $queue | Sort-Object -Unique
W ("Queue size: {0}" -f $queue.Count)

# ------------------------
# 3) DOWNLOADER
# ------------------------
function Save-File {
  param([string]$Url,[string]$OutFile)
  New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null

  if ($HaveAria2) {
    $args=@('--max-connection-per-server=8','--min-split-size=1M','--file-allocation=none','--allow-overwrite=true',
            '-d',(Split-Path $OutFile),'-o',(Split-Path -Leaf $OutFile),$Url)
    $p=Start-Process aria2c -ArgumentList $args -Wait -PassThru
    return ($p.ExitCode -eq 0)
  }

  try {
    $job=Start-BitsTransfer -Source $Url -Destination $OutFile -Asynchronous -Priority Foreground
    while($job.JobState -in 'Connecting','Transferring'){ Start-Sleep -Milliseconds 250; $job=Get-BitsTransfer -Id $job.Id }
    if($job.JobState -eq 'Transferred'){ Complete-BitsTransfer -BitsJob $job; return $true }
    throw "BITS state: $($job.JobState)"
  } catch {
    try { Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 900; return (Test-Path $OutFile) }
    catch { W ("Download failed: {0} => {1}" -f $Url,$_.Exception.Message) 'ERROR'; return $false }
  }
}

function Is-GitHubRepoUrl([string]$u){
  return ($u -match '^https?://github\.com/[^/]+/[^/]+/?$' -or $u -match '^https?://github\.com/[^/]+/[^/]+\.git$')
}

# ------------------------
# 4) FETCH LOOP
# ------------------------
$dlOk=0; $dlFail=0
foreach($u in $queue){
  try{
    if([string]::IsNullOrWhiteSpace($u)){ continue }

    if(Is-GitHubRepoUrl $u){
      $repo  = ($u -replace '\.git$','').TrimEnd('/')
      $owner = ($repo -split '/')[3]; $name = ($repo -split '/')[4]
      $target = Join-Path $Staging ("github\{0}\{1}" -f $owner,$name)
      New-Item -ItemType Directory -Force -Path $target | Out-Null

      if($HaveGit){
        W ("git clone: {0}" -f $repo)
        $p=Start-Process git -ArgumentList @('clone','--depth','1',$repo,$target) -Wait -PassThru
        if($p.ExitCode -ne 0){
          W ("git clone failed, trying ZIP... {0}" -f $repo) 'WARN'
          $zipUrl = ("{0}/archive/refs/heads/main.zip" -f $repo)
          $zipOut = Join-Path $target 'repo.zip'
          if(Save-File -Url $zipUrl -OutFile $zipOut){
            Expand-Archive -Force -Path $zipOut -DestinationPath $target -ErrorAction SilentlyContinue
            Remove-Item $zipOut -Force -ErrorAction SilentlyContinue
          } else { $dlFail++; continue }
        }
        $dlOk++; continue
      } else {
        $zipUrl = ("{0}/archive/refs/heads/main.zip" -f $repo)
        $zipOut = Join-Path $target 'repo.zip'
        W ("ZIP fetch (no git): {0}" -f $zipUrl)
        if(Save-File -Url $zipUrl -OutFile $zipOut){
          Expand-Archive -Force -Path $zipOut -DestinationPath $target -ErrorAction SilentlyContinue
          Remove-Item $zipOut -Force -ErrorAction SilentlyContinue
          $dlOk++; continue
        } else { $dlFail++; continue }
      }
    }

    # Raw file
    $fileName = Split-Path -Leaf $u
    if([string]::IsNullOrWhiteSpace($fileName)){ $fileName = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($u)) }
    $outFile = Join-Path $Staging ("files\{0}" -f $fileName)
    if(Save-File -Url $u -OutFile $outFile){ $dlOk++ } else { $dlFail++ }
  }catch{
    W ("Queue item failed: {0} => {1}" -f $u,$_.Exception.Message) 'ERROR'
    $dlFail++
  }
}

# ------------------------
# 5) UPLOAD & SUMMARY
# ------------------------
Copy-Item -Force $Log -Destination (Join-Path $Artifacts 'discovery-fetch.log') -ErrorAction SilentlyContinue

if($Upload){
  if($HaveRclone){
    W "Uploading artifacts via rclone (reports/)"
    $p=Start-Process rclone -ArgumentList @('copy',$Artifacts,'gfl-remote:reports','--progress') -Wait -PassThru
    if($p.ExitCode -ne 0){ W "rclone upload failed (non-zero exit)" 'WARN' }
  } else {
    W "rclone not found; skipping upload. (You can run Multi-Fix -Upload after.)" 'WARN'
  }
}

$summary=[ordered]@{
  downloaded_ok       = $dlOk
  downloaded_failed   = $dlFail
  harvested_url_count = (Test-Path $HarvestOut) ? ((Get-Content $HarvestOut | Measure-Object -Line).Lines) : 0
  queue_size          = $queue.Count
  finished            = (Get-Date).ToString('o')
}
$summary | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Artifacts 'discovery-summary.json') -Encoding UTF8
W ("Done. OK={0} FAIL={1}" -f $dlOk,$dlFail)




