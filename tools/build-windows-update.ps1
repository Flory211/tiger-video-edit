param([string]$Python='python', [string]$InnoIscc, [string]$BaseDirectory)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $taskRoot
$taskFlutter=Join-Path $taskRoot '.tools/flutter/bin/flutter.bat'
if(git status --porcelain){throw 'Commit the release source before building the public update'}
$taskSource=git rev-parse HEAD
  # Explicit public defines. Never reuse the private local Jamendo build file.
  $taskOldDefines=$env:DART_DEFINES
  try {
    Remove-Item Env:DART_DEFINES -ErrorAction SilentlyContinue
    & $taskFlutter build windows --release --no-pub --dart-define=TVE_GITHUB_OWNER=Flory211 --dart-define=TVE_GITHUB_REPO=tiger-video-edit
    if($LASTEXITCODE){throw 'Public Windows build failed'}
  } finally {$env:DART_DEFINES=$taskOldDefines}
if((git rev-parse HEAD) -ne $taskSource -or (git status --porcelain)){throw 'Release source changed during the build'}
$taskRelease=Join-Path $taskRoot 'build/windows/x64/runner/Release'
$taskPayload=Join-Path $taskRoot ('.tools/windows-update-payload-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskPayload | Out-Null
Copy-Item -LiteralPath (Join-Path $taskRelease 'tiger_video_edit.exe') -Destination $taskPayload
Copy-Item -LiteralPath (Join-Path $taskRelease 'data') -Destination (Join-Path $taskPayload 'data') -Recurse
$taskVersion=(Select-String -LiteralPath pubspec.yaml -Pattern '^version: (\d+\.\d+\.\d+)\+(\d+)').Matches
if(!$taskVersion){throw 'App version/build not found'}
$taskOutput=Join-Path $taskRoot 'dist/windows-update'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
$taskChecks=@('tools/windows_update_payload.py',$taskPayload,'--manifest',(Join-Path $taskOutput 'payload-manifest.json'),'--private-config','.tools/jamendo-local.json')
if($BaseDirectory){$taskChecks+=@('--base',$BaseDirectory)}
& $Python @taskChecks
if($LASTEXITCODE){throw 'Unsafe update payload'}
$taskEngine=(Get-FileHash -LiteralPath (Join-Path $taskRelease 'flutter_windows.dll')).Hash.ToLowerInvariant()
if(!$InnoIscc){$InnoIscc=Join-Path $taskRoot '.tools/inno/ISCC.exe'}
$taskRunnerHash=(Get-FileHash -LiteralPath (Join-Path $taskPayload 'tiger_video_edit.exe')).Hash.ToLowerInvariant()
$taskAotHash=(Get-FileHash -LiteralPath (Join-Path $taskPayload 'data/app.so')).Hash.ToLowerInvariant()
& $InnoIscc "/DAppVersion=$($taskVersion.Groups[1].Value)" "/DAppBuild=$($taskVersion.Groups[2].Value)" "/DPayloadDir=$taskPayload" "/DEngineSHA256=$taskEngine" "/DRunnerSHA256=$taskRunnerHash" "/DAotSHA256=$taskAotHash" "/O$taskOutput" (Join-Path $taskRoot 'installer/windows-update.iss')
if($LASTEXITCODE){throw 'Update installer compilation failed'}
$taskBuild=[ordered]@{
  version=$taskVersion.Groups[1].Value; build=[int]$taskVersion.Groups[2].Value;
  source=$taskSource; payloadDirectory=$taskPayload;
  kind='windows-application-update'; baseline='3.0.0+3004/3005';
  nativeRuntimes='not included; existing compatible files retained';
  publicDefines=@('TVE_GITHUB_OWNER=Flory211','TVE_GITHUB_REPO=tiger-video-edit');
  engineSHA256=$taskEngine
}
$taskBuild | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $taskOutput 'local-build-info.json') -Encoding utf8
Write-Output 'Public application-only Windows update built; no native runtime was packaged.'
