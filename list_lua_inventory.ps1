param(
  [string]$Root = (Get-Location).Path,
  [string]$OutFile = "lua_inventory_report.txt"
)

$ErrorActionPreference = 'Stop'

$rootPath = (Resolve-Path -Path $Root).Path.TrimEnd('\','/')
$rootPrefix = $rootPath + [IO.Path]::DirectorySeparatorChar
$files = Get-ChildItem -Path $rootPath -Recurse -Filter *.lua | Sort-Object FullName

$lines = New-Object System.Collections.Generic.List[string]
foreach ($f in $files) {
  $full = $f.FullName
  if ($full.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    $rel = $full.Substring($rootPrefix.Length)
  } else {
    $rel = $full
  }
  $lines.Add("FILE: $rel")
  $content = Get-Content -Path $f.FullName

  $requires = $content | Select-String -Pattern 'require\s*''([^'']+)''|require\s*"([^"]+)"'
  if ($requires) {
    $lines.Add('REQUIRES:')
    foreach ($r in $requires) { $lines.Add('  ' + $r.Matches.Value) }
  } else {
    $lines.Add('REQUIRES: (none)')
  }

  $funcs = $content | Select-String -Pattern '^\s*function\s+([\w\.:]+)'
  if ($funcs) {
    $lines.Add('FUNCTIONS:')
    foreach ($fn in $funcs) { $lines.Add('  ' + $fn.Matches.Groups[1].Value) }
  } else {
    $lines.Add('FUNCTIONS: (none)')
  }

  $lines.Add('')
}

$lines | Out-File -FilePath $OutFile -Encoding UTF8
$lines
