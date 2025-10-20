param()
$ErrorActionPreference="Stop"
$Root      = "C:\GFL-System"
$LogsDir   = Join-Path $Root "Logs"
$BinDir    = Join-Path $Root "QuantumMiner"
$Exe       = Join-Path $BinDir "quantumminer.exe"
$LogPair   = @{ Text = (Join-Path $LogsDir ("quantumminer_superupdate_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss")));
                Transcript = (Join-Path $LogsDir ("quantumminer_superupdate_{0}.transcript.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))) }
New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null

# Use transcript to separate file to avoid lock with our own Add-Content file
try { Start-Transcript -Path $LogPair.Transcript -Append | Out-Null } catch {}

function Say($m,[string]$c="Gray"){ Write-Host $m -ForegroundColor $c; try{ Add-Content -Path $LogPair.Text -Value $m }catch{} }
function Log($m,[string]$c="Gray"){ Say ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"),$m) $c }

# Ensure folder structure
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
$cfgDir = Join-Path $BinDir "Config"; New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null

# If miner missing, drop a flag and exit gracefully
if(-not (Test-Path $Exe)){
  New-Item -ItemType File -Force -Path (Join-Path $BinDir "needs_install.flag") | Out-Null
  Log "quantumminer.exe not found at $Exe  (created needs_install.flag). Skipping start." Yellow
  Stop-Transcript | Out-Null 2>$null
  exit 0
}

# Stop any running miner
$proc = Get-Process quantumminer* -EA SilentlyContinue
if($proc){ try{ $proc | Stop-Process -Force }catch{} }

# Simple hash pass for binaries
$arch = Get-ChildItem $BinDir -File -Include *.exe,*.dll -EA SilentlyContinue
foreach($a in $arch){
  try{
    $h=(Get-FileHash -Algorithm SHA256 -LiteralPath $a.FullName).Hash
    Log ("HASH OK: {0}  {1}" -f $h,$a.Name) "DarkGray"
  }catch{ Log ("Hash fail: {0}" -f $a.Name) "Yellow" }
}

# Start miner
Log "Starting Quantum Miner..." Cyan
Start-Process -FilePath $Exe -WorkingDirectory $BinDir | Out-Null
Start-Sleep -Seconds 2
$proc = Get-Process quantumminer* -EA SilentlyContinue
if($proc){ Log ("Miner running  PID {0}" -f $proc.Id) Green } else { Log "Miner failed to start." Red }

# Dashboard nudge
$flag = Join-Path $Root "Dashboards\QuantumMiner\update.flag"
New-Item -ItemType File -Force -Path $flag | Out-Null
Log "Flagged dashboard for refresh." Green

Stop-Transcript | Out-Null 2>$null








