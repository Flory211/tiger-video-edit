$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'bootstrap-windows.ps1')
$taskArchive=Join-Path $taskRoot '.tools/ffmpeg-9.0.2-shared.7z'
$taskHash='4d2060a8b34a940aa47d785142055bb92a63053781e55f2ace4546edd519a8f5'
if(!(Test-Path -LiteralPath $taskArchive)){Invoke-WebRequest 'https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-9.0.2-full_build-shared.7z' -OutFile $taskArchive}
if((Get-FileHash -LiteralPath $taskArchive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskHash){throw 'FFmpeg SHA256 mismatch'}
$taskSevenZip=if(Get-Command 7z -ErrorAction SilentlyContinue){(Get-Command 7z).Source}else{'C:/Program Files/7-Zip/7z.exe'}
& $taskSevenZip x -y "-o$taskRoot/.tools/ffmpeg" $taskArchive
if($LASTEXITCODE){throw 'FFmpeg extraction failed'}
if($env:GITHUB_ENV){"FFMPEG_BIN=$taskRoot/.tools/ffmpeg/ffmpeg-9.0.2-full_build-shared/bin" | Out-File $env:GITHUB_ENV -Append -Encoding utf8}
if($env:GITHUB_PATH){"$taskRoot/.tools/ffmpeg/ffmpeg-9.0.2-full_build-shared/bin" | Out-File $env:GITHUB_PATH -Append -Encoding utf8}
