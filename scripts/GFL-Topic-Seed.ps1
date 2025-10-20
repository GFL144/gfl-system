[CmdletBinding()]
param(
  [string[]]$Topics = @('powershell remoting','script analyzer rules','bits transfer','rclone windows','defender mpcmdrun'),
  [string]$Out='C:\GFL-System\Manifests\seeds.txt'
)
$mk = {
  param($q)
  $e=[Uri]::EscapeDataString($q)
  @(
    "https://learn.microsoft.com/search/?terms=$e",
    "https://github.com/search?q=$e&type=repositories",
    "https://github.com/search?q=$e&type=code",
    "https://duckduckgo.com/?q=$e"
  )
}
$acc=@()
foreach($t in $Topics){ $acc += & $mk $t }
$acc = $acc | Sort-Object -Unique
Add-Content -Path $Out -Value ($acc -join [Environment]::NewLine)
Write-Host ("Added {0} topic search URL(s) -> {1}" -f $acc.Count,$Out)


