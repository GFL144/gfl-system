. C:\\GFL-System\\Utils\\GFL-Logging.ps1
param([string]$Path='C:\\GFL-System\\Scripts')
$errs=0; $files= Get-ChildItem $Path -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue
foreach($f in $files){ try{ $null=[System.Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$null,[ref]$null) } catch { $errs++; Write-GFLLog "Parse error: $($f.FullName) :: $($_.Exception.Message)" 'ERR' } }
if($errs -eq 0){ Write-GFLLog 'TestHarness OK (no parse errors).' } else { Write-GFLLog "TestHarness found $errs parse errors." 'WARN' }
