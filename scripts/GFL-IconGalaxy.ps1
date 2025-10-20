<# ===================================================================================================
 GFL-IconGalaxy.ps1  (v1.1)
 Interstellar Icon Orchestrator  Windows PowerShell 5.1 & PowerShell 7 compatible

 Changes from v1.0:
   Removed null-conditional operator (?.) so it works on Windows PowerShell 5.1
   Separated transcript log from our own log to avoid file in use errors
   Snapshot/convert helpers simplified for 5.1 parser
=================================================================================================== #>

[CmdletBinding()]
param(
  [string]$IconDir = "C:\GFL-System\Dashboards\assets\alien",
  [switch]$Apply,
  [switch]$Restore,
  [switch]$DryRun,
  [switch]$RebuildCache,
  [switch]$ConvertPngToIco,     # optional: PNGICO if ImageMagick present
  [int]$ConvertSizes = 256,
  [switch]$VerboseLogs
)

$ErrorActionPreference = 'Stop'

# ---------- Paths & logging ----------
$Root       = 'C:\GFL-System'
$Reports    = Join-Path $Root 'Reports\IconGalaxy'
$Backups    = Join-Path $Reports 'backups'
$Snapshots  = Join-Path $Reports 'snapshots'
$LogsDir    = Join-Path $Reports 'logs'
$Transcript = Join-Path $LogsDir ("transcript-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".log")
$SayLog     = Join-Path $LogsDir ("say-"        + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".log")
$Manifest   = Join-Path $Reports 'last-manifest.json'
$ThemeFile  = Join-Path $IconDir 'theme.json'
$MapFile    = Join-Path $IconDir 'icon-map.json'

New-Item -ItemType Directory -Force -Path $Reports,$Backups,$Snapshots,$LogsDir | Out-Null
# Start transcript to its own file so our Add-Content can use a separate file safely
Start-Transcript -Path $Transcript -Append | Out-Null

function say([string]$m){
  if($VerboseLogs -or $DryRun){ Write-Host $m }
  try { Add-Content -Path $SayLog -Value ("[{0}] {1}" -f (Get-Date).ToString("s"), $m) -Encoding UTF8 } catch {}
}

# ---------- Helpers ----------
function PathJoin([string]$a,[string]$b){ [System.IO.Path]::Combine($a,$b) }
function TestLeaf([string]$p){ Test-Path $p -PathType Leaf -ErrorAction SilentlyContinue }
function TestDir([string]$p){ Test-Path $p -PathType Container -ErrorAction SilentlyContinue }
function Icon([string]$name){ PathJoin $IconDir $name }

# Desktop.ini writer for folder icons
function Set-FolderIcon([string]$folder,[string]$ico){
  if(-not (TestDir $folder)){ return }
  if($DryRun){ say "Would set folder icon: $folder -> $ico"; return }
  $desktopIni = PathJoin $folder 'desktop.ini'
  $content = @(
    "[.ShellClassInfo]"
    "IconResource=$ico,0"
    "IconFile=$ico"
    "IconIndex=0"
  ) -join "`r`n"
  attrib -s -r "$folder" 2>$null
  Set-Content -Path $desktopIni -Value $content -Encoding Unicode
  attrib +s +r "$folder" 2>$null
  attrib +h "$desktopIni" 2>$null
}

# .lnk icon updater
function Update-ShortcutIcons([string]$root,[string]$icoFallback){
  if(-not (TestDir $root)){ return }
  try{ $shell = New-Object -ComObject WScript.Shell }catch{ return }
  Get-ChildItem -Path $root -Filter *.lnk -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    try{
      $lnk = $shell.CreateShortcut($_.FullName)
      $hasIco = ($lnk.IconLocation -like '*.ico,*') -or ($lnk.IconLocation -like '*.ico')
      if(-not $hasIco){
        if($DryRun){ say "Would set .lnk icon: '$($_.FullName)' -> $icoFallback" }
        else { $lnk.IconLocation = "$icoFallback,0"; $lnk.Save() }
      }
    }catch{}
  }
}

