<# GFL-Updater.ps1
   If enabled, pulls latest from git or downloads ZIP and applies into C:\GFL-System\Updates\yyyymmdd\
#>
$Root = "C:\GFL-System"
$Cfg  = Get-Content (Join-Path $Root "Configs\update.json") -Raw | ConvertFrom-Json
if(-not $Cfg.enabled){ return }

$UpDir = Join-Path $Root "Updates"
New-Item -ItemType Directory -Force -Path $UpDir | Out-Null
$today = Get-Date -Format "yyyyMMdd"
$dest  = Join-Path $UpDir $today
New-Item -ItemType Directory -Force -Path $dest | Out-Null

try{
  if($Cfg.gitRepo){
    if(-not (Get-Command git -ErrorAction SilentlyContinue)){ winget install Git.Git -e --silent | Out-Null }
    $repoDir = Join-Path $UpDir "repo"
    if(-not (Test-Path $repoDir)){ git clone $Cfg.gitRepo $repoDir | Out-Null }
    Push-Location $repoDir
    git fetch --all | Out-Null
    git checkout $Cfg.gitBranch | Out-Null
    git pull | Out-Null
    Pop-Location
    Copy-Item (Join-Path $repoDir "*") $dest -Recurse -Force
  } elseif($Cfg.zipUrl){
    $zip = Join-Path $UpDir ("pkg-"+[guid]::NewGuid().ToString("N")+".zip")
    Invoke-WebRequest -Uri $Cfg.zipUrl -OutFile $zip
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip,$dest)
    Remove-Item $zip -Force
  }
} catch {}
