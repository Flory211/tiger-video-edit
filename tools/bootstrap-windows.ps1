$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskUrl='https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20261021/mpv-dev-x86_64-20261021-git-e471496c56.7z'
$taskArchive=Join-Path $taskRoot '.tools\libmpv.7z'
New-Item -ItemType Directory -Force (Join-Path $taskRoot '.tools'),(Join-Path $taskRoot 'third_party\mpv') | Out-Null
if(!(Test-Path -LiteralPath $taskArchive)){Invoke-WebRequest $taskUrl -OutFile $taskArchive}
if((Get-FileHash -LiteralPath $taskArchive -Algorithm SHA256).Hash.ToLower() -ne 'efc719eff3dc5954b4a5efc800632808bcec01cc9034940dd14e5eb7fe9ea633'){throw 'libmpv SHA256 mismatch'}
# Extract with 7-Zip, or WinRAR if installed. Windows tar lacks the required LZMA codec.
$taskSevenZip='C:\Program Files\7-Zip\7z.exe'
$taskTarget=Join-Path $taskRoot 'third_party\mpv'
if(Test-Path -LiteralPath $taskSevenZip){& $taskSevenZip x -y "-o$taskTarget" $taskArchive; if($LASTEXITCODE){throw 'libmpv extraction failed'}}
elseif(Test-Path -LiteralPath 'C:\Program Files\WinRAR\WinRAR.exe') {
  $taskExtract=Start-Process -FilePath 'C:\Program Files\WinRAR\WinRAR.exe' -ArgumentList @('x','-ibck','-y',"`"$taskArchive`"","`"$taskTarget\`"") -WindowStyle Hidden -Wait -PassThru
  if($taskExtract.ExitCode){throw 'libmpv extraction failed'}
} else {throw 'Install 7-Zip to extract the pinned runtime'}
if(!(Test-Path -LiteralPath (Join-Path $taskTarget 'libmpv-2.dll'))){throw 'libmpv extraction failed'}

