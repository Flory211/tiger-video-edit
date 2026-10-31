param([Parameter(Mandatory)][string]$Directory)
$ErrorActionPreference='Stop'
foreach($taskName in @('tiger_video_edit.exe','flutter_windows.dll','libmpv-2.dll','msvcp140.dll','vcruntime140.dll','data/icudtl.dat','data/app.so','tools/ffmpeg.exe','tools/ffprobe.exe')){
  $taskFile=Join-Path $Directory $taskName
  if(!(Test-Path -LiteralPath $taskFile -PathType Leaf) -or (Get-Item -LiteralPath $taskFile).Length -eq 0){throw "Missing runtime payload: $taskName"}
}
foreach($taskPattern in @('avcodec-*.dll','avformat-*.dll','avutil-*.dll','swresample-*.dll','swscale-*.dll')){
  if(!(Get-ChildItem -LiteralPath (Join-Path $Directory 'tools') -Filter $taskPattern)){throw "Missing FFmpeg shared dependency: $taskPattern"}
}
if(!(Test-Path (Join-Path $Directory 'data/flutter_assets'))){throw 'Flutter assets missing'}
& (Join-Path $Directory 'tools/ffmpeg.exe') -v error -f lavfi -i 'sine=frequency=440:duration=0.1' -f null -
if($LASTEXITCODE){throw 'Bundled FFmpeg smoke test failed'}
& (Join-Path $Directory 'tools/ffprobe.exe') -version | Select-Object -First 1
if($LASTEXITCODE){throw 'Bundled FFprobe failed'}
Write-Output 'Windows runtime payload: PASS'