# Registry helpers (per-user)
function HKCU_Exists([string]$p){ Test-Path $p -ErrorAction SilentlyContinue }
function HKCU_Set([string]$key,[string]$name,[string]$value){
  if($DryRun){ say "Would set: $key ($name) = $value"; return }
  New-Item -Path $key -Force | Out-Null
  New-ItemProperty -Path $key -Name $name -Value $value -PropertyType ExpandString -Force | Out-Null
}
function HKCU_SetDefault([string]$key,[string]$value){
  if($DryRun){ say "Would set: $key (default) = $value"; return }
  New-Item -Path $key -Force | Out-Null
  Set-ItemProperty -Path $key -Name '(default)' -Value $value -Force
}
function HKCU_Remove([string]$key){
  if($DryRun){ say "Would delete: $key"; return }
  if(HKCU_Exists $key){ Remove-Item $key -Recurse -Force -ErrorAction SilentlyContinue }
}

# File-type association (per-user override)
function Set-UserFileTypeIcon([string]$ext,[string]$ico){
  $ext = $ext.Trim(); if(-not $ext.StartsWith(".")){ $ext = "." + $ext }
  $progId = "GFL$($ext.Replace('.','_'))"
  $kExt  = "HKCU:\Software\Classes\$ext"
  $kProg = "HKCU:\Software\Classes\$progId"
  HKCU_SetDefault $kProg ''
  HKCU_SetDefault "$kProg\DefaultIcon" "$ico,0"
  HKCU_SetDefault $kExt $progId
}
function Restore-UserFileTypeIcon([string]$ext){
  $ext = $ext.Trim(); if(-not $ext.StartsWith(".")){ $ext = "." + $ext }
  $progId = "GFL$($ext.Replace('.','_'))"
  $kExt  = "HKCU:\Software\Classes\$ext"
  $kProg = "HKCU:\Software\Classes\$progId"
  HKCU_Remove $kExt
  HKCU_Remove $kProg
}

# System object per-user icon
function Set-SystemIcon([string]$clsid,[string]$ico){
  $k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID\$clsid\DefaultIcon"
  HKCU_SetDefault $k "$ico,0"
}
function Restore-SystemIcon([string]$clsid){
  $k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID\$clsid"
  HKCU_Remove $k
}

# Recycle Bin (empty/full)
function Set-RecycleIcons([string]$icoEmpty,[string]$icoFull){
  $base = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID\{645FF040-5081-101B-9F08-00AA002F954E}\DefaultIcon"
  HKCU_Set $base 'empty' "$icoEmpty,0"
  HKCU_Set $base 'full'  "$icoFull,0"
}
function Restore-RecycleIcons(){
  HKCU_Remove "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID\{645FF040-5081-101B-9F08-00AA002F954E}"
}

# Icon cache rebuild
function Rebuild-IconCache(){
  if($DryRun){ say "Would rebuild icon cache (ie4uinit + Explorer restart)"; return }
  try{ & ie4uinit.exe -ClearIconCache 2>$null }catch{}
  try{
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
  }catch{}
}

# Registry snapshot (simple)
function Snapshot-Registry {
  $snap = [ordered]@{}
  $roots = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID",
    "HKCU:\Software\Classes"
  )
  foreach($r in $roots){
    try{
      $items = Get-ChildItem $r -Recurse -ErrorAction SilentlyContinue
      $snap[$r] = @($items | Select-Object -ExpandProperty PsPath)
    }catch{}
  }
  $p = PathJoin $Snapshots ("snapshot-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".json")
  ($snap | ConvertTo-Json -Depth 6) | Set-Content -Encoding UTF8 -Path $p
  say "Snapshot  $p"
}

# PNGICO conversion via ImageMagick (optional; 5.1-safe Get-Command usage)
function Maybe-ConvertPngs([string]$dir,[int]$size){
  if(-not $ConvertPngToIco){ return }
  $cmd = Get-Command magick.exe -ErrorAction SilentlyContinue
  $mag = $null
  if($cmd){ $mag = $cmd.Source }  # no ?. in 5.1
  if(-not $mag){ say "ImageMagick not found; skipping PNGICO."; return }
  $pngs = Get-ChildItem $dir -Filter *.png -File -ErrorAction SilentlyContinue
  foreach($p in $pngs){
    $ico = [System.IO.Path]::ChangeExtension($p.FullName, ".ico")
    if(TestLeaf $ico){ continue }
    if($DryRun){ say ("Would convert: {0}  {1}" -f $p.Name, [IO.Path]::GetFileName($ico)); continue }
    & $mag $p.FullName -resize "${size}x${size}" -alpha on -colorspace sRGB $ico 2>&1 | Out-Null
    say ("Converted: {0}  {1}" -f $p.Name, [IO.Path]::GetFileName($ico))
  }
}

