param([string]$TaskJson)
$t = $TaskJson | ConvertFrom-Json
$cfg = Get-Content 'C:\GFL-System\Configs\hypermill.json' -Raw | ConvertFrom-Json
$outDir = $cfg.paths.output; if(-not (Test-Path $outDir)){ New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

function Render-Template([string]$tpl,[hashtable]$data){
  $s = Get-Content $tpl -Raw
  foreach($k in $data.Keys){
    $s = $s -replace ("<#= \$"+$k+" #>"), [regex]::Escape($data[$k]) -replace '\\\\','\'
    $s = $s -replace ("<#= "+$k+" #>"), [regex]::Escape($data[$k])
  }
  return $s
}

switch($t.kind){
  'ps-class' {
    $tpl = 'C:\GFL-System\HyperMill\Templates\ps-class.tpl'
    $code = Render-Template $tpl @{ ClassName = $t.args.ClassName; Namespace = $t.args.Namespace }
    $file = Join-Path $outDir ("{0}.ps1" -f $t.args.ClassName)
    $code | Out-File $file -Encoding utf8
    "$file"
  }
  'react' {
    $tpl = 'C:\GFL-System\HyperMill\Templates\react-widget.tpl'
    $code = Render-Template $tpl @{ Name=$t.args.Name; Title=$t.args.Title }
    $file = Join-Path $outDir ("{0}.jsx" -f $t.args.Name)
    $code | Out-File $file -Encoding utf8
    "$file"
  }
  default { "unsupported" }
}
