[CmdletBinding()]
param(
  [switch]$Once,
  [int]$EveryMinutes = 5,
  [switch]$NoRestart,
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Paths
$Root    = 'C:\GFL-System'
$Scripts = Join-Path $Root 'Scripts'
$CfgDir  = Join-Path $Root 'Configs'
$Rpt     = Join-Path $Root 'Reports'
$Logs    = Join-Path $Rpt  'logs'
$BkpDir  = Join-Path $Rpt  'backups\autoforge'
New-Item -ItemType Directory -Force -Path $Logs,$BkpDir | Out-Null
$Log     = Join-Path $Logs ('autoforge-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.log')
$CfgPath = Join-Path $CfgDir 'autoforge.json'

function Log([string]$m){ '$((Get-Date).ToString('o')) '+$m | Out-File $Log -Append -Encoding utf8; Write-Host $m }

function Render-Template([string]$tplPath,[hashtable]$tokens){
  if(-not (Test-Path $tplPath)){ throw "Template not found: $tplPath" }
  $s = Get-Content $tplPath -Raw
  foreach($k in $tokens.Keys){
    $v = [regex]::Escape([string]$tokens[$k])
    $s = [regex]::Replace($s,"<#=\s*\True$k\s*#>",$v)
  }
  return $s
}

function Validate-Code([string]$code,[hashtable]$opts){
  # Basic parse check
  try{
    [void][System.Management.Automation.Language.Parser]::ParseInput($code,[ref]$null,[ref]$null)
  }catch{ throw "Parser failed: $_" }
  # Optional ScriptAnalyzer if available
  if($opts -and $opts.pslint){
    if(Get-Module -ListAvailable -Name PSScriptAnalyzer){
      $tmp = [IO.Path]::GetTempFileName()+'.ps1'
      $code | Out-File $tmp -Encoding utf8
      try{
        $issues = Invoke-ScriptAnalyzer -Path $tmp -Severity Warning,Error -ErrorAction SilentlyContinue
        if($issues){ Log ("PSScriptAnalyzer: "+ (@($issues).Count) +" issues (non-fatal)") }
      }catch{ Log "PSScriptAnalyzer error: $_" }
      Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
  }
}

function Safe-Write([string]$dest,[string]$code){
  $dir = Split-Path $dest -Parent
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  # Simple timestamped backup
  if(Test-Path $dest){
    $bk = Join-Path '' ((Split-Path $dest -Leaf) + '.' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak')
    Copy-Item $dest $bk -Force
  }
  $tmp = Join-Path $dir ('.autoforge-'+[guid]::NewGuid().ToString('N')+'.tmp')
  $code | Out-File $tmp -Encoding utf8
  Move-Item $tmp $dest -Force
}

# Load config
if(-not (Test-Path $CfgPath)){ throw "Config missing: $CfgPath" }
$cfg = (Get-Content $CfgPath -Raw) | ConvertFrom-Json
$changed = @()

foreach($t in $cfg.targets){
  try{
    $tpl = [string]$t.template
    $dst = [string]$t.destination
    # Tokens
    $tokens = @{}
    if($t.tokens){ foreach($p in $t.tokens.PSObject.Properties){ $tokens[$p.Name] = [string]$p.Value } }
    # Render or copy-through
    $content = if($tokens.Count -gt 0){ Render-Template $tpl $tokens } else { Get-Content $tpl -Raw }
    Validate-Code $content $t.validate
    $oldHash = ''
    if(Test-Path $dst){ $oldHash = (Get-FileHash $dst -Algorithm SHA256).Hash }
    if(-not $DryRun){
      Safe-Write $dst $content
      $newHash = (Get-FileHash $dst -Algorithm SHA256).Hash
      if($newHash -ne $oldHash){ $changed += $dst; Log "Updated: $dst" } else { Log "No change: $dst" }
      # Manifest line
      $mani = Join-Path $Rpt 'autoforge-manifest.jsonl'
      ($([pscustomobject]@{ ts=(Get-Date).ToString('o'); name=$t.name; dest=$dst; hash=$newHash }) | ConvertTo-Json -Compress) | Out-File $mani -Append -Encoding utf8
    } else { Log "DRYRUN would update: $dst" }
  }catch{ Log "ERROR on target [$($t.name)]: $_" }
}

# Restart tasks if anything changed
if(($changed | Measure-Object).Count -gt 0 -and -not $NoRestart){
  if($cfg.restartTasksOnChange -and $cfg.taskRestarts){
    foreach($n in $cfg.taskRestarts){
      try{
        Stop-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue | Out-Null
        Start-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue | Out-Null
        Log "Restarted task: $n"
      }catch{ Log "Task restart failed: $n  $_" }
    }
  }
}
Log ("Forge pass complete. Changed: " + (($changed | Measure-Object).Count))
