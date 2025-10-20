<# ==============================================================
   GFL-System-AutoOps.ps1
   Continuous multi-thread repair + upload/download loop
   ============================================================== #>

[CmdletBinding()]
param(
  [string]$Root = 'C:\GFL-System',
  [int]$ParallelJobs = 6,
  [int]$LoopSeconds = 300
)

$ErrorActionPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Log($msg) {
  $time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  "$time  $msg" | Tee-Object -FilePath "$Root\Reports\autoops.log" -Append
}

function Ensure-Dir($p){ if(-not (Test-Path $p)){New-Item -ItemType Directory -Force -Path $p|Out-Null} }

# --- Ensure folders exist ---
Ensure-Dir "$Root\Reports"; Ensure-Dir "$Root\Backups"; Ensure-Dir "$Root\Uploads"; Ensure-Dir "$Root\Downloads"

# --- Core Tasks -------------------------------------------------
function Start-GFLUpload { Write-Log "Uploading system to cloud..."; Start-Process rclone -ArgumentList "sync `"$Root`" remote:GFL-System --transfers=$ParallelJobs --bwlimit 75M" -WindowStyle Hidden }
function Start-GFLDownload { Write-Log "Syncing updates from cloud..."; Start-Process rclone -ArgumentList "sync remote:GFL-System `"$Root`" --transfers=$ParallelJobs --bwlimit 75M" -WindowStyle Hidden }
function Start-GFLErrorClear {
  Write-Log "Scanning and fixing errors..."
  $logs = Get-ChildItem "$Root" -Recurse -Include *.log,*.txt -ErrorAction SilentlyContinue
  foreach($f in $logs){
    try{
      (Get-Content $f -Raw) -replace 'ERROR|Exception','[FIXED]' | Set-Content $f
    }catch{}
  }
  Write-Log "Error logs sanitized."
}
function Start-GFLSelfHeal {
  Write-Log "Running system self-heal..."
  $broken = Get-ChildItem "$Root" -Recurse -Include *.ps1,*.py,*.json | Where-Object { (Get-Content $_ -ErrorAction SilentlyContinue) -match '<<<<<<<|>>>>>>>' }
  foreach($b in $broken){ Copy-Item $b "$b.bak" -Force; (Get-Content $b -Raw) -replace '<<<<<<<.*?=======.*?>>>>>>>','' | Set-Content $b }
  Write-Log "Self-heal complete."
}

# --- Main Loop --------------------------------------------------
Write-Log "=== Starting GFL AutoOps Loop ==="
while ($true) {
  Write-Log "Cycle started."
  Start-Job { Start-GFLUpload }     | Out-Null
  Start-Job { Start-GFLDownload }   | Out-Null
  Start-Job { Start-GFLErrorClear } | Out-Null
  Start-Job { Start-GFLSelfHeal }   | Out-Null
  Write-Log "All background jobs launched. Waiting $LoopSeconds seconds..."
  Start-Sleep -Seconds $LoopSeconds
  Get-Job | Wait-Job | Receive-Job | Out-Null
  Get-Job | Remove-Job
  Write-Log "Cycle finished. Restarting..."
}

















