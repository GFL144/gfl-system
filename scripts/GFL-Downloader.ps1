. C:\\GFL-System\\Utils\\GFL-Logging.ps1
param([Parameter(Mandatory)][string]$Url,[Parameter(Mandatory)][string]$OutFile,[int]$Retries=3)
$ProgressPreference='SilentlyContinue'
for($i=0;$i -lt $Retries;$i++){ try{ Write-GFLLog "DL attempt $($i+1): $Url -> $OutFile"; try{ Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop; break } catch { try{ Start-BitsTransfer -Source $Url -Destination $OutFile -ErrorAction Stop; break } catch { $wc=New-Object System.Net.WebClient; $wc.DownloadFile($Url,$OutFile); break } } } catch { if($i -eq ($Retries-1)){ Write-GFLLog "Download failed: $Url :: $($_.Exception.Message)" 'ERR'; throw }; Start-Sleep -Seconds (2*($i+1)) } }
Write-GFLLog "Downloaded: $OutFile" 'OK'
