<# GFL-Extension-Loader.ps1
   Reads Configs\extensions.json and executes enabled extensions safely
#>
$cfg = Get-Content "C:\GFL-System\Configs\extensions.json" -Raw | ConvertFrom-Json
foreach($ext in ($cfg.extensions | Where-Object { $_.enabled -and $_.script })){
  try {
    if(Test-Path $ext.script){
      Start-Process pwsh -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$ext.script | Out-Null
    }
  } catch {}
}