# ---------- Icon catalog ----------
function IconPath($n){ Icon $n }
$icons = @{
  folder           = IconPath "folder.ico"
  desktop          = IconPath "desktop.ico"
  docs             = IconPath "docs.ico"
  downloads        = IconPath "downloads.ico"
  music            = IconPath "music.ico"
  pictures         = IconPath "pictures.ico"
  videos           = IconPath "videos.ico"
  recycle_empty    = IconPath "recycle-empty.ico"
  recycle_full     = IconPath "recycle-full.ico"
  pc               = IconPath "pc.ico"
  user             = IconPath "user.ico"
  network          = IconPath "network.ico"
  drive            = IconPath "drive.ico"
  link             = IconPath "link.ico"

  file_txt         = IconPath "file-txt.ico"
  file_pdf         = IconPath "file-pdf.ico"
  file_docx        = IconPath "file-docx.ico"
  file_xlsx        = IconPath "file-xlsx.ico"
  file_pptx        = IconPath "file-pptx.ico"
  file_png         = IconPath "file-png.ico"
  file_jpg         = IconPath "file-jpg.ico"
  file_svg         = IconPath "file-svg.ico"
  file_mp4         = IconPath "file-mp4.ico"
  file_mov         = IconPath "file-mov.ico"
  file_webm        = IconPath "file-webm.ico"
  file_mp3         = IconPath "file-mp3.ico"
  file_wav         = IconPath "file-wav.ico"
  file_zip         = IconPath "file-zip.ico"
  file_7z          = IconPath "file-7z.ico"
  file_ps1         = IconPath "file-ps1.ico"
  file_bat         = IconPath "file-bat.ico"
  file_js          = IconPath "file-js.ico"
  file_ts          = IconPath "file-ts.ico"
  file_json        = IconPath "file-json.ico"
  file_yaml        = IconPath "file-yaml.ico"
  file_xml         = IconPath "file-xml.ico"
  file_html        = IconPath "file-html.ico"
  file_css         = IconPath "file-css.ico"
  file_py          = IconPath "file-py.ico"
  file_go          = IconPath "file-go.ico"
  file_rs          = IconPath "file-rs.ico"
  file_cs          = IconPath "file-cs.ico"
  file_c           = IconPath "file-c.ico"
  file_cpp         = IconPath "file-cpp.ico"
  file_sql         = IconPath "file-sql.ico"
  file_pdf_fill    = IconPath "file-pdf-fill.ico"
}

# Optional per-type override map
$map = $null
if(TestLeaf $MapFile){
  try{ $map = Get-Content $MapFile -Raw | ConvertFrom-Json }catch{ $map=$null }
}

# Known folders
$KnownFolders = @{
  Desktop   = [Environment]::GetFolderPath('Desktop')
  Documents = [Environment]::GetFolderPath('MyDocuments')
  Downloads = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads')
  Music     = [Environment]::GetFolderPath('MyMusic')
  Pictures  = [Environment]::GetFolderPath('MyPictures')
  Videos    = [Environment]::GetFolderPath('MyVideos')
}

# File-type pairs (extendable)
$TypePairs = @(
  @{ ext='.txt';   ico=$icons.file_txt },
  @{ ext='.md';    ico=$icons.file_txt },
  @{ ext='.pdf';   ico= $(if(TestLeaf $icons.file_pdf_fill){$icons.file_pdf_fill}else{$icons.file_pdf}) },
  @{ ext='.doc';   ico=$icons.file_docx },
  @{ ext='.docx';  ico=$icons.file_docx },
  @{ ext='.xls';   ico=$icons.file_xlsx },
  @{ ext='.xlsx';  ico=$icons.file_xlsx },
  @{ ext='.ppt';   ico=$icons.file_pptx },
  @{ ext='.pptx';  ico=$icons.file_pptx },
  @{ ext='.csv';   ico=$icons.file_xlsx },
  @{ ext='.png';   ico=$icons.file_png },
  @{ ext='.jpg';   ico=$icons.file_jpg },
  @{ ext='.jpeg';  ico=$icons.file_jpg },
  @{ ext='.svg';   ico=$icons.file_svg },
  @{ ext='.gif';   ico=$icons.file_png },
  @{ ext='.mp4';   ico=$icons.file_mp4 },
  @{ ext='.mov';   ico=$icons.file_mov },
  @{ ext='.webm';  ico=$icons.file_webm },
  @{ ext='.mp3';   ico=$icons.file_mp3 },
  @{ ext='.wav';   ico=$icons.file_wav },
  @{ ext='.flac';  ico=$icons.file_wav },
  @{ ext='.zip';   ico=$icons.file_zip },
  @{ ext='.7z';    ico=$icons.file_7z },
  @{ ext='.rar';   ico=$icons.file_7z },
  @{ ext='.ps1';   ico=$icons.file_ps1 },
  @{ ext='.bat';   ico=$icons.file_bat },
  @{ ext='.js';    ico=$icons.file_js },
  @{ ext='.ts';    ico=$icons.file_ts },
  @{ ext='.json';  ico=$icons.file_json },
  @{ ext='.yml';   ico=$icons.file_yaml },
  @{ ext='.yaml';  ico=$icons.file_yaml },
  @{ ext='.xml';   ico=$icons.file_xml },
  @{ ext='.html';  ico=$icons.file_html },
  @{ ext='.css';   ico=$icons.file_css },
  @{ ext='.py';    ico=$icons.file_py },
  @{ ext='.go';    ico=$icons.file_go },
  @{ ext='.rs';    ico=$icons.file_rs },
  @{ ext='.cs';    ico=$icons.file_cs },
  @{ ext='.c';     ico=$icons.file_c },
  @{ ext='.cpp';   ico=$icons.file_cpp },
  @{ ext='.sql';   ico=$icons.file_sql }
)
if($map){
  foreach($k in $map.PSObject.Properties.Name){
    $TypePairs += @{ ext="$k"; ico=(PathJoin $IconDir $map[$k]) }
  }
}

