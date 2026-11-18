param([string]$FfmpegBin=$env:FFMPEG_BIN, [string]$InnoIscc=$env:INNO_ISCC, [switch]$SkipChecks, [switch]$Offline, [string]$DartDefineFile, [string]$InstallerOutputDirectory='dist')
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $taskRoot
$taskFlutter=if($env:FLUTTER_ROOT){Join-Path $env:FLUTTER_ROOT 'bin/flutter.bat'} elseif(Get-Command flutter -ErrorAction SilentlyContinue){(Get-Command flutter).Source} else {Join-Path $taskRoot '.tools/flutter/bin/flutter.bat'}
if(!$FfmpegBin){$taskCommand=Get-Command ffmpeg -ErrorAction SilentlyContinue; if($taskCommand){$FfmpegBin=Split-Path $taskCommand.Source} elseif(Test-Path 'C:/ffmpeg-master-latest-win64-gpl-shared/bin'){$FfmpegBin='C:/ffmpeg-master-latest-win64-gpl-shared/bin'} else {throw 'Set FFMPEG_BIN or run bootstrap-ci-windows.ps1'}}
if(!$InnoIscc){$InnoIscc=Join-Path $taskRoot '.tools/inno/ISCC.exe'; if(!(Test-Path $InnoIscc)){$InnoIscc='C:/Program Files (x86)/Inno Setup 6/ISCC.exe'}}
if($Offline){& $taskFlutter pub get --offline}else{& $taskFlutter pub get}
if($LASTEXITCODE){throw 'Dependency resolution failed'}
if(!$SkipChecks){
& $taskFlutter test
if($LASTEXITCODE -ne 0){throw 'Tests failed'}
& $taskFlutter analyze
if($LASTEXITCODE -ne 0){throw 'Analysis failed'}
}
$taskBuildArguments=@('build','windows','--release','--no-pub')
if($DartDefineFile){$taskBuildArguments+="--dart-define-from-file=$DartDefineFile"}
& $taskFlutter @taskBuildArguments
if($LASTEXITCODE -ne 0){throw 'Windows build failed'}
$taskRelease=Join-Path $taskRoot 'build\windows\x64\runner\Release'
$taskTools=Join-Path $taskRelease 'tools'
New-Item -ItemType Directory -Force $taskTools | Out-Null
Get-ChildItem -LiteralPath $FfmpegBin -File | Where-Object { $_.Extension -eq '.dll' -or $_.Name -in @('ffmpeg.exe','ffprobe.exe') } | Copy-Item -Destination $taskTools
# Bundle the compiler runtime app-locally: no separate VC runtime installation.
$taskVs=& 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe' -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$taskCrt=Get-ChildItem -LiteralPath (Join-Path $taskVs 'VC\Redist\MSVC') -Directory | Where-Object Name -Match '^14\.' | Sort-Object Name -Descending | Select-Object -First 1
$taskCrtDir=Get-ChildItem -LiteralPath (Join-Path $taskCrt.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' | Select-Object -First 1
if(!$taskCrtDir){throw 'Visual C++ redistributable payload missing'}
Get-ChildItem -LiteralPath $taskCrtDir.FullName -Filter '*.dll' | Copy-Item -Destination $taskRelease
$taskNotices=Join-Path $taskRelease 'third-party-notices'
New-Item -ItemType Directory -Force $taskNotices | Out-Null
Copy-Item -LiteralPath 'docs/THIRD_PARTY.md','LICENSE' -Destination $taskNotices
Get-ChildItem -LiteralPath (Split-Path -Parent $FfmpegBin) -File | Where-Object Name -Match 'license|copying|readme' | Copy-Item -Destination $taskNotices
& (Join-Path $PSScriptRoot 'verify-windows-payload.ps1') -Directory $taskRelease
$taskVersion=(Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version: (\d+\.\d+\.\d+)').Matches.Groups[1].Value
if(!$taskVersion){throw 'Missing semantic app version'}
$taskInstallerOutput=[IO.Path]::GetFullPath((Join-Path $taskRoot $InstallerOutputDirectory))
New-Item -ItemType Directory -Force -Path $taskInstallerOutput | Out-Null
& $InnoIscc "/DAppVersion=$taskVersion" "/O$taskInstallerOutput" (Join-Path $taskRoot 'installer/windows.iss')
if($LASTEXITCODE -ne 0){throw 'Installer compilation failed'}
if(!(Test-Path -LiteralPath (Join-Path $taskInstallerOutput "TigerVideoEdit-$taskVersion-Windows-x64-Setup.exe"))){throw 'Installer output missing'}


