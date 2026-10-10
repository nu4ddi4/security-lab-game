param([string]$RequestPath, [switch]$Library)
# An exported game can inherit PowerShell 7's module path from its launcher.
# The detached helper deliberately uses Windows PowerShell's system modules.
if ($PSVersionTable.PSEdition -eq 'Desktop') { $env:PSModulePath = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/Modules' }
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-SecurityLabDataRoot {
    Join-Path ([Environment]::GetFolderPath('ApplicationData')) ("Godot/app_userdata/Security Lab $([char]0xb7) Native")
}
function Get-UpdateHash([string]$Path) {
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $hash=[Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($hash.ComputeHash($stream)).Replace('-','') }
    finally { $hash.Dispose(); $stream.Dispose() }
}
function Assert-LocalPath([string]$Value) {
    if ($Value -notmatch '^[A-Za-z]:[\\/]' -or $Value -match '[\x00-\x1f"<>|]' -or $Value.Substring(2).Contains(':')) { throw 'Invalid local path' }
    foreach ($component in $Value.Split([char[]]@('\','/'))) { if ($component.EndsWith('.') -or $component.EndsWith(' ')) { throw 'Ambiguous Windows path component' } }
    $resolved = [IO.Path]::GetFullPath($Value).TrimEnd('\','/')
    $itemPath = $resolved
    while ($itemPath.Length -gt 3) {
        if (Test-Path -LiteralPath $itemPath) {
            $item = Get-Item -LiteralPath $itemPath -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse paths are not allowed' }
        }
        $itemPath = [IO.Path]::GetDirectoryName($itemPath)
    }
    $resolved
}
function Assert-ChildPath([string]$Root, [string]$Child) {
    $resolved = Assert-LocalPath $Child
    if (-not $resolved.StartsWith($Root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Path escaped its owner directory' }
    $resolved
}
function Write-UpdateJson([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path+'.tmp',($Value | ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath ($Path+'.tmp') -Destination $Path -Force
}
function Get-UpdateTree([string]$Root) {
    $queue = [Collections.Generic.Queue[string]]::new(); $queue.Enqueue($Root)
    $files = [Collections.Generic.List[object]]::new(); $count = 0; $bytes = 0L
    while ($queue.Count) {
        foreach ($item in Get-ChildItem -LiteralPath $queue.Dequeue() -Force) {
            $count++; if ($count -gt 4096) { throw 'Install directory has too many entries' }
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Install tree contains a reparse point' }
            $null = Assert-ChildPath $Root $item.FullName
            if ($item.PSIsContainer) { $queue.Enqueue($item.FullName) }
            else {
                $bytes += $item.Length; if ($bytes -gt 5GB) { throw 'Install directory exceeds backup limit' }
                $files.Add([pscustomobject]@{path=$item.FullName.Substring($Root.Length+1);sha256=(Get-UpdateHash $item.FullName);bytes=$item.Length})
            }
        }
    }
    $files.ToArray()
}
function Copy-UpdateTree([string]$Source, [string]$Destination, $Inventory) {
    $null = [IO.Directory]::CreateDirectory($Destination)
    foreach ($file in $Inventory) {
        $from = Assert-ChildPath $Source (Join-Path $Source $file.path)
        $to = Assert-ChildPath $Destination (Join-Path $Destination $file.path)
        $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to))
        Copy-Item -LiteralPath $from -Destination $to -Force
        if ((Get-UpdateHash $to) -ne $file.sha256) { throw 'Backup/restore checksum failed' }
    }
}
function Get-UpdateRegistry([string]$Channel, [string]$Product='SecurityLabNative') {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall\'+$Product+'-'+$Channel+'_is1')
    $snapshot = @{}
    if ($null -ne $key) {
        try { foreach ($name in $key.GetValueNames()) { $snapshot[$name] = @{kind=$key.GetValueKind($name).ToString();value=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)} } }
        finally { $key.Dispose() }
    }
    @{exists=($null -ne $key);values=$snapshot}
}
function Restore-UpdateRegistry([string]$Channel, $Snapshot, [string]$Product='SecurityLabNative') {
    $name = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\'+$Product+'-'+$Channel+'_is1'
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($name,$false)
    if ($Snapshot.exists) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($name)
        $entries = if ($Snapshot.values -is [Collections.IDictionary]) { $Snapshot.values.GetEnumerator() } else { $Snapshot.values.PSObject.Properties | ForEach-Object { [pscustomobject]@{Key=$_.Name;Value=$_.Value} } }
        try { foreach ($entry in $entries) {
            $kind = [Microsoft.Win32.RegistryValueKind][Enum]::Parse([Microsoft.Win32.RegistryValueKind],$entry.Value.kind)
            $value = $entry.Value.value
            if ($kind -eq [Microsoft.Win32.RegistryValueKind]::Binary) { $value = [byte[]]$value }
            if ($kind -eq [Microsoft.Win32.RegistryValueKind]::MultiString) { $value = [string[]]$value }
            $key.SetValue($entry.Key,$value,$kind)
        } } finally { $key.Dispose() }
    }
}
function Remove-UpdateRegistry([string]$Channel, [string]$Product='SecurityLabNative') {
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('Software\Microsoft\Windows\CurrentVersion\Uninstall\'+$Product+'-'+$Channel+'_is1',$false)
}
# Only the beta product moves between stable and beta (the opt-in beta preview and
# the way back). Dev installs stay on their own channel.
function Test-UpdateChannelTransition([bool]$Beta, [string]$Current, [string]$Target) {
    if ($Target -ceq $Current) { return $true }
    $Beta -and $Current -in @('stable','beta') -and $Target -in @('stable','beta')
}
function ConvertTo-ProcessArgument([string]$Value) {
    '"'+[regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'
}
function Start-UpdateProcess([string]$Executable, [string[]]$Parameters) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable; $start.WorkingDirectory = [IO.Path]::GetDirectoryName($Executable)
    $start.UseShellExecute = $false
    $start.Arguments = ($Parameters | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join ' '
    [Diagnostics.Process]::Start($start)
}
function Assert-UpdateBuild($Info) {
    if ($Info.schema -ne 1 -or $Info.app_id -notin @('security-lab-native','security-lab-beta') -or $Info.platform -ne 'windows-x86_64' -or $Info.install_layout -ne 1 -or $Info.channel -notin @('stable','beta','dev') -or $Info.commit -cnotmatch '^[0-9a-f]{40}$') { throw 'Invalid build identity' }
    if ($Info.version -cnotmatch '^(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})(?:-([0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*))?$') { throw 'Invalid version' }
    if ($Info.channel -eq 'stable' -and $Info.version.Contains('-')) { throw 'Stable rejects prerelease versions' }
    if ($Info.channel -ne 'stable' -and $Info.version -cnotmatch ('-'+$Info.channel+'[.]')) { throw 'Prerelease channel mismatch' }
}
function Test-NewerUpdateVersion([string]$Remote,[string]$Current) {
    $a=$Remote.Split('-')[0].Split('.');$b=$Current.Split('-')[0].Split('.')
    for($i=0;$i -lt 3;$i++){if([int]$a[$i] -ne [int]$b[$i]){return [int]$a[$i] -gt [int]$b[$i]}}
    $ap=if($Remote.Contains('-')){$Remote.Substring($Remote.IndexOf('-')+1).Split('.')}else{@()}
    $bp=if($Current.Contains('-')){$Current.Substring($Current.IndexOf('-')+1).Split('.')}else{@()}
    if($Remote -ceq $Current){return $false};if(-not $ap.Count){return $true};if(-not $bp.Count){return $false}
    for($i=0;$i -lt [Math]::Min($ap.Count,$bp.Count);$i++){
        if($ap[$i] -ceq $bp[$i]){continue}
        $an=$ap[$i] -match '^[0-9]+$';$bn=$bp[$i] -match '^[0-9]+$'
        if($an -and $bn){return [decimal]$ap[$i] -gt [decimal]$bp[$i]};if($an -ne $bn){return -not $an}
        return [String]::CompareOrdinal($ap[$i],$bp[$i]) -gt 0
    }
    return $ap.Count -gt $bp.Count
}
function Invoke-SecurityLabUpdate([string]$TransactionPath) {
    $stageRoot = ''; $installerLock = $null; $backupReady = $false; $targetRegistrySnapshot = $null; $newProcess = $null; $parentProcess = $null; $installStarted = $false
    try {
        $transactionPath = Assert-LocalPath $TransactionPath
        $stageRoot = [IO.Path]::GetDirectoryName($transactionPath)
        $nonce = [IO.Path]::GetFileName($stageRoot)
        $dataRoot = Assert-LocalPath (Get-SecurityLabDataRoot)
        $expectedStage = Join-Path (Join-Path $dataRoot 'updates') $nonce
        $betaStage = Join-Path (Join-Path $dataRoot 'beta-updates') $nonce
        if ($nonce -cnotmatch '^[0-9a-f]{32}$' -or ($stageRoot -ne $expectedStage -and $stageRoot -ne $betaStage) -or [IO.Path]::GetFileName($transactionPath) -ne 'transaction.json') { $stageRoot=''; throw 'Invalid staging directory' }
        if ((Get-Item -LiteralPath $transactionPath).Length -gt 16384) { throw 'Transaction too large' }
        $request = Get-Content -LiteralPath $transactionPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($request.schema -ne 1 -or $request.token -cne $nonce) { throw 'Invalid transaction identity' }
        Assert-UpdateBuild $request.current; Assert-UpdateBuild $request.target
        $channel = $request.current.channel
        if ($request.target.app_id -cne $request.current.app_id) { throw 'Product mismatch' }
        $beta = $request.current.app_id -eq 'security-lab-beta'
        if ($stageRoot -ne $(if ($beta) {$betaStage} else {$expectedStage})) { throw 'Product stage mismatch' }
        $product = if ($beta) {'SecurityLabBeta'} else {'SecurityLabNative'}
        $targetChannel = $request.target.channel
        if (-not (Test-UpdateChannelTransition $beta $channel $targetChannel)) { throw 'Channel mismatch' }
        if (-not (Test-NewerUpdateVersion $request.target.version $request.current.version)) { throw 'Downgrade or duplicate version rejected' }
        if ($request.parent_pid -le 0 -or $request.parent_pid -gt 2147483647 -or $request.parent_pid -ne [Math]::Floor($request.parent_pid)) { throw 'Invalid parent PID' }
        if ($request.target.sha256 -cnotmatch '^[0-9a-f]{64}$' -or $request.target.exe_sha256 -cnotmatch '^[0-9a-f]{64}$' -or $request.target.size -lt 1024 -or $request.target.size -gt 512MB) { throw 'Invalid payload digest or size' }
        $installRoot = Assert-LocalPath $request.install_directory
        if ($installRoot.Length -lt 10 -or $installRoot -in @($env:USERPROFILE,$env:APPDATA,$env:LOCALAPPDATA,$env:ProgramFiles,${env:ProgramFiles(x86)},$env:SystemRoot) -or $installRoot.StartsWith($dataRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or $stageRoot.StartsWith($installRoot+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe install directory' }
        $progressRoot = Assert-LocalPath $request.data_directory
        if ($progressRoot -ne $dataRoot -and -not ($channel -eq 'dev' -and $progressRoot.StartsWith($dataRoot+'\qa\',[StringComparison]::OrdinalIgnoreCase))) { throw 'Unexpected save directory' }
        $appExe = Join-Path $installRoot 'SecurityLab.exe'
        $sidecar = Get-Content -LiteralPath (Join-Path $installRoot 'build_info.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $marker = Get-Content -LiteralPath (Join-Path $installRoot 'securitylab.install.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($marker.app_id -cne $request.current.app_id -or $marker.channel -cne $channel -or $marker.install_layout -ne 1 -or $sidecar.version -cne $request.current.version -or $sidecar.commit -cne $request.current.commit -or $sidecar.channel -cne $channel) { throw 'Installed identity mismatch' }
        $null = Get-UpdateTree $installRoot
        $parentProcess = [Diagnostics.Process]::GetProcessById([int]$request.parent_pid)
        if ($parentProcess.MainModule.FileName -ne $appExe) { throw 'Parent process is not this installation' }
        foreach ($otherProcess in Get-Process -Name SecurityLab -ErrorAction SilentlyContinue) {
            if ($otherProcess.Id -ne $parentProcess.Id -and $otherProcess.MainModule.FileName -eq $appExe) { throw 'Another instance is using this installation' }
        }
        $installer = Join-Path $stageRoot 'SecurityLabSetup.exe'
        $installerLock = [IO.File]::Open($installer,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        if ($installerLock.Length -ne $request.target.size -or (Get-UpdateHash $installer).ToLowerInvariant() -cne $request.target.sha256) { throw 'Installer hash/size mismatch before shutdown' }
        Write-UpdateJson (Join-Path $stageRoot 'ready.json') @{token=$nonce;pid=[Diagnostics.Process]::GetCurrentProcess().Id}
        if (-not $parentProcess.WaitForExit(60000)) { throw 'Game did not exit; installation cancelled' }
        $backupRoot = Assert-ChildPath $stageRoot (Join-Path $stageRoot 'backup')
        $inventory = @(Get-UpdateTree $installRoot)
        Copy-UpdateTree $installRoot $backupRoot $inventory
        $saveSnapshot = @()
        $saveNames = if ($beta) {@('investigation/save.json','investigation/save.backup.json','controls.cfg','beta-settings.json','input_bindings.json',('beta-update-settings-'+$channel+'.json'),('beta-update-settings-'+$targetChannel+'.json')) | Select-Object -Unique} else {@('progress.json','progress.backup.json')}
        foreach ($saveName in $saveNames) {
            $savePath = Join-Path $progressRoot $saveName
            $exists = Test-Path -LiteralPath $savePath
            if ($exists) {
                $null = Assert-ChildPath $progressRoot $savePath
                if ((Get-Item -LiteralPath $savePath).Length -gt $(if ($beta) {262144} else {131072})) { throw 'Save exceeds native save limit' }
                $saveHash = Get-UpdateHash $savePath
                Copy-Item -LiteralPath $savePath -Destination (Join-Path $stageRoot ('saved-'+$saveName.Replace('/','_')))
                if ((Get-UpdateHash (Join-Path $stageRoot ('saved-'+$saveName.Replace('/','_')))) -ne $saveHash) { throw 'Save backup verification failed' }
            } else { $saveHash = '' }
            $saveSnapshot += @{name=$saveName;exists=$exists;sha256=$saveHash}
        }
        $registrySnapshot = Get-UpdateRegistry $channel $product
        if ($targetChannel -cne $channel) { $targetRegistrySnapshot = Get-UpdateRegistry $targetChannel $product }
        Write-UpdateJson (Join-Path $stageRoot 'backup.json') @{files=$inventory;saves=$saveSnapshot;registry=$registrySnapshot;registry_target=$targetRegistrySnapshot;install=$installRoot;data=$progressRoot;channel=$channel;target_channel=$targetChannel}
        $backupReady = $true
        # Hold a read-only, non-delete-sharing handle through installer execution.
        if ((Get-UpdateHash $installer).ToLowerInvariant() -cne $request.target.sha256) { throw 'Installer changed immediately before install' }
        $installStarted = $true
        $setupProcess = Start-UpdateProcess $installer @('/VERYSILENT','/SUPPRESSMSGBOXES','/SP-','/NORESTART','/NOCLOSEAPPLICATIONS','/NOICONS',('/DIR='+$installRoot),('/LOG='+$stageRoot+'\installer.log'))
        if (-not $setupProcess.WaitForExit(180000)) {
            $killer = Start-UpdateProcess ($env:SystemRoot+'\System32\taskkill.exe') @('/PID',[string]$setupProcess.Id,'/T','/F')
            $null = $killer.WaitForExit(10000)
            if (-not $setupProcess.WaitForExit(10000)) { $backupReady=$false; throw 'Installer timeout; backup retained for manual recovery' }
            throw 'Installer timed out'
        }
        if ($setupProcess.ExitCode -ne 0) { throw ('Installer exited '+$setupProcess.ExitCode) }
        $null = Get-UpdateTree $installRoot
        $newBuild = Get-Content -LiteralPath (Join-Path $installRoot 'build_info.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-UpdateBuild $newBuild
        $newMarker = Get-Content -LiteralPath (Join-Path $installRoot 'securitylab.install.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($newBuild.channel -cne $targetChannel -or $newBuild.version -cne $request.target.version -or $newBuild.commit -cne $request.target.commit -or $newMarker.app_id -cne $request.current.app_id -or $newMarker.channel -cne $targetChannel -or (Get-UpdateHash $appExe).ToLowerInvariant() -cne $request.target.exe_sha256) { throw 'Installed payload identity/digest mismatch' }
        Write-UpdateJson (Join-Path $stageRoot 'result.json') @{state='verifying_startup';token=$nonce}
        $newProcess = Start-UpdateProcess $appExe @('--','--disable-updates',('--update-relaunch='+$nonce))
        $healthy = $false
        for ($attempt=0; $attempt -lt 300; $attempt++) {
            if ($newProcess.HasExited) { break }
            $healthFile = Join-Path $stageRoot 'health.json'
            if (Test-Path -LiteralPath $healthFile) {
                try { $health = Get-Content -LiteralPath $healthFile -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($health.token -ceq $nonce -and $health.version -ceq $newBuild.version -and $health.pid -eq $newProcess.Id) { $healthy=$true; break }
                } catch { }
            }
            Start-Sleep -Milliseconds 100
        }
        if (-not $healthy -or $newProcess.WaitForExit(1000)) { throw 'New game did not complete startup health check' }
        Write-UpdateJson (Join-Path $stageRoot 'result.json') @{state='installed';token=$nonce;version=$newBuild.version;pid=$newProcess.Id}
        # A channel switch installs under the target channel's product entry; drop the old one.
        if ($targetChannel -cne $channel) { try { Remove-UpdateRegistry $channel $product } catch { } }
        $null = Assert-ChildPath $stageRoot $backupRoot
        Remove-Item -LiteralPath $backupRoot -Recurse -Force
        $installerLock.Dispose(); $installerLock=$null
        Remove-Item -LiteralPath $installer -Force
        return 0
    } catch {
        $failure = $_.Exception.Message
        if ($null -ne $newProcess -and -not $newProcess.HasExited) { $newProcess.Kill(); $null=$newProcess.WaitForExit(10000) }
        if ($backupReady) {
            try {
                # Verify every backup before removing only this managed install's contents.
                foreach ($file in $inventory) { $backupFile = Assert-ChildPath $backupRoot (Join-Path $backupRoot $file.path); if ((Get-UpdateHash $backupFile) -ne $file.sha256) { throw 'Rollback backup corrupt' } }
                $null = Get-UpdateTree $installRoot
                foreach ($item in Get-ChildItem -LiteralPath $installRoot -Force) { $null=Assert-ChildPath $installRoot $item.FullName; Remove-Item -LiteralPath $item.FullName -Recurse -Force }
                Copy-UpdateTree $backupRoot $installRoot $inventory
                foreach ($save in $saveSnapshot) {
                    $destination = Assert-ChildPath $progressRoot (Join-Path $progressRoot $save.name)
                    if ($save.exists) {
                        $from = Join-Path $stageRoot ('saved-'+$save.name.Replace('/','_'))
                        if ((Get-UpdateHash $from) -ne $save.sha256) { throw 'Rollback save corrupt' }
                         $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
                        Copy-Item -LiteralPath $from -Destination $destination -Force
                    } elseif (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }
                }
                Restore-UpdateRegistry $channel $registrySnapshot $product
                if ($null -ne $targetRegistrySnapshot) { Restore-UpdateRegistry $targetChannel $targetRegistrySnapshot $product }
                Write-UpdateJson (Join-Path $stageRoot 'result.json') @{state='rolled_back';token=$nonce;error=$failure;backup=$backupRoot}
                $oldProcess = Start-UpdateProcess $appExe @('--','--disable-updates',('--update-rollback='+$nonce))
                return 1
            } catch {
                Write-UpdateJson (Join-Path $stageRoot 'result.json') @{state='recovery_required';token=$nonce;error=$_.Exception.Message;backup=$backupRoot}
                return 3
            }
        }
        if ($stageRoot) { Write-UpdateJson (Join-Path $stageRoot 'result.json') @{state=($(if ($installStarted) {'recovery_required'} else {'cancelled'}));error=$failure} }
        # A pre-install failure after shutdown can safely relaunch the unchanged app.
        if ($null -ne $parentProcess -and $parentProcess.HasExited -and -not $installStarted) { $oldProcess=Start-UpdateProcess $appExe @('--','--disable-updates') }
        return 2
    } finally { if ($null -ne $installerLock) { $installerLock.Dispose() } }
}
if (-not $Library) { exit (Invoke-SecurityLabUpdate $RequestPath) }
