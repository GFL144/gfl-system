. C\\GFL-System\\Utils\\GFL-Logging.ps1
param([switch]$AutoFix)
$patterns=@(
  @{ Find='The term .* is not recognized'; Fix='module/path or missing file' },
  @{ Find='Could not load file or assembly'; Fix='install dependency' },
  @{ Find='Access to the path .* is denied'; Fix='Admin/ACL' },
  @{ Find='Cannot find path .* because it does not exist'; Fix='create missing folders' }
)
Write-GFLLog 'ErrorDoctor heuristics complete.'


