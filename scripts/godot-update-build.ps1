param(
    [string]$Godot='godot', [string]$Iscc='',
    [ValidateSet('stable','beta','dev')][string]$Channel='dev',
    [string]$Version='0.7.0-dev.0', [string]$Commit='',
    [string]$OutputDirectory=''
)
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
$original=@{}
try {
    if ($Version -cnotmatch '^(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})(?:-(beta|dev)\.(0|[1-9][0-9]{0,8}))?$') { throw 'Version must be SemVer, with beta.N/dev.N for those channels' }
    $core=$Version.Split('-')[0]
    if (($core.Split('.') | Where-Object {[int]$_ -gt 65535}).Count) { throw 'Version exceeds Windows numeric version limit' }
    if (($Channel -eq 'stable' -and $Version.Contains('-')) -or ($Channel -ne 'stable' -and $Version -cnotmatch ('-'+$Channel+'[.][0-9]+$'))) { throw 'Version/channel mismatch' }
    if (-not $Commit) { $Commit=git rev-parse HEAD }
    if ($Commit -cnotmatch '^[0-9a-f]{40}$') { throw 'Commit must be a full SHA' }
    if (-not $Iscc) { $Iscc=Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe' }
    if (-not (Test-Path -LiteralPath $Iscc)) { throw 'Inno Setup 6 compiler is required; pass -Iscc' }
    if (-not $OutputDirectory) { $OutputDirectory=Join-Path $repoRoot ('godot/builds/package/'+$Channel) }
    $OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory,$repoRoot)
    $payload=Join-Path $OutputDirectory 'payload'
    $null=New-Item -ItemType Directory -Path $payload -Force
    $build=[ordered]@{schema=1;app_id='security-lab-native';platform='windows-x86_64';version=$Version;channel=$Channel;commit=$Commit;install_layout=1;updates_default=($Channel -eq 'stable');manifest_url="https://github.com/nu4ddi4/security-lab-game/releases/download/native-channel-$Channel/update.json"}
    foreach ($file in @('godot/resources/build_info.json','godot/project.godot','godot/export_presets.cfg')) { $original[$file]=[IO.File]::ReadAllBytes((Join-Path $repoRoot $file)) }
    [IO.File]::WriteAllText((Join-Path $repoRoot 'godot/project.godot'),([IO.File]::ReadAllText((Join-Path $repoRoot 'godot/project.godot')).Replace('res://scenes/entry.tscn','res://scenes/main.tscn')),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $repoRoot 'godot/resources/build_info.json'),($build | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    foreach ($file in @('godot/project.godot','godot/export_presets.cfg')) {
        $text=[IO.File]::ReadAllText((Join-Path $repoRoot $file))
        if ($file.EndsWith('project.godot')) { $text=$text -replace 'config/version="[^"]+"',('config/version="'+$Version+'"') }
        else { $text=$text -replace 'application/(file|product)_version="[^"]+"',('application/$1_version="'+$core+'.0"') }
        [IO.File]::WriteAllText((Join-Path $repoRoot $file),$text,[Text.UTF8Encoding]::new($false))
    }
    & ./scripts/godot-build.ps1 -Godot $Godot -Output (Join-Path $payload 'SecurityLab.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Native export failed' }
    if (-not (Test-Path -LiteralPath (Join-Path $payload 'SecurityLab.exe'))) { throw 'Native EXE missing' }
    [IO.File]::WriteAllText((Join-Path $payload 'build_info.json'),($build | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $payload 'securitylab.install.json'),(@{app_id=$build.app_id;channel=$Channel;install_layout=1} | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath godot/LICENSES.txt -Destination (Join-Path $payload 'LICENSES.txt')
    & $Iscc ('/DSourceDirectory='+$payload) ('/DOutputDirectory='+$OutputDirectory) ('/DChannel='+$Channel) ('/DAppVersion='+$Version) ('/DBinaryVersion='+$core+'.0') installer/SecurityLab.iss
    if ($LASTEXITCODE -ne 0) { throw 'SecurityLabSetup.exe compilation failed' }
    $installer=Get-Item -LiteralPath (Join-Path $OutputDirectory 'SecurityLabSetup.exe')
    $manifest=[ordered]@{schema=1;app_id=$build.app_id;platform=$build.platform;install_layout=1;channel=$Channel;version=$Version;commit=$Commit;installer_url="https://github.com/nu4ddi4/security-lab-game/releases/download/native-$Channel-v$Version/SecurityLabSetup.exe";size=$installer.Length;sha256=(Get-FileHash -LiteralPath $installer.FullName).Hash.ToLowerInvariant();exe_sha256=(Get-FileHash -LiteralPath (Join-Path $payload 'SecurityLab.exe')).Hash.ToLowerInvariant();published_at=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')}
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'update.json'),($manifest | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath (Join-Path $payload 'build_info.json') -Destination (Join-Path $OutputDirectory 'build_info.json')
    Write-Output ('NATIVE_UPDATE_PACKAGE '+($manifest | ConvertTo-Json -Compress))
} finally {
    foreach ($entry in $original.GetEnumerator()) { [IO.File]::WriteAllBytes((Join-Path $repoRoot $entry.Key),$entry.Value) }
    Pop-Location
}
