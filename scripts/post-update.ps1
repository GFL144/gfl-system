param()
Write-Host "Post-update: clearing temp and warming caches..."
Remove-Item -Recurse -Force "C:\GFL-System\Reports\tmp\*" -ErrorAction SilentlyContinue
