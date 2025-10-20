[CmdletBinding()]
param(
  [string]$Manifest = "C:\GFL-System\config\GFL-Manifest.json",
  [switch]$Parallel,
  [switch]$PushRclone,
  [switch]$PushFTP,
  [switch]$DryRun,
  [int]$Retry = 3,
  [int]$TimeoutSec = 180
)

$ErrorActionPreference = "Stop"

function Say([string]$Text,[string]$Color="Gray"){ Write-Host $Text -ForegroundColor $Color }
function Ensure-Dir([string]$p){ if(-not (Test-Path $p)){ New-Item -ItemType Directory -Path $p | Out-Null } }
function Get-Command([string]$n){ (Get-Command $n -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
function Try-Run([scriptblock]$Do,[string]$Step){
  try{ & $Do; Say "[OK] $Step" "Green" }
  catch { Say ("[FAIL] {0}: {1}" -f $Step, $_.Exception.Message) "Red"; throw }
}

# Roots
$Root   = "C:\GFL-System"
$Scripts= Join-Path $Root "Scripts"
$Logs   = Join-Path $Root "logs"
$Stage  = Join-Path $Root "staging"
$Tools  = Join-Path $Root "tools"
$Cfg    = Join-Path $Root "config"
$Tmp    = Join-Path $Root "tmp"
foreach($d in @($Root,$Scripts,$Logs,$Stage,$Tools,$Cfg,$Tmp)){ Ensure-Dir $d }

$RunLog = Join-Path $Logs ("transfers_upgrades_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
"== START $(Get-Date) ==" | Out-File $RunLog -Encoding UTF8

if(-not (Test-Path $Manifest)){ throw "Manifest not found: $Manifest" }
$M = Get-Content -Raw -LiteralPath $Manifest | ConvertFrom-Json

function Winget-InstallOrUpgrade([string]$Id){
  $wg = Get-Command "winget"
  if($null -eq $wg){ Say "[WARN] winget not found" Yellow; return }
  if($DryRun){ Say "[DRY] winget upgrade/install $Id" Yellow; return }
  & $wg source update | Out-Null
  $up = & $wg upgrade -e --id $Id --accept-source-agreements --accept-package-agreements
  if(($LASTEXITCODE -ne 0) -or ($up -match "No applicable update found")){
    & $wg install -e --id $Id --accept-source-agreements --accept-package-agreements --silent | Out-Null
  }
}

function Choco-InstallOrUpgrade([string]$Pkg){
  $ch = Get-Command "choco"
  if($null -eq $ch){ Say "[INFO] choco not found; skipping $Pkg" DarkYellow; return }
  if($DryRun){ Say "[DRY] choco upgrade $Pkg -y" Yellow; return }
  & $ch upgrade $Pkg -y --no-progress | Out-Null
}

function Invoke-Download {
  param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$OutFile,
    [int]$Retry = 3,
    [int]$TimeoutSec = 180
  )
  if(Test-Path $OutFile){ Remove-Item $OutFile -Force }
  for($i=1;$i -le $Retry;$i++){
    try{
      $wc = New-Object System.Net.WebClient
      $wc.DownloadFile($Url, $OutFile)
      if(-not (Test-Path $OutFile)){ throw "No file after download." }
      return
    }catch{
      if($i -eq $Retry){ throw "Download failed after $Retry attempts: $Url :: $($_.Exception.Message)" }
      Start-Sleep -Seconds ([Math]::Min(15,$i*5))
    }
  }
}

function Test-HashMatch([string]$File,[string]$Expect){
  if([string]::IsNullOrWhiteSpace($Expect)){ return $true }
  $h = (Get-FileHash -Algorithm SHA256 -Path $File).Hash.ToLowerInvariant()
  return ($h -eq $Expect.ToLowerInvariant())
}

function Extract-IfArchive([string]$File,[string]$Dest){
  Ensure-Dir $Dest
  $ext = [IO.Path]::GetExtension($File).ToLowerInvariant()
  if($ext -in @(".zip",".7z",".rar",".tar",".gz")){
    if($DryRun){ Say "[DRY] Extract $File -> $Dest" Yellow; return }
    if($ext -eq ".zip"){
      Expand-Archive -Path $File -DestinationPath $Dest -Force
    } else {
      $z = Get-Command "7z"
      if(-not $z){ throw "7-Zip CLI not available. Install 7zip.7zip via winget first." }
      & $z x -y -o"`"$Dest`"" "`"$File`"" | Out-Null
    }
  }
}

# 1) Upgrades
Try-Run {
  $wg = Get-Command "winget"
  if($wg -and -not $DryRun){ & $wg source update | Out-Null }
  if($M.packagesWinget){
    if($Parallel){
      $jobs = @()
      foreach($id in $M.packagesWinget){ $jobs += Start-Job -ScriptBlock ${function:Winget-InstallOrUpgrade} -ArgumentList $id }
            # wait for all jobs, then receive & clean (PS5/PS7-safe)
      Wait-Job -Job $jobs | Out-Null
      Receive-Job -Job $jobs | Out-Null
      Remove-Job -Job $jobs -Force -ErrorAction SilentlyContinue
    } else {
      $M.packagesWinget | ForEach-Object { Winget-InstallOrUpgrade $_ }
    }
  }
  if($M.packagesChoco){ $M.packagesChoco | ForEach-Object { Choco-InstallOrUpgrade $_ } }
} "Packages upgraded/ensured"

# 2) Downloads
if($M.downloads){
  foreach($d in $M.downloads){
    $destFolder = switch(($d.dest+'').ToLower()){
      "tools"   { $Tools }
      "staging" { $Stage }
      default   { if([string]::IsNullOrWhiteSpace($d.dest)){ $Stage } else { Join-Path $Root $d.dest } }
    }
    Ensure-Dir $destFolder
    $fileName = if($d.fileName){ $d.fileName } else { [IO.Path]::GetFileName([Uri]$d.url) }
    $outFile  = Join-Path $destFolder $fileName
    if($DryRun){ Say "[DRY] get $($d.url) -> $outFile" Yellow }
    else{ Invoke-Download -Url $d.url -OutFile $outFile -Retry $Retry -TimeoutSec $TimeoutSec }

    if(-not $DryRun){
      if(-not (Test-HashMatch -File $outFile -Expect ($d.sha256+''))){ throw "SHA256 mismatch for $($d.name) ($outFile)." }
      if($d.extract){ Extract-IfArchive -File $outFile -Dest $destFolder }
    }
    "DOWNLOADED: $($d.name) -> $outFile" | Add-Content $RunLog
  }
  Say "[OK] Downloads complete" Green
} else { Say "[INFO] No downloads in manifest" DarkGray }

# 3) Scripts from manifest
if($M.scripts){
  foreach($s in $M.scripts){
    $p = $s.path; $dir = Split-Path $p -Parent
    if($dir){ Ensure-Dir $dir }
    if($DryRun){ Say "[DRY] write $p" Yellow } else { $s.content | Out-File -LiteralPath $p -Encoding UTF8 }
  }
  Say "[OK] Scripts written from manifest" Green
}

# 4) Optional rclone push
if($PushRclone -and $M.rclone -and $M.rclone.remote){
  $rclone = Get-Command "rclone"
  if($rclone){
    foreach($p in $M.rclone.uploadPaths){
      if(Test-Path $p){
        if($DryRun){ Say "[DRY] rclone copy $p -> $($M.rclone.remote)" Yellow }
        else{ & $rclone copy "$p" "$($M.rclone.remote)" --create-empty-src-dirs --fast-list | Out-Null }
      }
    }
    Say "[OK] rclone push complete" Green
  } else { Say "[WARN] rclone not found; skipping push" Yellow }
}

# 5) Optional FTP push
if($PushFTP -and $M.ftp){
  try{ Add-Type -AssemblyName System.Net.Http | Out-Null }catch{}
  foreach($map in $M.ftp.paths){
    $local = $map.local; $remote = $map.remote.Trim("/")
    if(-not (Test-Path $local)){ continue }
    Get-ChildItem -Recurse -File $local | ForEach-Object {
      $rel = $_.FullName.Substring($local.Length).TrimStart('\','/')
      $u = "ftp://$($M.ftp.host):$($M.ftp.port)/$remote/$rel" -replace '\\','/'
      if($DryRun){ Say "[DRY] FTP PUT $($_.FullName) -> $u" Yellow }
      else{
        $req = [System.Net.FtpWebRequest]::Create($u)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
        $req.Credentials = New-Object System.Net.NetworkCredential($M.ftp.user,$M.ftp.pass)
        $bytes = [IO.File]::ReadAllBytes($_.FullName)
        $req.ContentLength = $bytes.Length
        $stream = $req.GetRequestStream()
        $stream.Write($bytes,0,$bytes.Length); $stream.Close()
        $resp = $req.GetResponse(); $resp.Close()
      }
    }
  }
  Say "[OK] FTP push complete" Green
}

"== END $(Get-Date) ==" | Add-Content $RunLog
Say "Transfers + Upgrades: COMPLETE. Log: $RunLog" "Green"




















