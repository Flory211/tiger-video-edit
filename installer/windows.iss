#define AppName "Tiger Video Edit"
#ifndef AppVersion
#define AppVersion "3.0.1"
#endif
[Setup]
AppId={{F532F8DE-68FC-47B4-86C0-B22BDA909622}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Tiger
DefaultDirName={localappdata}\Programs\TigerVideoEdit
DefaultGroupName={#AppName}
UsePreviousGroup=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=TigerVideoEdit-{#AppVersion}-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\tiger_video_edit.exe
LicenseFile=..\LICENSE
ChangesAssociations=yes
[Files]
Source: "..\build\windows\x64\runner\Release\*"; Excludes: "leos_fast_video_edit.exe"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\docs\THIRD_PARTY.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\demo\*"; DestDir: "{app}\demo"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\tiger_video_edit.exe"
Name: "{group}\Удалить Tiger Video Edit"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\tiger_video_edit.exe"; Tasks: desktopicon
[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; Flags: unchecked
[Run]
Filename: "{app}\tiger_video_edit.exe"; Description: "Запустить Tiger Video Edit"; Flags: nowait postinstall skipifsilent


[InstallDelete]
Type: files; Name: "{app}\leos_fast_video_edit.exe"
[Registry]
Root: HKA; Subkey: "Software\Classes\.tve"; ValueType: string; ValueName: ""; ValueData: "TigerVideoEdit.Project"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\TigerVideoEdit.Project"; ValueType: string; ValueName: ""; ValueData: "Tiger Video Edit Project"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\TigerVideoEdit.Project\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\tiger_video_edit.exe,0"
Root: HKA; Subkey: "Software\Classes\TigerVideoEdit.Project\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\tiger_video_edit.exe"" ""%1"""
