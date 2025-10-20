<# GFL-Metrics.ps1 - collects CPU/GPU/MEM/DISK/NET + optional speedtest
   Writes rolling history to Reports\metrics.jsonl and current snapshot to Reports\metrics.json
#>
param([string]$ConfigPath = "C:\GFL-System\Configs\dashboard-config.json")

$ErrorActionPreference = "Stop"
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$Root    = "C:\GFL-System"
$Reports = Join-Path $Root "Reports"
$Logs    = Join-Path $Reports "logs"
$Hist    = Join-Path $Reports "metrics.jsonl"
$Snap    = Join-Path $Reports "metrics.json"
New-Item -ItemType Directory -Force -Path $Reports,$Logs | Out-Null

function Get-CPU {
  try {
    $c = (Get-Counter "\Processor(_Total)\% Processor Time").CounterSamples.CookedValue
    [math]::Round($c,2)
  } catch { 0 }
}

function Get-RAM {
  try {
    $os = Get-CimInstance Win32_OperatingSystem
    $total = [math]::Round($os.TotalVisibleMemorySize/1MB,2)
    $free  = [math]::Round($os.FreePhysicalMemory/1MB,2)
    $used  = [math]::Round($total-$free,2)
    @{ totalGB=$total; usedGB=$used; freeGB=$free; usedPct=[math]::Round(($used/$total)*100,2) }
  } catch { @{ totalGB=0; usedGB=0; freeGB=0; usedPct=0 } }
}

function Get-Disk {
  try {
    Get-PSDrive -PSProvider FileSystem | ForEach-Object {
      $vol = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($_.Root.Replace('\',''))'"
      if($vol){ [pscustomobject]@{
        name = $_.Name
        totalGB = [math]::Round($vol.Size/1GB,2)
        freeGB  = [math]::Round($vol.FreeSpace/1GB,2)
        usedGB  = [math]::Round(($vol.Size-$vol.FreeSpace)/1GB,2)
        usedPct = if($vol.Size){ [math]::Round((($vol.Size-$vol.FreeSpace)/$vol.Size)*100,2)} else {0}
      } }
    }
  } catch { @() }
}

function Get-NIC {
  try {
    Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | ForEach-Object {
      $s = Get-NetAdapterStatistics -Name $_.Name
      [pscustomobject]@{
        name     = $_.Name
        rxMBps   = [math]::Round(($s.ReceivedBytes/1MB),3)
        txMBps   = [math]::Round(($s.SentBytes/1MB),3)
        speedGb  = [math]::Round($_.LinkSpeed/1Gb,2)
      }
    }
  } catch { @() }
}

function Get-GPU {
  # Try Windows "GPU Engine" counters; fallback to vendor CLIs; last resort: basic info only
  $gpus = @()
  try {
    $samples = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop
    $byInst = @{}
    foreach($s in $samples.CounterSamples){
      $inst = $s.InstanceName
      if(-not $inst){ continue }
      # aggregate per physical adapter (strip engine)
      $key = ($inst -split "_")[0]
      if(-not $byInst.ContainsKey($key)){ $byInst[$key] = @() }
      $byInst[$key] += $s.CookedValue
    }
    foreach($k in $byInst.Keys){
      $util = [math]::Round(($byInst[$k] | Measure-Object -Average).Average,2)
      $gpus += [pscustomobject]@{ name=$k; utilPct=$util; vramGB=$null; vramUsedGB=$null; vendor=$null }
    }
  } catch {
    # Try NVIDIA
    try {
      if(Get-Command nvidia-smi -ErrorAction SilentlyContinue){
        $csv = nvidia-smi --query-gpu=name,utilization.gpu,memory.total,memory.used --format=csv,noheader
        foreach($line in $csv){
          $parts = $line -split ","
          $gpus += [pscustomobject]@{
            name=$parts[0].Trim(); utilPct=[double]($parts[1] -replace "[^0-9.]","")
            vramGB=[math]::Round(([double]($parts[2] -replace "[^0-9.]",""))/1024,2)
            vramUsedGB=[math]::Round(([double]($parts[3] -replace "[^0-9.]",""))/1024,2)
            vendor="NVIDIA"
          }
        }
      }
    } catch {}
  }
  if(-not $gpus){
    # Minimal fallback
    try {
      Get-CimInstance Win32_VideoController | ForEach-Object {
        [pscustomobject]@{
          name=$_.Name; utilPct=$null; vramGB=[math]::Round($_.AdapterRAM/1GB,2)
          vramUsedGB=$null; vendor=$_.AdapterCompatibility
        }
      }
    } catch { @() }
  }
  $gpus
}

function Maybe-Speed {
  if(-not $cfg.speedtest){ return $null }
  try {
    if(-not (Get-Command speedtest -ErrorAction SilentlyContinue)){ return $null }
    $r = speedtest -f json | ConvertFrom-Json
    [pscustomobject]@{
      pingMs = [math]::Round($r.ping.latency,2)
      downMbps = [math]::Round($r.download.bandwidth*8/1MB,2)
      upMbps   = [math]::Round($r.upload.bandwidth*8/1MB,2)
      server   = $r.server.host
    }
  } catch { $null }
}

# prune history older than cfg.keepDays
function Prune-History {
  if(Test-Path $Hist){
    $cut = (Get-Date).AddDays(-1*$cfg.keepDays)
    $tmp = [System.IO.Path]::GetTempFileName()
    Get-Content $Hist | ForEach-Object {
      try{ $o = $_ | ConvertFrom-Json; if([datetime]$o.ts -ge $cut){ $_ | Out-File $tmp -Append -Encoding utf8 } }
      catch {}
    }
    Move-Item $tmp $Hist -Force
  }
}

while($true){
  $cpu = Get-CPU
  $ram = Get-RAM
  $dsk = Get-Disk
  $nic = Get-NIC
  $gpu = Get-GPU
  $spd = Maybe-Speed
  $upt = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
  $uptSec = [int]((Get-Date) - $upt).TotalSeconds

  $obj = [ordered]@{
    ts = (Get-Date).ToString("o")
    uptimeSec = $uptSec
    cpuPct = $cpu
    ram = $ram
    disks = $dsk
    nics  = $nic
    gpus  = $gpu
    speed = $spd
  }

  $json = $obj | ConvertTo-Json -Depth 8
  $json | Out-File $Snap -Encoding utf8
  $json | Out-File $Hist -Append -Encoding utf8

  Prune-History
  Start-Sleep -Seconds $cfg.loopSec
}








