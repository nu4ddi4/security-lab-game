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
    # Stamp only the commit. A future updater's version/channel metadata survives.
    # Restore source metadata even when export fails; runtime gets the exact HEAD.
    $nativeInfoPath = Join-Path $repoRoot 'godot/resources/build_info.json'
    $nativeInfoOriginal = [System.IO.File]::ReadAllBytes($nativeInfoPath)
    try {
        $nativeBuildInfo = Get-Content -LiteralPath $nativeInfoPath -Raw | ConvertFrom-Json
        $nativeCommit = (& git rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0 -or $nativeCommit -notmatch '^[0-9a-f]{40}$') { throw 'Cannot identify native build commit' }
        $nativeBuildInfo.commit = $nativeCommit
        [System.IO.File]::WriteAllText($nativeInfoPath, ($nativeBuildInfo | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
        $exportLog = & $Godot --headless --path godot --export-release "Windows Native" $target 2>&1
        $nativeExportExit = $LASTEXITCODE
    } finally { [System.IO.File]::WriteAllBytes($nativeInfoPath, $nativeInfoOriginal) }
    $exportLog | Write-Output
    if ($nativeExportExit -ne 0 -or ($exportLog | Select-String 'ERROR:|SCRIPT ERROR:') -or -not (Test-Path -LiteralPath $target)) { throw "Windows native export failed" }
    $binary = Get-Item -LiteralPath $target -ErrorAction Stop
    if ($binary.PSIsContainer -or $binary.Length -le 0) { throw "Native Windows EXE missing or empty" }
    Write-Host "Native EXE: $($binary.Length) bytes"
    Get-FileHash -LiteralPath $target -Algorithm SHA256
} finally { Pop-Location }
