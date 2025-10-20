[CmdletBinding()] param([string]$Root='C:\GFL-System',[int]$MaxRetry=3,[int]$DelayMs=800)
$Reports = Join-Path $Root 'Reports'
$zipName = "reports-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".zip"
$zip = Join-Path $Reports $zipName
if(Test-Path $zip){ Remove-Item $zip -Force -ErrorAction SilentlyContinue }

Add-Type -AssemblyName System.IO.Compression.FileSystem
for($i=1; $i -le $MaxRetry; $i++){
  try {
    [System.IO.Compression.ZipFile]::CreateFromDirectory($Reports,$zip)
    break
  } catch {
    if($i -eq $MaxRetry){ throw }
    Start-Sleep -Milliseconds $DelayMs
  }
}
Write-Host "Zipped reports -> $zip"
if (Get-Command rclone -ErrorAction SilentlyContinue) {
  Start-Process rclone -ArgumentList @('copyto',$zip,'gfl-remote:reports/' + (Split-Path -Leaf $zip),'--progress') -Wait | Out-Null
  Write-Host "Uploaded zip via rclone."
}




