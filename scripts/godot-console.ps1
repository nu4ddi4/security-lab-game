param([string]$Godot = "godot")
$ErrorActionPreference = "Stop"

# setup-godot's Windows PATH alias points at the GUI executable. Resolve its
# target before looking for the adjacent console wrapper, so stdout and exit
# status are available to every CLI check (including --version).
$command = Get-Command $Godot -CommandType Application -ErrorAction Stop
$file = [System.IO.FileInfo]::new($command.Source)
$target = $file.ResolveLinkTarget($true)
$executable = if ($null -ne $target) { $target.FullName } else { $file.FullName }
if ($IsWindows -and [System.IO.Path]::GetExtension($executable) -eq '.exe' -and $executable -notmatch '_console\.exe$') {
    $console = Join-Path (Split-Path -Parent $executable) ([System.IO.Path]::GetFileNameWithoutExtension($executable) + '_console.exe')
    if (-not (Test-Path -LiteralPath $console -PathType Leaf)) {
        throw "Godot console wrapper not found beside $executable. Supply the *_console.exe from the standard Windows download."
    }
    $executable = $console
}
Write-Output $executable
