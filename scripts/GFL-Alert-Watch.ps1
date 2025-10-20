param(
  [string]$ApiUrl = "http://127.0.0.1:8787/api/status",
  [double]$MinDownMbps = 5,
  [double]$MinUpMbps   = 1,
  [int]$Consecutive = 3,
  [string]$LogPath = "C:\GFL-System\Logs\alerts.log"
)
$ErrorActionPreference='SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null

function Toast([string]$title,[string]$msg){
  try{
    $t = New-Object System.Windows.Forms.NotifyIcon
    $t.Icon = [System.Drawing.SystemIcons]::Information
    $t.BalloonTipTitle = $title
    $t.BalloonTipText  = $msg
    $t.Visible = $true
    $t.ShowBalloonTip(5000)
    Start-Sleep 6
    $t.Dispose()
  }catch{}
}

$bad=0
while($true){
  try{
    $j = Invoke-RestMethod -Uri $ApiUrl -UseBasicParsing -TimeoutSec 5
    $s = $j.nic_samples | Select-Object -First 1
    if($null -ne $s){
      $d = [double]$s.Rx_Mbps; $u=[double]$s.Tx_Mbps
      if(($d -lt $MinDownMbps) -or ($u -lt $MinUpMbps)){ $bad++ } else { $bad=0 }
      if($bad -ge $Consecutive){
        $line = "$(Get-Date -Format o) ALERT: Low speeds D=$d Mbps U=$u Mbps ($Consecutive hits)"
        Add-Content -Path $LogPath -Value $line -Encoding UTF8
        Toast "GFL Network Alert" "Low speeds for $Consecutive checks. D=$([math]::Round($d,2)) / U=$([math]::Round($u,2)) Mbps"
        $bad=0
      }
    }
  }catch{
    $line = "$(Get-Date -Format o) ALERT: API unreachable"
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
    Toast "GFL Network Alert" "Dashboard API unreachable"
  }
  Start-Sleep -Seconds 60
}


