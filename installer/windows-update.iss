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
#ifndef RunnerSHA256
  #error RunnerSHA256 is required
#endif
#ifndef AotSHA256
  #error AotSHA256 is required
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
AllowCancelDuringInstall=no
SetupMutex=TigerVideoEditApplicationUpdate
SetupLogging=yes

[Files]
Source: "{#PayloadDir}\tiger_video_edit.exe"; DestDir: "{app}"; Flags: ignoreversion; AfterInstall: TestFailureAfterRunner
Source: "{#PayloadDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Run]
Filename: "{app}\tiger_video_edit.exe"; WorkingDir: "{app}"; Description: "Запустить Tiger Video Edit"; Flags: nowait postinstall skipifsilent

[Code]
var
  PayloadPaths: TArrayOfString;
  Destination, BackupDir: String;
  BackupReady, Completed: Boolean;

procedure InitializeWizard;
begin
  SetArrayLength(PayloadPaths, 12);
  PayloadPaths[0] := 'tiger_video_edit.exe';
  PayloadPaths[1] := 'data\app.so';
  PayloadPaths[2] := 'data\icudtl.dat';
  PayloadPaths[3] := 'data\flutter_assets\AssetManifest.bin';
  PayloadPaths[4] := 'data\flutter_assets\FontManifest.json';
  PayloadPaths[5] := 'data\flutter_assets\NativeAssetsManifest.json';
  PayloadPaths[6] := 'data\flutter_assets\NOTICES.Z';
  PayloadPaths[7] := 'data\flutter_assets\fonts\MaterialIcons-Regular.otf';
  PayloadPaths[8] := 'data\flutter_assets\packages\cupertino_icons\assets\CupertinoIcons.ttf';
  PayloadPaths[9] := 'data\flutter_assets\packages\media_kit\assets\web\hls1.4.10.js';
  PayloadPaths[10] := 'data\flutter_assets\shaders\ink_sparkle.frag';
  PayloadPaths[11] := 'data\flutter_assets\shaders\stretch_effect.frag';
end;

function IsRollbackTest: Boolean;
begin
  Result := (ExpandConstant('{param:TVEISOLATED|0}') = '1') and
            (ExpandConstant('{param:TVEFAILTEST|0}') = '1');
end;

procedure TestFailureAfterRunner;
begin
  if IsRollbackTest then
    RaiseException('Isolated rollback test: forced failure after runner replacement');
end;

function BackupOwned: Boolean;
var Marker: AnsiString;
begin
  Result := LoadStringFromFile(BackupDir + '\OWNER', Marker) and
            (Marker = 'TigerVideoEditApplicationUpdate-{#AppVersion}');
end;

