$ErrorActionPreference='Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$Root     = 'C:\GFL-System'
$Reports  = Join-Path $Root 'Reports'
$OutDir   = Join-Path $Reports 'backgrounds'
$DashMain = Join-Path $Root 'Dashboards\Main'
$Gallery  = Join-Path $OutDir 'backgrounds_gallery.html'
$CsvFiles = Join-Path $OutDir 'backgrounds_files.csv'
$CsvSql   = Join-Path $OutDir 'backgrounds_db.csv'
$DeskUrl  = Join-Path $env:USERPROFILE 'Desktop\GFL Backgrounds.url'
$SqliteDb = ''
$SqlSrv   = ''
$SqlDb    = ''

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
function Write-Utf8File($Path,$Text){
  try { Set-Content -Path $Path -Value $Text -Encoding UTF8 -ErrorAction Stop }
  catch { [System.IO.File]::WriteAllText($Path, $Text, ([System.Text.UTF8Encoding]::new($false))) }
}
function Get-Command([string]$name){ (Get-Command $name -EA SilentlyContinue | Select-Object -First 1).Source }
function Short-Bytes([long]$B){
  if($B -ge 1GB){ '{0:N1} GB' -f ($B/1GB) }
  elseif($B -ge 1MB){ '{0:N1} MB' -f ($B/1MB) }
  elseif($B -ge 1KB){ '{0:N1} KB' -f ($B/1KB) }
  else { "$B B" }
}
function Build-Gallery{
  $exts='*.jpg','*.jpeg','*.png','*.bmp','*.gif','*.webp','*.heic'
  $names='background','wallpaper','bg','backdrop'
  $roots=@("$env:USERPROFILE\Pictures","$env:USERPROFILE\Desktop","C:\Windows\Web\Wallpaper","C:\Windows\Web\Screen","$env:PUBLIC\Pictures") | ?{ Test-Path $_ }
  $files = foreach($r in $roots){ foreach($e in $exts){ Get-ChildItem -Path $r -Recurse -File -Include $e -EA SilentlyContinue } }
  $files = $files | Sort-Object LastWriteTime -Descending | Select-Object -Unique FullName,Name,Directory,Length,LastWriteTime
  $filter = $files | Where-Object { $n=$_.Name.ToLower(); ($names | ForEach-Object { $n -like "*$_*" }) -contains $true }
  if(-not $filter){ $filter=$files }
  $filter | Select-Object @{n='File';e={$_.FullName}},@{n='Folder';e={$_.Directory}},@{n='Name';e={$_.Name}},@{n='SizeBytes';e={$_.Length}},@{n='Size';e={ Short-Bytes $_.Length }},@{n='Modified';e={$_.LastWriteTime}} |
    Export-Csv -NoTypeInformation -Encoding UTF8 -Path $CsvFiles
  $rows = $filter | ForEach-Object { $p=$_.FullName -replace '\\','/'; "<div class='card'><img loading='lazy' src='file:///$p'/><div class='meta'><div>$($_.Name)</div><div class='small'>$($_.Directory)</div></div></div>" }
  $count = ($filter|Measure-Object).Count
  $css='body{font-family:Segoe UI,Arial,sans-serif;background:#0b0f14;color:#e5e7eb;margin:0} h2{margin:16px} .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px;padding:16px} .card{background:#0e1622;border:1px solid #1f2a3a;border-radius:12px;overflow:hidden} .card img{width:100%;height:140px;object-fit:cover;display:block;background:#111826} .meta{padding:8px;font-size:12px;color:#cbd5e1} .small{color:#94a3b8} footer{padding:12px;color:#94a3b8;font-size:12px}'
  $html = "<!doctype html><meta charset='utf-8'/><title>GFL Backgrounds</title><style>$css</style><h2>Backgrounds found ($count)</h2><div class='grid'>$($rows -join "`n")</div><footer>CSV: $CsvFiles</footer>"
  Write-Utf8File -Path $Gallery -Text $html
  $url = "file:///$($Gallery -replace '\\','/')"
  $lnk = "[InternetShortcut]`r`nURL=$url`r`nIconIndex=0"
  Write-Utf8File -Path $DeskUrl -Text $lnk
}
function TrySQLite{
  if([string]::IsNullOrWhiteSpace($SqliteDb) -or -not (Test-Path $SqliteDb)){ return }
  $sqlite = Get-Command 'sqlite3'
  if(-not $sqlite){
    $wg = Get-Command 'winget'
    if($wg){ try{ & $wg install -e --id SQLite.SQLite --accept-source-agreements --accept-package-agreements | Out-Null }catch{}; $sqlite = Get-Command 'sqlite3' }
  }
  if(-not $sqlite){
    $choco=Get-Command 'choco'
    if($choco){ try{ & $choco install sqlite -y --no-progress | Out-Null }catch{}; $sqlite = Get-Command 'sqlite3' }
  }
  if(-not $sqlite){ return }
  $sql = ".headers on`n.mode csv`n.output $CsvSql`nSELECT id, name, file_path, tags, created_at FROM backgrounds ORDER BY created_at DESC;`n.output stdout"
  $sql | & $sqlite "$SqliteDb" | Out-Null
}
function TrySqlServer{
  if([string]::IsNullOrWhiteSpace($SqlSrv) -or [string]::IsNullOrWhiteSpace($SqlDb)){ return }
  try{
    Import-Module SqlServer -ErrorAction Stop
    $q='SELECT Id, Name, FilePath, Tags, CreatedAt FROM dbo.Backgrounds ORDER BY CreatedAt DESC;'
    Invoke-Sqlcmd -ServerInstance $SqlSrv -Database $SqlDb -Query $q | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $CsvSql
  }catch{}
}
function InjectTile{
  $index = Join-Path $DashMain 'index.html'
  if(-not (Test-Path $index)){ return }
  $c = Get-Content $index -Raw
  if($c -match 'Backgrounds Gallery'){ return }
  $href = 'file:///' + ($Gallery -replace '\\','/')
  $tile = "<div class='card'><h3>Backgrounds Gallery</h3><a href='$href' style='color:#60a5fa'>Open gallery</a></div>"
  if($c -match '</div>\s*</div>\s*<footer'){ $c = $c -replace '</div>\s*</div>\s*<footer', "`n$tile`n</div></div><footer" } else { $c += "`n$tile`n" }
  Write-Utf8File -Path $index -Text $c
}
Build-Gallery
TrySQLite
TrySqlServer
InjectTile














