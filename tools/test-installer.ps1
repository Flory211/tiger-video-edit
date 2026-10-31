$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskInstaller=Join-Path $taskRoot 'dist\TigerVideoEdit-2.0.0-Windows-x64-Setup.exe'
$taskInstallDir=Join-Path $taskRoot '.tools\install-check'
$taskExpected=[IO.Path]::GetFullPath($taskInstallDir)
if(!$taskExpected.StartsWith([IO.Path]::GetFullPath($taskRoot)+[IO.Path]::DirectorySeparatorChar)){throw 'Test destination outside workspace'}
$taskExistingKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{F532F8DE-68FC-47B4-86C0-B22BDA909622}_is1'
if(Test-Path -LiteralPath $taskExistingKey){
  $taskExisting=(Get-ItemProperty -LiteralPath $taskExistingKey).InstallLocation
  if([IO.Path]::GetFullPath($taskExisting).TrimEnd('\') -ne $taskExpected.TrimEnd('\')){throw 'Existing user installation detected; installer smoke test must not replace it'}
}
if(Test-Path -LiteralPath 'HKCU:\Software\Classes\.tve'){throw 'Existing .tve association detected; smoke test must not replace it'}
$taskInstall=Start-Process -FilePath $taskInstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/DIR=$taskInstallDir",'/GROUP="Tiger Video Edit Test"',"/LOG=$taskRoot\.tools\install-test.log") -WindowStyle Hidden -Wait -PassThru
if($taskInstall.ExitCode -ne 0){throw "Installer exit $($taskInstall.ExitCode)"}
if((Get-Item -LiteralPath 'HKCU:\Software\Classes\.tve').GetValue('') -ne 'TigerVideoEdit.Project'){throw 'TVE association missing'}
$taskExe=Join-Path $taskInstallDir 'tiger_video_edit.exe'
foreach($taskFile in @($taskExe,(Join-Path $taskInstallDir 'libmpv-2.dll'),(Join-Path $taskInstallDir 'msvcp140.dll'),(Join-Path $taskInstallDir 'tools\ffmpeg.exe'),(Join-Path $taskInstallDir 'tools\ffprobe.exe'))){if(!(Test-Path -LiteralPath $taskFile)){throw "Missing runtime: $taskFile"}}
& (Join-Path $taskInstallDir 'tools\ffmpeg.exe') -v error -f lavfi -i 'sine=frequency=440:duration=0.1' -f null -
if($LASTEXITCODE -ne 0){throw 'Installed FFmpeg runtime failed'}
$taskApp=Start-Process -FilePath $taskExe -WorkingDirectory $taskInstallDir -PassThru
Start-Sleep -Seconds 5
$taskApp.Refresh()
if($taskApp.HasExited){throw "Installed app exited: $($taskApp.ExitCode)"}
Write-Output "Installed app running: PID $($taskApp.Id)"
$taskClosed=$taskApp.CloseMainWindow()
if($taskClosed){$taskApp.WaitForExit(10000) | Out-Null}
$taskApp.Refresh()
if(!$taskApp.HasExited){Stop-Process -Id $taskApp.Id}
$taskUninstaller=Join-Path $taskInstallDir 'unins000.exe'
$taskUninstall=Start-Process -FilePath $taskUninstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -WindowStyle Hidden -Wait -PassThru
if($taskUninstall.ExitCode -ne 0){throw "Uninstaller exit $($taskUninstall.ExitCode)"}
if(Test-Path -LiteralPath $taskExe){throw 'Uninstaller left executable'}
Write-Output 'INSTALL / LAUNCH / BUNDLED FFMPEG / UNINSTALL: PASS'




