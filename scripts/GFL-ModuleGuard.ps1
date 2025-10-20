. C:\\GFL-System\\Utils\\GFL-Logging.ps1
param([string[]]$Modules=@(''BurntToast'',''Pester''))
foreach($m in $Modules){ try{ if(-not (Get-Module -ListAvailable -Name $m)){ Write-GFLLog "Installing module $m"; Install-Module $m -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop } } catch { Write-GFLLog "Module $m install failed: $($_.Exception.Message)" 'WARN' } }