# System CLSIDs
$CLSIDs = @{
  ThisPC   = '{20D04FE0-3AEA-1069-A2D8-08002B30309D}'
  User     = '{59031a47-3f72-44a7-89c5-5595fe6b30ee}'
  Network  = '{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}'
  Recycle  = '{645FF040-5081-101B-9F08-00AA002F954E}'
}

# ---------- Pre-flight ----------
if(-not ($Apply -xor $Restore)){
  say "Specify either -Apply or -Restore."
  Stop-Transcript | Out-Null
  return
}
if(-not (TestDir $IconDir)){
  say "IconDir not found: $IconDir"
  Stop-Transcript | Out-Null
  return
}
if($Apply -and $ConvertPngToIco){ Maybe-ConvertPngs -dir $IconDir -size $ConvertSizes }

# ---------- Manifest scaffold ----------
$runManifest = [ordered]@{
  when         = (Get-Date).ToString('o')
  iconDir      = $IconDir
  action       = $(if($Apply){"apply"}else{"restore"})
  dryRun       = [bool]$DryRun
  iconPresence = @{}
  fileTypes    = @()
  folders      = @{}
  shortcuts    = @{}
  registryKeys = @()
  themeFile    = $(if(TestLeaf $ThemeFile){$ThemeFile}else{$null})
  mapFile      = $(if(TestLeaf $MapFile){$MapFile}else{$null})
}
foreach($k in $icons.Keys){ $runManifest.iconPresence[$k] = (TestLeaf $icons[$k]) }

Snapshot-Registry