procedure ClearOwnedBackup;
var I: Integer; Folder: String;
begin
  if not BackupOwned then Exit;
  { Delete only our 12 backup files and remove empty directories, never user files. }
  for I := 0 to GetArrayLength(PayloadPaths) - 1 do begin
    DeleteFile(BackupDir + '\' + PayloadPaths[I]);
    Folder := ExtractFileDir(BackupDir + '\' + PayloadPaths[I]);
    while (Length(Folder) > Length(BackupDir)) and
          (Pos(BackupDir + '\', Folder + '\') = 1) do begin
      if not RemoveDir(Folder) then Break;
      Folder := ExtractFileDir(Folder);
    end;
  end;
  DeleteFile(BackupDir + '\READY');
  DeleteFile(BackupDir + '\OWNER');
  RemoveDir(BackupDir);
end;

function RestoreBackup: Boolean;
var I: Integer;
begin
  Result := False;
  if not BackupOwned or not FileExists(BackupDir + '\READY') then Exit;
  for I := 0 to GetArrayLength(PayloadPaths) - 1 do
    if not FileExists(BackupDir + '\' + PayloadPaths[I]) then Exit;
  for I := 0 to GetArrayLength(PayloadPaths) - 1 do
    if not FileCopy(BackupDir + '\' + PayloadPaths[I], Destination + '\' + PayloadPaths[I], False) then Exit;
  Result := True;
  BackupReady := False;
  ClearOwnedBackup;
end;

function SaveBackup: Boolean;
var I: Integer; Target: String;
begin
  Result := False;
  if DirExists(BackupDir) then Exit;
  if not ForceDirectories(BackupDir) then Exit;
  if not SaveStringToFile(BackupDir + '\OWNER', 'TigerVideoEditApplicationUpdate-{#AppVersion}', False) then Exit;
  for I := 0 to GetArrayLength(PayloadPaths) - 1 do begin
    Target := BackupDir + '\' + PayloadPaths[I];
    if not ForceDirectories(ExtractFileDir(Target)) then Exit;
    if not FileCopy(Destination + '\' + PayloadPaths[I], Target, False) then Exit;
  end;
  if not SaveStringToFile(BackupDir + '\READY', 'ready', False) then Exit;
  BackupReady := True;
  Result := True;
end;

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

function CompatibleRuntime(const Root: String): Boolean;
begin
  Result := False;
  try
    Result := (Lowercase(GetSHA256OfFile(Root + '\flutter_windows.dll')) = '{#EngineSHA256}') and
      (Lowercase(GetSHA256OfFile(Root + '\libmpv-2.dll')) = '04e4d27dc385dc18ddd93fbe69c75e635b864f3c6ec53a9122df54c2f7842f4a');
  except
    Result := False;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var Root, Version: String; I: Integer;
begin
  Root := ExpandConstant('{app}');
  Destination := Root;
  BackupDir := Root + '\.tve-update-backup-{#AppVersion}';
  Result := 'Не найдена совместимая установленная версия Tiger Video Edit. Обновление не началось.';
  if not CompatibleRuntime(Root) then Exit;
  Result := 'Не удалось восстановить предыдущую попытку обновления. Закрой редактор и повтори. Резервные файлы сохранены: ' + BackupDir;
  if DirExists(BackupDir) then begin
    if not BackupOwned then Exit;
    if FileExists(BackupDir + '\READY') then begin
      if not GetVersionNumbersString(BackupDir + '\tiger_video_edit.exe', Version) then Exit;
      if (Version <> '3.0.0.3004') and (Version <> '3.0.0.3005') and
         (Version <> '{#AppVersion}.{#AppBuild}') then Exit;
      for I := 0 to GetArrayLength(PayloadPaths) - 1 do
        if FileExists(Root + '\' + PayloadPaths[I]) and not IsUnlocked(Root + '\' + PayloadPaths[I]) then Exit;
      if not RestoreBackup then Exit;
    end else ClearOwnedBackup;
    if DirExists(BackupDir) then Exit;
  end;
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
  Result := 'Сохрани проект и полностью закрой Tiger Video Edit, затем повтори установку обновления. Автоматически закрывать редактор установщик не будет.';
  for I := 0 to GetArrayLength(PayloadPaths) - 1 do
    if not IsUnlocked(Root + '\' + PayloadPaths[I]) then Exit;
  Result := 'Не удалось создать резервную копию файлов приложения. Обновление не началось.';
  if not SaveBackup then Exit;
  Result := '';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var Key, InstalledLocation: String;
begin
  if CurStep <> ssPostInstall then Exit;
  if IsRollbackTest then RaiseException('Isolated rollback test');
  if (Lowercase(GetSHA256OfFile(Destination + '\tiger_video_edit.exe')) <> '{#RunnerSHA256}') or
     (Lowercase(GetSHA256OfFile(Destination + '\data\app.so')) <> '{#AotSHA256}') then
    RaiseException('Проверка установленных файлов не пройдена. Будет восстановлена предыдущая версия.');
  Completed := True;
  ClearOwnedBackup;
  BackupReady := False;
  if ExpandConstant('{param:TVEISOLATED|0}') <> '1' then begin
    Key := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{F532F8DE-68FC-47B4-86C0-B22BDA909622}_is1';
    if RegQueryStringValue(HKCU, Key, 'InstallLocation', InstalledLocation) and
       (CompareText(RemoveBackslashUnlessRoot(InstalledLocation), RemoveBackslashUnlessRoot(Destination)) = 0) then
      RegWriteStringValue(HKCU, Key, 'DisplayVersion', '{#AppVersion}');
  end;
end;

procedure DeinitializeSetup;
begin
  if BackupReady and not Completed then begin
    if RestoreBackup then Log('Previous application files restored after an incomplete update')
    else Log('Automatic restoration could not finish; backup retained at ' + BackupDir);
  end;
end;
