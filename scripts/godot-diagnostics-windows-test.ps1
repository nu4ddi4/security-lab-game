param([string]$Godot = 'godot', [string]$Project = 'godot')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = [IO.Path]::GetFullPath($Project, $repoRoot)
$Godot = & (Join-Path $PSScriptRoot 'godot-console.ps1') -Godot $Godot
$fixtureRoot = Join-Path $repoRoot ('godot/builds/diagnostics-test-' + [guid]::NewGuid().ToString())
$denied = Join-Path $fixtureRoot 'denied'
$private = Join-Path $fixtureRoot 'private'
$link = Join-Path $fixtureRoot 'linked'
$sid = '*' + [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$aclChanged = $false
try {
    New-Item -ItemType Directory -Path $denied, $private -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $private 'private.json'), '{"secret":"must-not-collect"}')
    New-Item -ItemType Junction -Path $link -Target $private | Out-Null
    # Deny writes only to this newly owned test folder; no system ACL is changed.
    & icacls $denied /deny ($sid + ':(W)') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot set test-only denied destination' }
    $aclChanged = $true
    $log = & $Godot --headless --path $projectRoot --script res://tests/diagnostics_test.gd -- "--diagnostics-denied=$denied" "--diagnostics-link=$link" 2>&1
    $log | Write-Output
    if ($LASTEXITCODE -ne 0 -or ($log | Select-String 'SCRIPT ERROR:|ERROR:')) { throw 'Windows diagnostic boundary tests failed' }
    $result = $log | Where-Object { $_ -like 'NATIVE_DIAGNOSTICS *' } | Select-Object -Last 1
    if (-not $result -or -not (($result.ToString().Substring(19) | ConvertFrom-Json).passed)) { throw 'Native diagnostics result missing or failed' }
} finally {
    if ($aclChanged) { & icacls $denied /remove:d $sid | Out-Null }
    # Unlink explicitly before deleting the verified, task-created workspace tree.
    if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }
    $resolved = [IO.Path]::GetFullPath($fixtureRoot)
    $allowed = [IO.Path]::GetFullPath((Join-Path $repoRoot 'godot/builds')) + [IO.Path]::DirectorySeparatorChar
    if ($resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
