. C:\\GFL-System\\Utils\\GFL-Logging.ps1
param([string]$Repo='C:\\GFL-System\\git')
$null= New-Item -ItemType Directory -Path $Repo -Force; Push-Location $Repo
try{ if(-not (Test-Path (Join-Path $Repo '.git'))){ git init | Out-Null }; git config user.email "autobot@gfl.local" | Out-Null; git config user.name "GFL Auto" | Out-Null; git add -A | Out-Null; git commit -m "snapshot: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-Null; Write-GFLLog 'Git snapshot committed' 'OK' } catch { Write-GFLLog "Git snapshot failed: $($_.Exception.Message)" 'WARN' } finally { Pop-Location }
