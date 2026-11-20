#ifndef AppVersion
  #define AppVersion "3.0.1"
#endif
#ifndef AppBuild
  #define AppBuild "3006"
#endif
#ifndef PayloadDir
  #error PayloadDir is required
#endif
#ifndef EngineSHA256
  #error EngineSHA256 is required
#endif

[Setup]
AppId={{F532F8DE-68FC-47B4-86C0-B22BDA909622}
AppName=Tiger Video Edit
AppVersion={#AppVersion}
AppPublisher=Tiger
DefaultDirName={localappdata}\Programs\TigerVideoEdit
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist\windows-update
OutputBaseFilename=TigerVideoEdit-{#AppVersion}-Windows-x64-Update-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
LicenseFile=..\LICENSE
Uninstallable=no
CloseApplications=no
RestartApplications=no
SetupLogging=yes

[Files]
Source: "{#PayloadDir}\tiger_video_edit.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Run]
Filename: "{app}\tiger_video_edit.exe"; WorkingDir: "{app}"; Description: "Запустить Tiger Video Edit"; Flags: nowait postinstall skipifsilent

[Code]
function IsUnlocked(const FileName: String): Boolean;
var Stream: TFileStream;
begin
  Result := False;
  try
    { Read/write + exclusive sharing; open an existing file, without changing it. }
    Stream := TFileStream.Create(FileName, $0012);
    Stream.Free;
    Result := True;
  except
    Result := False;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var Root, Version: String;
begin
  Root := ExpandConstant('{app}');
  Result := 'Это обновление для установленного Tiger Video Edit 3.0.0 (сборка 3004/3005). Базовая программа не найдена в выбранной папке.';
  if not GetVersionNumbersString(Root + '\tiger_video_edit.exe', Version) then Exit;
  if (Version <> '3.0.0.3004') and (Version <> '3.0.0.3005') and
     (Version <> '{#AppVersion}.{#AppBuild}') then Exit;
  Result := 'Не найдены необходимые компоненты установленной программы. Обновление не изменило файлы.';
  if not FileExists(Root + '\data\app.so') or
     not FileExists(Root + '\flutter_windows.dll') or
     not FileExists(Root + '\libmpv-2.dll') or
     not FileExists(Root + '\file_selector_windows_plugin.dll') or
     not FileExists(Root + '\tools\ffmpeg.exe') or
     not FileExists(Root + '\tools\ffprobe.exe') then Exit;
  Result := 'Установленная версия медиадвижка несовместима с этим обновлением. Файлы программы не изменены.';
  try
    if Lowercase(GetSHA256OfFile(Root + '\flutter_windows.dll')) <> '{#EngineSHA256}' then Exit;
    if Lowercase(GetSHA256OfFile(Root + '\libmpv-2.dll')) <> '04e4d27dc385dc18ddd93fbe69c75e635b864f3c6ec53a9122df54c2f7842f4a' then Exit;
  except
    Exit;
  end;
  Result := 'Сохрани проект и полностью закрой Tiger Video Edit, затем повтори установку обновления. Автоматически закрывать редактор установщик не будет.';
  if not IsUnlocked(Root + '\tiger_video_edit.exe') or
     not IsUnlocked(Root + '\data\app.so') then Exit;
  Result := '';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var Key: String;
begin
  if (CurStep = ssPostInstall) and (ExpandConstant('{param:TVEISOLATED|0}') <> '1') then begin
    Key := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{F532F8DE-68FC-47B4-86C0-B22BDA909622}_is1';
    if RegKeyExists(HKCU, Key) then
      RegWriteStringValue(HKCU, Key, 'DisplayVersion', '{#AppVersion}');
  end;
end;
