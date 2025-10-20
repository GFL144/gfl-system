<# GFL-AutoHeal.ps1
   1) Runs PSScriptAnalyzer on C:\GFL-System\Scripts
   2) Collects Windows Error events related to PowerShell
   3) Builds a FixQueue (manifest), attempts safe auto-fixes (common patterns),
      logs results to Reports\autoheal-*.log and publishes summary to metrics.json
#>
$ErrorActionPreference = "Continue"
$Root    = "C:\GFL-System"
$Scripts = Join-Path $Root "Scripts"
$Reports = Join-Path $Root "Reports"
$Logs    = Join-Path $Reports "logs"
New-Item -ItemType Directory -Force -Path $Logs | Out-Null

# Ensure PSScriptAnalyzer
if(-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)){
  try { Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -ErrorAction Stop } catch {}
}

$stamp = (Get-Date -Format "yyyyMMdd-HHmmss")
$log   = Join-Path $Logs "autoheal-$stamp.log"

function Log($m){ ("[{0}] {1}" -f (Get-Date),$m) | Out-File $log -Append -Encoding utf8; Write-Host $m }

$issues = @()
try {
  if(Get-Module -ListAvailable -Name PSScriptAnalyzer){
    $issues = Invoke-ScriptAnalyzer -Path $Scripts -Recurse -Severity Warning,Error
  }
} catch { Log "Analyzer error: $_" }

$fixCount=0
foreach($i in $issues){
  # Sample safe auto-fixes (common typos/compat)
  try{
    $file = $i.ScriptPath
    if(-not (Test-Path $file)){ continue }
    $text = Get-Content $file -Raw
    $new  = $text

    # Fix common param typo: Get-Command -> Get-Command
    $new = $new -replace '\bGet-Cmd\b','Get-Command'

    # Deprecated backtick line-continuations with trailing spaces
    $new = ($new -split "`r?`n") | ForEach-Object { $_.TrimEnd() } | Out-String

    if($new -ne $text){
      Copy-Item $file "$file.bak" -Force
      $new | Set-Content $file -Encoding utf8
      $fixCount++
      Log "Patched: $file"
    }
  } catch { Log "Patch error in $($i.ScriptPath): $_" }
}

# Capture recent PowerShell related Application errors
try {
  $errEvts = Get-WinEvent -LogName Application -MaxEvents 200 |
    Where-Object { $_.Message -match 'PowerShell' -or $_.Message -match '\.ps1' }
  $errOut  = Join-Path $Logs "errors-$stamp.txt"
  $errEvts | Format-List TimeCreated,ProviderName,Id,LevelDisplayName,Message | Out-File $errOut -Encoding utf8
  Log "Captured recent errors: $errOut"
} catch { Log "Event log read failed: $_" }

# Publish quick status (for dashboard ticker)
$Snap = Join-Path $Reports "metrics.json"
if(Test-Path $Snap){
  try {
    $m = Get-Content $Snap -Raw | ConvertFrom-Json
    $m | Add-Member -NotePropertyName autoHeal -NotePropertyValue ([pscustomobject]@{
      lastRun = (Get-Date).ToString("o"); fixes=$fixCount
    }) -Force
    ($m | ConvertTo-Json -Depth 10) | Out-File $Snap -Encoding utf8
  } catch {}
}
Log "AutoHeal complete. Fixes applied: $fixCount"






