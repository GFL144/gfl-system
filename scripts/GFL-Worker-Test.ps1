param([string]$TaskJson)
$t = $TaskJson | ConvertFrom-Json
switch($t.kind){
  'pslint' {
    if(Get-Module -ListAvailable -Name PSScriptAnalyzer){
      $issues = Invoke-ScriptAnalyzer -Path $t.args.path -Recurse -Severity Warning,Error
      $issues | ConvertTo-Json -Depth 6
    } else { 'PSScriptAnalyzer missing' }
  }
  'node-test' {
    if(Get-Command node -ErrorAction SilentlyContinue){
      Push-Location $t.args.path
      try{ npm test --silent | Out-String } finally { Pop-Location }
    } else { 'node missing' }
  }
  default { 'unsupported' }
}
