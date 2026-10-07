param([switch]$Beta, [string]$Iscc='', [string]$Results='godot/tests/results/windows-updater.json')
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'godot/resources/native_update_helper.ps1') -Library
if (-not $Iscc) { $Iscc=Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe' }
if (-not (Test-Path -LiteralPath $Iscc)) { throw 'Inno Setup compiler required for real installer tests' }
$checks=[Collections.Generic.List[string]]::new()
function Expect([bool]$Condition,[string]$Label) { if (-not $Condition) { throw $Label }; $checks.Add($Label) }
function Expect-Reject([scriptblock]$Code,[string]$Label) { $rejected=$false; try { & $Code | Out-Null } catch { $rejected=$true }; Expect $rejected $Label }
$fixtureRoot=Join-Path $repoRoot ('godot/builds/update-tests/'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $fixtureRoot -Force
$csc=Join-Path $env:SystemRoot 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$stub=@'
using System; using System.IO; using System.Linq; using System.Threading; using System.Diagnostics; using System.Collections.Generic; using System.Web.Script.Serialization;
class Fixture {
 static void Main(string[] args) {
  string flag=args.FirstOrDefault(x=>x.StartsWith("--update-relaunch=")||x.StartsWith("--update-rollback="));
  if(flag==null){Thread.Sleep(60000);return;}
  string token=flag.Substring(flag.IndexOf('=')+1);
  string stage=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"Godot","app_userdata","Security Lab \u00b7 Native","updates",token);
  var json=new JavaScriptSerializer();
  if(flag.StartsWith("--update-rollback=")){File.WriteAllText(Path.Combine(stage,"old-restarted.txt"),"yes");return;}
  var transaction=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(stage,"transaction.json")));
  if(!__HEALTHY__){File.WriteAllText(Path.Combine((string)transaction["data_directory"],"progress.json"),"incompatible new save");Environment.Exit(17);}
  var build=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"build_info.json")));
  File.WriteAllText(Path.Combine(stage,"health.json"),json.Serialize(new {token=token, version=build["version"], pid=Process.GetCurrentProcess().Id}));
  for(int i=0;i<600;i++){if(File.Exists(Path.Combine(stage,"release-child")))return;Thread.Sleep(100);}
 }
}
'@
$badSetup=@'
using System;using System.IO;using System.Linq;
class BadSetup {static void Main(string[] args){string dir=args.First(x=>x.StartsWith("/DIR=")).Substring(5);File.WriteAllText(Path.Combine(dir,"SecurityLab.exe"),"partial failed install");File.WriteAllText(Path.Combine(dir,"unexpected.bin"),"partial");Environment.Exit(5);}}
'@
function Compile-Fixture([string]$Code,[string]$Destination) {
    [IO.File]::WriteAllText($Destination+'.cs',$Code,[Text.UTF8Encoding]::new($false))
    & $csc /nologo /target:exe /platform:x64 ('/out:'+$Destination) /reference:System.Web.Extensions.dll ($Destination+'.cs') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Fixture compiler failed' }
}
$product = if ($Beta) {'SecurityLabBeta'} else {'SecurityLabNative'}
$appId = if ($Beta) {'security-lab-beta'} else {'security-lab-native'}
$saveName = if ($Beta) {'investigation/save.json'} else {'progress.json'}
$stageName = if ($Beta) {'beta-updates'} else {'updates'}
if ($Beta) { $stub=$stub.Replace('"updates",token','"beta-updates",token').Replace('"progress.json"','"investigation/save.json"') }
$oldStub=Join-Path $fixtureRoot 'old.exe'; Compile-Fixture ($stub.Replace('__HEALTHY__','true')) $oldStub
$newStub=Join-Path $fixtureRoot 'new.exe'; Compile-Fixture ($stub.Replace('__HEALTHY__','true')) $newStub
$failedStub=Join-Path $fixtureRoot 'failed.exe'; Compile-Fixture ($stub.Replace('__HEALTHY__','false')) $failedStub
$badInstaller=Join-Path $fixtureRoot 'badsetup.exe'; Compile-Fixture $badSetup $badInstaller
$sourceMarker=@{app_id=$appId;channel='dev';install_layout=1}
function Build-Info([string]$Version,[string]$Commit) { @{schema=1;app_id=$appId;platform='windows-x86_64';version=$Version;channel='dev';commit=$Commit;install_layout=1;updates_default=$false;manifest_url='https://github.com/nu4ddi4/security-lab-game/releases/download/native-channel-dev/update.json'} }
$oldBuild=Build-Info '0.7.0-dev.0' ('a'*40)
$newBuild=Build-Info '0.7.1-dev.1' ('b'*40)
function Compile-Setup([string]$App,[string]$Label) {
    $output=Join-Path $fixtureRoot $Label; $payload=Join-Path $output 'payload'
    $null=New-Item -ItemType Directory -Path $payload -Force
    Copy-Item -LiteralPath $App -Destination (Join-Path $payload 'SecurityLab.exe')
    Write-UpdateJson (Join-Path $payload 'build_info.json') $newBuild
    Write-UpdateJson (Join-Path $payload 'securitylab.install.json') $sourceMarker
    $compilerOutput = @(& $Iscc /Qp ('/DSourceDirectory='+$payload) ('/DOutputDirectory='+$output) '/DChannel=dev' '/DAppVersion=0.7.1-dev.1' '/DBinaryVersion=0.7.1.0' (Join-Path $repoRoot $(if ($Beta) {'installer/SecurityLabBeta.iss'} else {'installer/SecurityLab.iss'})) 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ('Real Inno fixture compilation failed: '+($compilerOutput -join "`n")) }
    Join-Path $output 'SecurityLabSetup.exe'
}
$successSetup=Compile-Setup $newStub 'healthy-package'
$failureSetup=Compile-Setup $failedStub 'startup-failure-package'
Expect-Reject { Assert-LocalPath '\\server\share\game' } 'UNC denied'
Expect-Reject { Assert-LocalPath 'C:\games\file:stream' } 'NTFS alternate stream denied'
Expect-Reject { Assert-ChildPath $fixtureRoot (Join-Path $fixtureRoot '../escape') } 'Traversal denied'
Expect ((ConvertTo-ProcessArgument 'a & b% $c').StartsWith('"')) 'Opaque process arguments'
$registryBefore=Get-UpdateRegistry 'dev' $product
$owned=@();$stages=@()
try {
 foreach ($case in @('success','installer-failure','startup-failure','wrong-hash','wrong-channel','junction','second-instance')) {
    $nonce=[Guid]::NewGuid().ToString('N')
    $stage=Join-Path (Get-SecurityLabDataRoot) ($stageName+'/'+$nonce);$stages+=,$stage
    $saveRoot=Join-Path (Get-SecurityLabDataRoot) ('qa/updater/'+$nonce)
    $installRoot=Join-Path $fixtureRoot ($case+' A & B% $ (space) '+[char]0xd55c)
    $null=New-Item -ItemType Directory -Path $stage,$installRoot,$saveRoot -Force
    Copy-Item -LiteralPath $oldStub -Destination (Join-Path $installRoot 'SecurityLab.exe')
    Write-UpdateJson (Join-Path $installRoot 'build_info.json') $oldBuild
    Write-UpdateJson (Join-Path $installRoot 'securitylab.install.json') $sourceMarker
    [IO.File]::WriteAllText((Join-Path $installRoot 'old-only.txt'),'keep whole install')
    $null=New-Item -ItemType Directory -Path (Join-Path $saveRoot 'investigation') -Force
    [IO.File]::WriteAllText((Join-Path $saveRoot $saveName),'original saved progress')
    if ($Beta) { [IO.File]::WriteAllText((Join-Path $saveRoot 'controls.cfg'),'original controls') }
    $setup=if ($case -eq 'installer-failure') {$badInstaller} elseif ($case -eq 'startup-failure') {$failureSetup} else {$successSetup}
    Copy-Item -LiteralPath $setup -Destination (Join-Path $stage 'SecurityLabSetup.exe')
    $target=@{schema=1;app_id=$appId;platform='windows-x86_64';install_layout=1;channel='dev';version=$newBuild.version;commit=$newBuild.commit;size=(Get-Item -LiteralPath $setup).Length;sha256=(Get-FileHash -LiteralPath $setup).Hash.ToLowerInvariant();exe_sha256=(Get-FileHash -LiteralPath (Join-Path $fixtureRoot 'healthy-package/payload/SecurityLab.exe')).Hash.ToLowerInvariant()}
    if ($case -eq 'startup-failure') {$target.exe_sha256=(Get-FileHash -LiteralPath $failedStub).Hash.ToLowerInvariant()}
    if ($case -eq 'wrong-hash') {$target.sha256='c'*64}
    if ($case -eq 'wrong-channel') {$target.channel='beta';$target.version='0.7.1-beta.1'}
    $parent=Start-UpdateProcess (Join-Path $installRoot 'SecurityLab.exe') @('hold');$owned+=,$parent
    if ($case -eq 'second-instance') { $second=Start-UpdateProcess (Join-Path $installRoot 'SecurityLab.exe') @('hold');$owned+=,$second }
    if ($case -eq 'junction') {
        $junctionTarget=Join-Path $fixtureRoot 'junction-target';$null=New-Item -ItemType Directory -Path $junctionTarget -Force
        $null=New-Item -ItemType Junction -Path (Join-Path $installRoot 'link') -Target $junctionTarget
    }
    $transaction=@{schema=1;token=$nonce;parent_pid=$parent.Id;install_directory=$installRoot;data_directory=$saveRoot;current=$oldBuild;target=$target}
    $transactionPath=Join-Path $stage 'transaction.json'; Write-UpdateJson $transactionPath $transaction
    $helper=Start-UpdateProcess ($env:SystemRoot+'\System32\WindowsPowerShell\v1.0\powershell.exe') @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $repoRoot 'godot/resources/native_update_helper.ps1'),'-RequestPath',$transactionPath);$owned+=,$helper
    for ($attempt=0;$attempt -lt 100;$attempt++){if((Test-Path -LiteralPath (Join-Path $stage 'ready.json')) -or $helper.HasExited){break};Start-Sleep -Milliseconds 100}
    if ($case -in @('wrong-hash','wrong-channel','junction','second-instance')) {
        Expect ($helper.WaitForExit(5000)) ($case+' rejected promptly')
        Expect (-not (Test-Path -LiteralPath (Join-Path $stage 'ready.json'))) ($case+' rejected before game exit')
        Expect (-not $parent.HasExited) ($case+' leaves game running')
        if ($case -eq 'junction'){[IO.Directory]::Delete((Join-Path $installRoot 'link'))}
        $parent.Kill();$null=$parent.WaitForExit(5000)
    } else {
        Expect (Test-Path -LiteralPath (Join-Path $stage 'ready.json')) ($case+' preflight handshake')
        Expect-Reject { [IO.File]::WriteAllText((Join-Path $stage 'SecurityLabSetup.exe'),'tamper') } ($case+' installer file pinned against replacement')
        $parent.Kill();$null=$parent.WaitForExit(5000)
        Expect ($helper.WaitForExit(45000)) ($case+' helper completed')
        $result=Get-Content -LiteralPath (Join-Path $stage 'result.json') -Raw | ConvertFrom-Json
        if ($case -eq 'success') {
            Expect ($result.state -eq 'installed') 'real Inno install and startup health succeeded'
            Expect ((Get-FileHash -LiteralPath (Join-Path $installRoot 'SecurityLab.exe')).Hash -eq (Get-FileHash -LiteralPath $newStub).Hash) 'new EXE exact'
            Expect (-not (Test-Path -LiteralPath (Join-Path $stage 'backup'))) 'backup removed only after health'
            [IO.File]::WriteAllText((Join-Path $stage 'release-child'),'done')
            $child=[Diagnostics.Process]::GetProcessById([int]$result.pid);$owned+=,$child;$null=$child.WaitForExit(5000)
        } else {
            Expect ($result.state -eq 'rolled_back') ($case+' rollback completed')
            Expect ((Get-FileHash -LiteralPath (Join-Path $installRoot 'SecurityLab.exe')).Hash -eq (Get-FileHash -LiteralPath $oldStub).Hash) ($case+' old EXE restored')
            Expect (-not (Test-Path -LiteralPath (Join-Path $installRoot 'unexpected.bin'))) ($case+' partial install files removed')
            Expect (Test-Path -LiteralPath (Join-Path $installRoot 'old-only.txt')) ($case+' whole install restored')
            for($attempt=0;$attempt -lt 30;$attempt++){if(Test-Path -LiteralPath (Join-Path $stage 'old-restarted.txt')){break};Start-Sleep -Milliseconds 100}
            Expect (Test-Path -LiteralPath (Join-Path $stage 'old-restarted.txt')) ($case+' old game restarted')
            Expect (Test-Path -LiteralPath (Join-Path $stage 'backup.json')) ($case+' recovery journal retained')
        }
    }
    Expect ((Get-Content -LiteralPath (Join-Path $saveRoot $saveName) -Raw) -eq 'original saved progress') ($case+' saves preserved')
    if ($Beta) { Expect ((Get-Content -LiteralPath (Join-Path $saveRoot 'controls.cfg') -Raw) -eq 'original controls') ($case+' beta input settings preserved') }
    Restore-UpdateRegistry 'dev' $registryBefore $product
 }
 $summary=@{passed=$true;product=$appId;assertions=$checks.Count;checks=$checks.ToArray();fixture_directory=$fixtureRoot;method='Real Inno installers and isolated Windows fixture EXEs; game missions tested separately'}
 $resultPath=[IO.Path]::GetFullPath($Results,$repoRoot);$null=New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($resultPath)) -Force
 Write-UpdateJson $resultPath $summary
 Write-Output ('WINDOWS_UPDATE_TEST '+($summary | ConvertTo-Json -Compress -Depth 5))
} finally {
 foreach($process in $owned){try{if(-not $process.HasExited){$process.Kill();$null=$process.WaitForExit(5000)}}catch{}}
 Restore-UpdateRegistry 'dev' $registryBefore $product
 # Fixtures and backup journals are kept under owned test directories for review.
}
