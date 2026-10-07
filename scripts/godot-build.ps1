param([string]$Godot = "godot", [string]$Output = "godot/builds/Windows/SecurityLab.exe")
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    $Godot = & (Join-Path $PSScriptRoot 'godot-console.ps1') -Godot $Godot
    Write-Host "Godot CLI: $Godot"
    $version = & $Godot --version
    if ($LASTEXITCODE -ne 0 -or $version -notmatch '^4\.7\.2\.stable') { throw "Use tested Godot 4.7.2 stable: $version" }
    & $Godot --headless --editor --path godot --import
    if ($LASTEXITCODE -ne 0) { throw "Native import failed" }
    python scripts/godot-import-config.py
    & $Godot --headless --editor --path godot --import
    if ($LASTEXITCODE -ne 0) { throw "Texture import failed" }
    & $Godot --headless --path godot --script res://tests/unit.gd
    if ($LASTEXITCODE -ne 0) { throw "Native parity tests failed" }
    node scripts/godot-asset-test.mjs
    if ($LASTEXITCODE -ne 0) { throw "Protected native geometry changed" }
    $target = [System.IO.Path]::GetFullPath($Output, $repoRoot)
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    $exportLog = & $Godot --headless --path godot --export-release "Windows Native" $target 2>&1
    $exportLog | Write-Output
    if ($LASTEXITCODE -ne 0 -or ($exportLog | Select-String 'ERROR:|SCRIPT ERROR:') -or -not (Test-Path -LiteralPath $target)) { throw "Windows native export failed" }
    Get-FileHash -LiteralPath $target -Algorithm SHA256
} finally { Pop-Location }
