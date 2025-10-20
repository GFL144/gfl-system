<# ====================== GFL-OneBig-TesterFixer.ps1 (v3) ======================
PS5-safe: TEST (default), optional FIX, optional RUN pipeline
- No PS7 . operator anywhere
- Skips staging & "Zip Files" during discovery (prevents re-ingesting)
============================================================================ #>

[CmdletBinding()]
param(
  [int]$Hours = 72,
  [switch]$AutoFix,
  [switch]$RunPipeline,
  [switch]$UseSevenZip,
  [int]$SplitMB = 500,
  [switch]$PruneStage
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------- Paths & logging ----------
$GflRoot   = "C:\GFL-System"
$ScriptDir = Join-Path $GflRoot "Scripts"
$LogsDir   = Join-Path $GflRoot "Logs"
$Reports   = Join-Path $GflRoot "Reports"
$TempDir   = Join-Path $GflRoot "Temp"
$ZipRoot   = Join-Path $env:USERPROFILE "Desktop\Zip Files"

New-Item -ItemType Directory -Force -Path $GflRoot,$ScriptDir,$LogsDir,$Reports,$TempDir,$ZipRoot | Out-Null
$STAMP = Get-Date -Format "yyyyMMdd_HHmmss"
$Log   = Join-Path $LogsDir "onebig_$STAMP.log"

$transcribing = $false
try { Start-Transcript -Path $Log -Append | Out-Null; $transcribing = $true } catch {}

function Write-Ok   ($m){ Write-Host "✓ $m" -ForegroundColor Green }
function Write-Warn ($m){ Write-Host "! $m" -ForegroundColor Yellow }
function Write-Err  ($m){ Write-Host "✗ $m" -ForegroundColor Red }
function Try-Step([string]$Name,[scriptblock]$Block){
  try{ Write-Host ">> $Name" -ForegroundColor Cyan; & $Block; Write-Ok $Name }
  catch{ Write-Err ("$Name :: " + $_.Exception.Message) }
}
function Get-CmdPath([string]$cmd){
  $c = Get-Command $cmd -ErrorAction SilentlyContinue
  if ($c) { $c.Source } else { $null }
}

# ---------- TESTS ----------
$TestRows = New-Object System.Collections.Generic.List[Object]
function Add-TestRow($name,$ok,$note){ $TestRows.Add([pscustomobject]@{Test=$name; Result=($(if($ok){"PASS"}else{"FAIL"})); Note=$note}) }

Add-TestRow "PS version" $true "$($PSVersionTable.PSVersion)"
$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
Add-TestRow "PS7 present in PATH" ([bool]$pwsh) ($(if($pwsh){$pwsh.Source}else{"No"}))

$Profiles = @(
  "$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1",
  "$env:WINDIR\System32\WindowsPowerShell\v1.0\profile.ps1",
  "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1",
  "$env:ProgramFiles\PowerShell\7\profile.ps1"
) | Select-Object -Unique

$BadTokens = @('\?\.', '\?\?')
$BadFoundPaths = @()
foreach($p in $Profiles){
  if(Test-Path $p){
    $t = Get-Content $p -Raw
    $hits=@(); foreach($tok in $BadTokens){ if($t -match $tok){ $hits += $tok } }
    Add-TestRow ("Profile scan: " + [IO.Path]::GetFileName($p)) ($hits.Count -eq 0) ($(if($hits){ "Found: "+($hits -join ', ') } else { "OK" }))
    if($hits.Count -gt 0 -and $p -like "*WindowsPowerShell*"){ $BadFoundPaths += $p }
  }
}

Add-TestRow "7z.exe"     ([bool](Get-Command 7z.exe     -EA SilentlyContinue)) (Get-CmdPath '7z.exe')
Add-TestRow "ffmpeg"     ([bool](Get-Command ffmpeg     -EA SilentlyContinue)) (Get-CmdPath 'ffmpeg')
Add-TestRow "aria2c"     ([bool](Get-Command aria2c     -EA SilentlyContinue)) (Get-CmdPath 'aria2c')
Add-TestRow "winscp.com" ([bool](Get-Command winscp.com -EA SilentlyContinue)) (Get-CmdPath 'winscp.com')
Add-TestRow "adb"        ([bool](Get-Command adb        -EA SilentlyContinue)) (Get-CmdPath 'adb')

foreach($d in @($GflRoot,$ScriptDir,$LogsDir,$Reports,$TempDir,$ZipRoot)){
  Add-TestRow ("Folder: " + [IO.Path]::GetFileName($d)) (Test-Path $d) (Resolve-Path $d -EA SilentlyContinue)
}

$TestFile = Join-Path $Reports "onebig_tests_$STAMP.csv"
$TestRows | Tee-Object -FilePath $TestFile | Format-Table -AutoSize
Write-Host "`nTest report → $TestFile" -ForegroundColor Cyan

# ---------- AUTO FIX (optional) ----------
if($AutoFix){
  foreach($prof in $BadFoundPaths){
    Try-Step "Patch PS5 profile ($([IO.Path]::GetFileName($prof)))" {
      $txt = Get-Content $prof -Raw
      $bak = "$prof.bak_$STAMP"; Copy-Item $prof $bak -Force

      $txt = $txt -replace '\(Get-Command\s+7z\.exe\s+-ErrorAction\s+SilentlyContinue\)\?\.\s*Source','$(Get-Command 7z.exe -ErrorAction SilentlyContinue).Source'
      $txt = $txt -replace '\(Get-Command\s+ffmpeg.*?\)\?\.\s*Source','$(Get-Command ffmpeg -ErrorAction SilentlyContinue).Source'
      $txt = $txt -replace '\?\?',''

      Set-Content -Path $prof -Encoding UTF8 -Value $txt
    }
  }

  Try-Step "PATH doctor (system PATH add if missing)" {
    $targets=@(
      "C:\Program Files\7-Zip",
      "C:\Program Files\ffmpeg\bin",
      "C:\Program Files\aria2",
      "$env:LOCALAPPDATA\Android\Sdk\platform-tools",
      "C:\Program Files (x86)\WinSCP"
    )
    $envReg="HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
    $sysPath=(Get-ItemProperty -Path $envReg -Name Path).Path
    $missing=@()
    foreach($t in $targets){ if((Test-Path $t) -and ($sysPath -notlike "*$t*")){ $missing += $t } }
    if($missing.Count -gt 0){
      $newPath = $sysPath.TrimEnd(';') + ';' + ($missing -join ';')
      Set-ItemProperty -Path $envReg -Name Path -Value $newPath
      Write-Host "PATH updated. Restart terminals to take effect." -ForegroundColor Green
    } else { Write-Host "PATH OK (no changes)." -ForegroundColor Green }
  }
}

# ---------- short-circuit if test-only ----------
if(-not $RunPipeline){
  Write-Host "`n(All done. No pipeline run; omit -RunPipeline to stay in test mode.)" -ForegroundColor Yellow
  if($transcribing){ try{ Stop-Transcript | Out-Null } catch {} }
  return
}

# ---------- Helpers for pipeline ----------
function Discover-NewFiles([int]$Hours,[string[]]$Roots,[string[]]$Exts,[string]$OutCsv,[string[]]$ExcludeDirs){
  $since = (Get-Date).AddHours(-1 * $Hours)
  $extSet=@{}; foreach($e in $Exts){ $extSet[$e.ToLowerInvariant()]=$true }
  $ex = @()
  foreach($x in $ExcludeDirs){ if($x){ $ex += ($x.TrimEnd('\').ToLower() + '\') } }

  $found = New-Object System.Collections.Generic.List[Object]
  foreach($root in $Roots){
    if(-not (Test-Path $root)){ continue }
    Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
      $f = $_
      if($f.LastWriteTime -lt $since){ return }
      $fullLower = $f.FullName.ToLower()
      foreach($e in $ex){ if($fullLower.StartsWith($e)){ return } }  # skip excluded dirs
      if($extSet.ContainsKey($f.Extension.ToLowerInvariant())){
        $found.Add([pscustomobject]@{
          FullPath=$f.FullName; SizeBytes=$f.Length; Extension=$f.Extension
          LastWriteTime=$f.LastWriteTime; RootScanned=$root
        })
      }
    }
  }
  if($found.Count -gt 0){
    $found | Sort-Object LastWriteTime -Descending | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $OutCsv
  }
  return $found.Count
}

function Stage-Files([string]$Manifest,[string]$StageDir,[switch]$DoHash){
  $rows = Import-Csv -LiteralPath $Manifest
  $pathCol = @("FullPath","OriginalPath") | Where-Object { $rows[0].PSObject.Properties.Name -contains $_ } | Select-Object -First 1
  $staged = New-Object System.Collections.Generic.List[Object]
  foreach($r in $rows){
    $src = $r.$pathCol
    if(-not $src -or -not (Test-Path -LiteralPath $src)){ continue }
    if($src.ToLower().StartsWith($StageDir.ToLower())){ continue }
    if($src.ToLower().StartsWith($TempDir.ToLower())) { continue }

    $root = [IO.Path]::GetPathRoot($src)
    $driveTag = $root.TrimEnd('\').Replace(':','')
    $rel = $src.Substring($root.Length)
    $dest = Join-Path $StageDir (Join-Path $driveTag $rel)
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
    Copy-Item -LiteralPath $src -Destination $dest -Force
    $hash = ""
    if($DoHash){ try{ $hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $dest).Hash }catch{ $hash="ERROR: $($_.Exception.Message)" } }
    $staged.Add([pscustomobject]@{ OriginalPath=$src; StagedPath=$dest; SizeBytes=(Get-Item $dest).Length; LastWriteTime=(Get-Item $src).LastWriteTime; HashSHA256=$hash })
  }
  $csv = Join-Path $StageDir ("STAGED_{0}.csv" -f (Get-Date -Format yyyyMMdd_HHmmss))
  if($staged.Count -gt 0){ $staged | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csv }
  return @{ Count=$staged.Count; Csv=$csv }
}

function Archive-Staged([string]$StageDir,[string]$OutRoot,[switch]$Use7z,[int]$SplitMB){
  New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
  $Base="NewData_{0}" -f (Get-Date -Format yyyyMMdd_HHmmss)
  $list=@()
  if($Use7z){
    $seven = Get-CmdPath '7z.exe'
    if($seven){
      Push-Location $StageDir
      & $seven a -t7z -mhe=on -ms=on -mx=5 -r "$Base.7z" "*" ("-v{0}m" -f [int]$SplitMB) | Out-Null
      Pop-Location
      Move-Item -Force (Join-Path $StageDir "$Base.7z*") -Destination $OutRoot
      $list += (Get-ChildItem (Join-Path $OutRoot "$Base.7z*") -File | ForEach-Object FullName)
    } else {
      $zip=Join-Path $OutRoot "$Base.zip"
      Compress-Archive -Path (Join-Path $StageDir '*') -DestinationPath $zip -Force
      $list += $zip
    }
  } else {
    $zip=Join-Path $OutRoot "$Base.zip"
    Compress-Archive -Path (Join-Path $StageDir '*') -DestinationPath $zip -Force
    $list += $zip
  }
  foreach($a in $list){
    try{ $h=Get-FileHash -Algorithm SHA256 -LiteralPath $a; "$($h.Hash)  $(Split-Path $a -Leaf)" | Out-File -Encoding ascii -FilePath "$a.sha256.txt" }catch{}
  }
  return $list
}

function Verify-And-Clean([string]$OutRoot,[string]$StageDir,[switch]$Prune){
  $ok=$true
  $arch=Get-ChildItem $OutRoot -File -Include *.zip,*.7z,*.7z.* -ErrorAction SilentlyContinue
  foreach($a in $arch){
    $sum="$($a.FullName).sha256.txt"
    if(Test-Path $sum){
      $exp=(Get-Content $sum -Raw).Split()[0]
      $act=(Get-FileHash -Algorithm SHA256 -LiteralPath $a.FullName).Hash
      if($exp -ne $act){ $ok=$false; Write-Err "SHA mismatch: $($a.Name)" } else { Write-Ok "SHA OK: $($a.Name)" }
    }
  }
  $seven = Get-CmdPath '7z.exe'
  $first7z = Get-ChildItem $OutRoot -File -Filter *.7z.001 -ErrorAction SilentlyContinue | Select-Object -First 1
  if($seven -and $first7z){ try{ & $seven t $first7z.FullName | Out-Null; Write-Ok "7z test passed" } catch { $ok=$false; Write-Err "7z test failed" } }
  if($ok -and $Prune -and (Test-Path $StageDir)){ Remove-Item -Recurse -Force $StageDir; Write-Ok "Staging cleaned" }
  return $ok
}

# ---------- RUN ----------
Try-Step "Discover new files" {
  $manifest = Join-Path $Reports ("NEWFILES_{0}.csv" -f (Get-Date -Format yyyyMMdd_HHmmss))
  $roots = @("$env:USERPROFILE\Desktop","$env:USERPROFILE\Downloads",$GflRoot)
  $exts  = ".csv",".tsv",".json",".ndjson",".parquet",".xml",".yaml",".yml",".txt",".log",".md",".xls",".xlsx",".xlsm",".ods",".ps1",".psm1",".psd1",".bat",".cmd",".sh",".py",".zip",".7z",".rar"
  $exclude = @($TempDir, $ZipRoot)
  $count = Discover-NewFiles -Hours $Hours -Roots $roots -Exts $exts -OutCsv $manifest -ExcludeDirs $exclude
  if($count -eq 0){ Write-Warn "No new/changed files found in the last $Hours hours."; throw "Nothing to process." }
  Write-Host "Manifest → $manifest (items: $count)" -ForegroundColor Cyan
}

$StageFolder = Join-Path $TempDir ("Stage_NewData_{0}" -f (Get-Date -Format yyyyMMdd_HHmmss))
Try-Step "Stage files" {
  New-Item -ItemType Directory -Force -Path $StageFolder | Out-Null
  $manifestLatest = (Get-ChildItem $Reports -Filter "NEWFILES_*.csv" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
  $stageRes = Stage-Files -Manifest $manifestLatest -StageDir $StageFolder -DoHash
  if($stageRes.Count -eq 0){ throw "Nothing staged." }
  Write-Host "Staged manifest → $($stageRes.Csv)" -ForegroundColor Cyan
}

$Archives = @()
Try-Step "Archive staged" {
  $Archives = Archive-Staged -StageDir $StageFolder -OutRoot $ZipRoot -Use7z:$UseSevenZip -SplitMB $SplitMB
  Write-Host "Archives →`n  $($Archives -join "`n  ")" -ForegroundColor Cyan
}

Try-Step "Verify & cleanup" {
  $ok = Verify-And-Clean -OutRoot $ZipRoot -StageDir $StageFolder -Prune:$PruneStage
  if(-not $ok){ throw "Archive verification failed." }
}

Write-Host "`nAll done." -ForegroundColor Green
Write-Host "Log → $Log" -ForegroundColor Cyan
if($transcribing){ try{ Stop-Transcript | Out-Null } catch {} }



























