# ------- APPLY -------
if($Apply){
  say "Applying Interstellar Galactic theme (DryRun=$DryRun)"

  # Known folders
  foreach($kv in $KnownFolders.GetEnumerator()){
    $name = $kv.Key.ToLower()
    $path = $kv.Value
    $iconKey = switch($name){
      'desktop'   {'desktop'}
      'documents' {'docs'}
      'downloads' {'downloads'}
      'music'     {'music'}
      'pictures'  {'pictures'}
      'videos'    {'videos'}
      default     {'folder'}
    }
    $ico = $icons[$iconKey]
    if(TestLeaf $ico){ Set-FolderIcon -folder $path -ico $ico; $runManifest.folders[$name] = @{ path=$path; icon=$ico } }
  }

  # Per-folder theme.json
  if(TestLeaf $ThemeFile){
    try{
      $theme = Get-Content $ThemeFile -Raw | ConvertFrom-Json
      foreach($t in $theme){
        $p = [string]$t.path; $ico = [string](PathJoin $IconDir $t.icon)
        if((TestDir $p) -and (TestLeaf $ico)){ Set-FolderIcon -folder $p -ico $ico; $runManifest.folders[$p] = @{ path=$p; icon=$ico } }
      }
    }catch{ say "theme.json parse error: $($_.Exception.Message)" }
  }

  # System objects
  if(TestLeaf $icons.pc){    Set-SystemIcon -clsid $CLSIDs.ThisPC   -ico $icons.pc;      $runManifest.registryKeys += "CLSID\$($CLSIDs.ThisPC)" }
  if(TestLeaf $icons.user){  Set-SystemIcon -clsid $CLSIDs.User     -ico $icons.user;    $runManifest.registryKeys += "CLSID\$($CLSIDs.User)" }
  if(TestLeaf $icons.network){ Set-SystemIcon -clsid $CLSIDs.Network -ico $icons.network; $runManifest.registryKeys += "CLSID\$($CLSIDs.Network)" }
  if(TestLeaf $icons.recycle_empty -and TestLeaf $icons.recycle_full){
    Set-RecycleIcons -icoEmpty $icons.recycle_empty -icoFull $icons.recycle_full
    $runManifest.registryKeys += "CLSID\$($CLSIDs.Recycle)"
  }

  # File-type overrides
  foreach($p in $TypePairs){
    if($p.ico -and (TestLeaf $p.ico)){
      Set-UserFileTypeIcon -ext $p.ext -ico $p.ico
      $runManifest.fileTypes += @{ ext=$p.ext; icon=$p.ico }
      $runManifest.registryKeys += "Software\Classes\$($p.ext)"
      $runManifest.registryKeys += "Software\Classes\GFL$($p.ext.Replace('.','_'))\DefaultIcon"
    }
  }

  # Shortcuts
  $shortcutIco = $(if(TestLeaf $icons.link){$icons.link}else{ $icons.folder })
  $Desktop = [Environment]::GetFolderPath('Desktop')
  $StartCU = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Microsoft\Windows\Start Menu\Programs'
  $StartAll = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
  Update-ShortcutIcons -root $Desktop -icoFallback $shortcutIco
  Update-ShortcutIcons -root $StartCU -icoFallback $shortcutIco
  Update-ShortcutIcons -root $StartAll -icoFallback $shortcutIco
  $runManifest.shortcuts = @{ desktop=$Desktop; startUser=$StartCU; startAll=$StartAll; icon=$shortcutIco }

  # Minimal backup list of keys touched
  $uniq = $runManifest.registryKeys | Sort-Object -Unique
  $bk = [ordered]@{ when=(Get-Date).ToString('o'); keys=$uniq }
  ($bk | ConvertTo-Json -Depth 6) | Set-Content -Encoding UTF8 -Path (Join-Path $Backups ("backup-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".json"))

  if($RebuildCache){ Rebuild-IconCache }
  say "Apply complete."
}

# ------- RESTORE -------
if($Restore){
  say "Restoring defaults (DryRun=$DryRun)"

  foreach($kv in $KnownFolders.GetEnumerator()){
    $p = $kv.Value
    $ini = PathJoin $p 'desktop.ini'
    if(TestLeaf $ini){
      if($DryRun){ say "Would remove $ini" }
      else{
        attrib -s -r $p 2>$null
        Remove-Item $ini -Force -ErrorAction SilentlyContinue
        attrib +s +r $p 2>$null
      }
    }
  }

  if(TestLeaf $ThemeFile){
    try{
      $theme = Get-Content $ThemeFile -Raw | ConvertFrom-Json
      foreach($t in $theme){
        $p = [string]$t.path
        $ini = PathJoin $p 'desktop.ini'
        if(TestLeaf $ini){
          if($DryRun){ say "Would remove $ini" }
          else{
            attrib -s -r $p 2>$null
            Remove-Item $ini -Force -ErrorAction SilentlyContinue
            attrib +s +r $p 2>$null
          }
        }
      }
    }catch{}
  }

  Restore-SystemIcon $CLSIDs.ThisPC
  Restore-SystemIcon $CLSIDs.User
  Restore-SystemIcon $CLSIDs.Network
  Restore-RecycleIcons

  $exts = ($TypePairs | ForEach-Object { $_.ext })
  if($map){ foreach($k in $map.PSObject.Properties.Name){ $exts += $k } }
  $exts = $exts + @('.csv','.jpeg','.flac','.rar') | Sort-Object -Unique
  foreach($e in $exts){ Restore-UserFileTypeIcon -ext $e }

  if($RebuildCache){ Rebuild-IconCache }
  say "Restore complete."
}

# ---------- Save manifest ----------
($runManifest | ConvertTo-Json -Depth 8) | Set-Content -Encoding UTF8 -Path $Manifest
say ("Manifest  {0}" -f $Manifest)
say ("Transcript  {0}" -f $Transcript)
say ("Log  {0}" -f $SayLog)
Stop-Transcript | Out-Null
