#ifndef SourceDirectory
  #define SourceDirectory "..\godot\builds\package\dev\payload"
#endif
#ifndef OutputDirectory
  #define OutputDirectory "..\godot\builds\package\dev"
#endif
#ifndef Channel
  #define Channel "dev"
#endif
#ifndef AppVersion
  #define AppVersion "0.3.0-beta.1"
#endif
#ifndef BinaryVersion
  #define BinaryVersion "0.3.0.0"
#endif

[Setup]
AppId=SecurityLabBeta-{#Channel}
AppName=Security Lab Beta ({#Channel})
AppVersion={#AppVersion}
AppPublisher=Security Lab contributors
AppPublisherURL=https://github.com/nu4ddi4/security-lab-game
DefaultDirName={localappdata}\Programs\SecurityLabBeta-{#Channel}
DefaultGroupName=Security Lab Beta ({#Channel})
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
CloseApplications=no
RestartApplications=no
Uninstallable=yes
UninstallDisplayIcon={app}\SecurityLab.exe
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDirectory}
OutputBaseFilename=SecurityLabSetup
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern
VersionInfoVersion={#BinaryVersion}
VersionInfoDescription=Security Lab Windows Beta Installer ({#Channel})
VersionInfoProductName=Security Lab Beta
VersionInfoProductVersion={#BinaryVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Tasks]
Name: "desktopicon"; Description: "바탕 화면 바로가기 만들기"; Flags: unchecked

[Files]
Source: "{#SourceDirectory}\SecurityLab.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDirectory}\build_info.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDirectory}\securitylab.install.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDirectory}\LICENSES.txt"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\Security Lab"; Filename: "{app}\SecurityLab.exe"; WorkingDir: "{app}"
Name: "{group}\Security Lab 제거"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Security Lab Beta ({#Channel})"; Filename: "{app}\SecurityLab.exe"; Tasks: desktopicon; WorkingDir: "{app}"

[Run]
Filename: "{app}\SecurityLab.exe"; Description: "Security Lab 실행"; Flags: nowait postinstall skipifsilent
