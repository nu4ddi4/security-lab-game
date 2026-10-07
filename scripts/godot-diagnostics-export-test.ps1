param(
    [string]$Executable = 'godot/builds/Windows/SecurityLab.exe',
    [string]$Output = '',
    [switch]$Headless
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$Executable = [IO.Path]::GetFullPath($Executable, $repoRoot)
if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw 'Native EXE missing' }
if (-not $Output) { $Output = Join-Path $repoRoot ('godot/builds/diagnostics-review-' + [guid]::NewGuid().ToString()) }
$Output = [IO.Path]::GetFullPath($Output, $repoRoot)
New-Item -ItemType Directory -Path $Output -Force | Out-Null
$stdout = Join-Path $Output 'stdout.log'
$stderr = Join-Path $Output 'stderr.log'
$arguments = @('--', '--qa-diagnostics', ('"--qa-output=' + $Output + '"'))
if ($Headless) { $arguments = @('--headless') + $arguments }
# GUI-subsystem executables are asynchronous with PowerShell's call operator.
# Explicit process waiting is required even when Godot uses --headless.
$process = Start-Process -FilePath $Executable -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
try {
    if (-not $process.WaitForExit(60000)) { $process.Kill(); throw 'Exported diagnostics timed out' }
    $log = @(Get-Content -LiteralPath $stdout) + @(Get-Content -LiteralPath $stderr)
    $log | Write-Output
    if ($process.ExitCode -ne 0 -or ($log | Select-String 'SCRIPT ERROR:|ERROR:')) { throw 'Exported diagnostics failed' }
    $result = $log | Where-Object { $_ -like 'DIAGNOSTICS_REVIEW *' } | Select-Object -Last 1
    if (-not $result -or -not (($result.Substring(19) | ConvertFrom-Json).passed)) { throw 'Diagnostics result missing or failed' }
} finally { $process.Dispose() }
