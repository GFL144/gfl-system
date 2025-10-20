[CmdletBinding()]
param(
  [string]$Root='C:\GFL-System',
  [switch]$UploadArtifacts
)
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$Reports = Join-Path $Root 'Reports'
$Logs    = Join-Path $Reports 'logs'
$Art     = Join-Path $Reports 'artifacts'
$Log     = Join-Path $Logs 'safety-scan.log'
New-Item -ItemType Directory -Force -Path $Reports,$Logs,$Art | Out-Null

function W { param([string]$m,[string]$lvl='INFO')
  $line=('[{0}] {1}: {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$lvl,$m)
  $line | Tee-Object -FilePath $Log -Append | Out-Null
}
function Get-Cmd { param([string]$n) Get-Command $n -ErrorAction SilentlyContinue }

# Defender targets (explicit strings)
$Quarantine = [IO.Path]::Combine($Root,'Quarantine')
$Fetched    = [IO.Path]::Combine($Root,'Staging','Discovery','Fetched')
$targets    = @($Quarantine,$Fetched)

# 1) Defender quick scans
$mp = Join-Path $Env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
foreach($t in $targets){
  if ((Test-Path -LiteralPath $mp -PathType Leaf) -and (Test-Path -LiteralPath $t)) {
    W ("Defender scan: {0}" -f $t)
    Start-Process -FilePath $mp -ArgumentList @('-Scan','-ScanType','3','-File',$t) -Wait | Out-Null
  }
}

# 2) PSScriptAnalyzer (optional)
$issues=@()
if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
  try {
    Import-Module PSScriptAnalyzer -ErrorAction Stop
    $scriptsRoot = Join-Path $Root 'Scripts'
    $scripts = Get-ChildItem -LiteralPath $scriptsRoot -Recurse -Include *.ps1,*.psm1 -ErrorAction SilentlyContinue
    foreach($s in $scripts){
      $res = Invoke-ScriptAnalyzer -Path $s.FullName -Recurse -ErrorAction SilentlyContinue
      if($res){ $issues += $res }
    }
    $issues | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Art 'pssa-issues.json') -Encoding UTF8
    W ("ScriptAnalyzer: files={0} issues={1}" -f $scripts.Count, $issues.Count)
  } catch {
    W ("PSScriptAnalyzer error: {0}" -f $_.Exception.Message) 'WARN'
  }
} else {
  W 'PSScriptAnalyzer not installed; skipping.' 'WARN'
}

# Copy log to artifacts
Copy-Item -Force -LiteralPath $Log -Destination (Join-Path $Art 'safety-scan.log') -ErrorAction SilentlyContinue

# Optional upload via rclone
if ( $UploadArtifacts -and (Get-Cmd 'rclone') ) {
  W 'Uploading safety artifacts via rclone...'
  $p = Start-Process rclone -ArgumentList @('copy',$Art,'gfl-remote:reports','--progress') -Wait -PassThru
  if ($p.ExitCode -ne 0) { W 'rclone upload failed (non-zero exit)' 'WARN' }
}
W 'Safety scan complete.'
