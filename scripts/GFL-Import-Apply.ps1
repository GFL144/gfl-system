[CmdletBinding()]
param(
  [string]$Root='C:\GFL-System',
  [string]$Staging='C:\GFL-System\Staging\Discovery',
  [string]$Rules='C:\GFL-System\Manifests\import-rules.json',
  [switch]$RebuildManifest
)

$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$Reports   = Join-Path $Root 'Reports'
$Artifacts = Join-Path $Reports 'artifacts'
$Logs      = Join-Path $Reports 'logs'
$Log       = Join-Path $Reports 'import-apply.log'
New-Item -ItemType Directory -Force -Path $Reports,$Artifacts,$Logs | Out-Null

function W { param([string]$m,[string]$lvl='INFO')
  $line = ('[{0}] {1}: {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$lvl,$m)
  $line | Tee-Object -FilePath $Log -Append
}

if (!(Test-Path $Staging)) { W "Nothing to import: $Staging not found" 'WARN'; exit 0 }
if (!(Test-Path $Rules))   { throw "Rules file not found: $Rules" }

$rulesObj = Get-Content $Rules -Raw | ConvertFrom-Json
$rules = $rulesObj.rules
$quarantineRel = $rulesObj.quarantineDir
$quarantine = Join-Path $Root $quarantineRel
New-Item -ItemType Directory -Force -Path $quarantine | Out-Null

function Match-Rule {
  param([string]$name)
  foreach($r in $rules){
    $patterns = ($r.match -split ';')
    foreach($p in $patterns){
      if ($name -like $p) { return $r }
    }
  }
  return $null
}

$processed=0; $moved=0; $unpacked=0; $quarantined=0; $skipped=0

Get-ChildItem -Path $Staging -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
  $file = $_.FullName
  $name = $_.Name
  $rel  = $file.Substring($Staging.Length).TrimStart('\')
  $rule = Match-Rule $name

  if ($null -eq $rule) { $skipped++; W ("No rule for {0}" -f $rel) 'WARN'; return }

  $targetDir = Join-Path $Root $rule.dest
  New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

  $destPath = Join-Path $targetDir $name

  if ($rule.PSObject.Properties['quarantine'] -and $rule.quarantine -eq $true) {
    $qPath = Join-Path $quarantine $name
    Copy-Item -Force $file $qPath
    $quarantined++; $processed++
    W ("Quarantined: {0} -> {1}" -f $rel, $qPath)
    return
  }

  # De-duplicate by hash
  $srcHash = (Get-FileHash -Path $file -Algorithm SHA256).Hash.ToLowerInvariant()
  if (Test-Path $destPath) {
    $dstHash = (Get-FileHash -Path $destPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($srcHash -eq $dstHash) {
      $skipped++; $processed++
      W ("Skip duplicate: {0}" -f $rel)
      return
    }
  }

  Copy-Item -Force $file $destPath
  $moved++; $processed++
  W ("Imported: {0} -> {1}" -f $rel, ($rule.dest + $name))

  # Optional unzip
  if ($rule.PSObject.Properties['unpackTo']) {
    try {
      $unpackDir = Join-Path $Root $rule.unpackTo
      New-Item -ItemType Directory -Force -Path $unpackDir | Out-Null
      $nameNoExt = [IO.Path]::GetFileNameWithoutExtension($name)
      $outDir = Join-Path $unpackDir $nameNoExt
      New-Item -ItemType Directory -Force -Path $outDir | Out-Null
      Expand-Archive -Force -Path $destPath -DestinationPath $outDir -ErrorAction SilentlyContinue
      $unpacked++
      W ("Unpacked: {0} -> {1}" -f $name, $outDir)
    } catch {
      W ("Unpack failed: {0} => {1}" -f $name, $_.Exception.Message) 'WARN'
    }
  }
}

# Optional: manifest rebuild
if ($RebuildManifest) {
  $mb = Join-Path $Root 'Scripts\GFL-Manifest-Builder.ps1'
  if (Test-Path $mb) {
    W "Rebuilding manifest..."
    pwsh -File $mb | Tee-Object -FilePath (Join-Path $Logs 'manifest-builder.out.log') -Append | Out-Null
  } else {
    W "Manifest builder not found: $mb" 'WARN'
  }
}

# Copy log to artifacts and summarize
Copy-Item -Force $Log (Join-Path $Artifacts 'import-apply.log') -ErrorAction SilentlyContinue
$sum = [ordered]@{ processed=$processed; moved=$moved; unpacked=$unpacked; quarantined=$quarantined; skipped=$skipped; finished=(Get-Date).ToString('o') }
$sum | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Artifacts 'import-apply-summary.json') -Encoding UTF8
W ("Done. moved={0} unpacked={1} quarantined={2} skipped={3}" -f $moved,$unpacked,$quarantined,$skipped)



