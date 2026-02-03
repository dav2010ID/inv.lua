param(
    [string]$Root = "inv"
)

$ErrorActionPreference = "Stop"

$rules = @{
    core           = @("core")
    domain         = @("core","domain")
    craft          = @("core","domain","craft")
    infrastructure = @("core","domain","infrastructure")
    services       = @("core","domain","craft","infrastructure","services")
    runtime        = @("core","domain","craft","infrastructure","services","runtime")
}

function Get-LayerFromPath([string]$path) {
    if ($path -match "inv[\\/](core|domain|craft|infrastructure|services|runtime)[\\/]") {
        return $Matches[1]
    }
    return $null
}

function Get-LayerFromModule([string]$module) {
    if ($module -match "^inv\.(core|domain|craft|infrastructure|services|runtime)\.") {
        return $Matches[1]
    }
    return $null
}

$violations = @()

Get-ChildItem -Path $Root -Recurse -Filter *.lua | ForEach-Object {
    $file = $_.FullName
    $layer = Get-LayerFromPath $file
    if (-not $layer) {
        return
    }
    $allowed = $rules[$layer]
    if (-not $allowed) {
        return
    }

    $content = Get-Content -Path $file -Raw
    $matches = [regex]::Matches($content, "require\s*['""]([^'""]+)['""]")
    foreach ($m in $matches) {
        $module = $m.Groups[1].Value
        $depLayer = Get-LayerFromModule $module
        if (-not $depLayer) {
            continue
        }
        if ($allowed -notcontains $depLayer) {
            $violations += [pscustomobject]@{
                File = $file
                From = $layer
                To   = $depLayer
                Module = $module
            }
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host "Layer dependency violations:" -ForegroundColor Red
    $violations | ForEach-Object {
        Write-Host ("- {0} -> {1} requires {2}" -f $_.From, $_.To, $_.Module)
        Write-Host ("  {0}" -f $_.File)
    }
    exit 1
}

Write-Host "Layer dependency check passed." -ForegroundColor Green
