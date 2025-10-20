<# GFL-TaskRunner.ps1
   Watches C:\GFL-System\Queue for *.ps1/*.cmd/*.bat and runs them FIFO, logs results, moves to \done
#>
$Root    = "C:\GFL-System"
$Queue   = Join-Path $Root "Queue"
$Done    = Join-Path $Queue "done"
$Logs    = Join-Path $Root "Reports\logs"
New-Item -ItemType Directory -Force -Path $Queue,$Done,$Logs | Out-Null

function Handle-Task($file){
  $name = [IO.Path]::GetFileName($file)
  $log  = Join-Path $Logs ("task-"+(Get-Date -Format "yyyyMMdd-HHmmss")+"-"+$name+".log")
  try{
    if($file -like "*.ps1"){
      & pwsh -NoProfile -ExecutionPolicy Bypass -File $file *>&1 | Tee-Object -FilePath $log
    } elseif($file -like "*.cmd" -or $file -like "*.bat"){
      & cmd /c $file *>&1 | Tee-Object -FilePath $log
    }
    Move-Item $file (Join-Path $Done $name) -Force
  } catch {
    "ERROR: $_" | Out-File $log -Append -Encoding utf8
    Move-Item $file (Join-Path $Done ("FAILED-"+$name)) -Force
  }
}

# Drain existing first
Get-ChildItem $Queue -File | Sort-Object LastWriteTime | ForEach-Object { Handle-Task $_.FullName }

# Watch for new
$fsw = New-Object IO.FileSystemWatcher $Queue, '*'
$fsw.EnableRaisingEvents = $true
Register-ObjectEvent $fsw Created -Action {
  Start-Sleep -Milliseconds 300
  Handle-Task $Event.SourceEventArgs.FullPath
} | Out-Null

# keep process alive
while($true){ Start-Sleep -Seconds 3600 }








