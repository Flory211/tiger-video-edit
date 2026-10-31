param([string]$FfmpegBin='C:\ffmpeg-master-latest-win64-gpl-shared\bin')
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskFlutter=Join-Path $taskRoot '.tools\flutter\bin\flutter.bat'
& $taskFlutter test
if($LASTEXITCODE -ne 0){throw 'Tests failed'}
& $taskFlutter analyze
if($LASTEXITCODE -ne 0){throw 'Analysis failed'}
& $taskFlutter build windows --release
if($LASTEXITCODE -ne 0){throw 'Windows build failed'}
$taskRelease=Join-Path $taskRoot 'build\windows\x64\runner\Release'
$taskTools=Join-Path $taskRelease 'tools'
New-Item -ItemType Directory -Force $taskTools | Out-Null
Get-ChildItem -LiteralPath $FfmpegBin -File | Where-Object { $_.Extension -eq '.dll' -or $_.Name -in @('ffmpeg.exe','ffprobe.exe') } | Copy-Item -Destination $taskTools
# Bundle the compiler runtime app-locally: no separate VC runtime installation.
$taskVs=& 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe' -latest -property installationPath
$taskCrt=Get-ChildItem -LiteralPath (Join-Path $taskVs 'VC\Redist\MSVC') -Directory | Where-Object Name -Match '^14\.' | Sort-Object Name -Descending | Select-Object -First 1
Get-ChildItem -LiteralPath (Join-Path $taskCrt.FullName 'x64\Microsoft.VC143.CRT') -Filter '*.dll' | Copy-Item -Destination $taskRelease
& (Join-Path $taskRoot '.tools\inno\ISCC.exe') (Join-Path $taskRoot 'installer\windows.iss')
if($LASTEXITCODE -ne 0){throw 'Installer compilation failed'}


