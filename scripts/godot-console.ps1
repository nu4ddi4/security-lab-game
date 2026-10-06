param([string]$Godot = "godot")
$ErrorActionPreference = "Stop"

# Resolve ordinary symlinks before looking for an adjacent console wrapper.
# Windows hard-link aliases have no target path: CI supplies the installed
# console wrapper explicitly instead of the setup-godot PATH alias.
$command = Get-Command $Godot -CommandType Application -ErrorAction Stop
$file = [System.IO.FileInfo]::new($command.Source)
$target = $file.ResolveLinkTarget($true)
$executable = if ($null -ne $target) { $target.FullName } else { $file.FullName }
if ($IsWindows -and $executable -notmatch '_console\.exe$') {
    $console = Join-Path (Split-Path -Parent $executable) ([System.IO.Path]::GetFileNameWithoutExtension($executable) + '_console.exe')
    if (-not (Test-Path -LiteralPath $console -PathType Leaf)) {
        throw "Godot console wrapper not found beside $executable. Supply the *_console.exe from the standard Windows download."
    }
    $executable = $console
}
Write-Output $executable
