param([Parameter(Mandatory=$true)][string]$BaseDirectory,
      [Parameter(Mandatory=$true)][string]$Installer)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskArea=Join-Path $taskRoot ('.tools/windows-update-acceptance-'+[guid]::NewGuid().ToString('N'))
$taskApp=Join-Path $taskArea 'app'
$taskEmpty=Join-Path $taskArea 'empty'
New-Item -ItemType Directory -Path $taskArea,$taskEmpty | Out-Null
Copy-Item -LiteralPath $BaseDirectory -Destination $taskApp -Recurse
$taskMarker=Join-Path $taskApp 'user-projects/sentinel.tve'
New-Item -ItemType Directory -Path (Split-Path $taskMarker) | Out-Null
[IO.File]::WriteAllText($taskMarker,'KEEP USER PROJECT')
$taskInstaller=[IO.Path]::GetFullPath($Installer)
function Get-UpdateSnapshot([string]$Path){
  $taskMap=@{}
  Get-ChildItem -LiteralPath $Path -Recurse -File | ForEach-Object {
    $taskName=$_.FullName.Substring($Path.Length+1).Replace('\','/')
    $taskMap[$taskName]=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()
  }
  return $taskMap
}
function Invoke-UpdateTest([string]$Target,[string]$Name){
  $taskLog=Join-Path $taskArea "$Name.log"
  $taskArgs=@('/VERYSILENT','/SUPPRESSMSGBOXES','/SP-','/NORESTART','/TVEISOLATED=1',"/DIR=`"$Target`"","/LOG=`"$taskLog`"")
  if($Name -eq 'forced-copy-failure'){$taskArgs+='/TVEFAILTEST=1'}
  $taskProcess=Start-Process -FilePath $taskInstaller -ArgumentList $taskArgs -WindowStyle Hidden -Wait -PassThru
  return $taskProcess.ExitCode
}
function Assert-SameSnapshot($Before,$After){
  if($Before.Count -ne $After.Count){throw 'Refused update changed the file set'}
  foreach($taskKey in $Before.Keys){if($After[$taskKey] -ne $Before[$taskKey]){throw "Refused update changed $taskKey"}}
}
if((Invoke-UpdateTest $taskEmpty 'missing-base') -eq 0){throw 'Missing base was accepted'}
if((Get-ChildItem -LiteralPath $taskEmpty -Recurse -File).Count -ne 0){throw 'Missing-base test copied application files'}
$taskBefore=Get-UpdateSnapshot $taskApp
$taskLock=[IO.File]::Open((Join-Path $taskApp 'data/app.so'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
try {
  if((Invoke-UpdateTest $taskApp 'locked-app') -eq 0){throw 'Locked application was accepted'}
} finally {$taskLock.Dispose()}
Assert-SameSnapshot $taskBefore (Get-UpdateSnapshot $taskApp)
$taskLock=[IO.File]::Open((Join-Path $taskApp 'data/icudtl.dat'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
try {
  if((Invoke-UpdateTest $taskApp 'locked-later-asset') -eq 0){throw 'Locked later asset was accepted'}
} finally {$taskLock.Dispose()}
Assert-SameSnapshot $taskBefore (Get-UpdateSnapshot $taskApp)
$taskEngine=Join-Path $taskApp 'flutter_windows.dll'
$taskEngineBytes=[IO.File]::ReadAllBytes($taskEngine)
try {
  [IO.File]::WriteAllBytes($taskEngine,[byte[]]@(0))
  $taskBad=Get-UpdateSnapshot $taskApp
  if((Invoke-UpdateTest $taskApp 'wrong-engine') -eq 0){throw 'Incompatible engine was accepted'}
  Assert-SameSnapshot $taskBad (Get-UpdateSnapshot $taskApp)
} finally {[IO.File]::WriteAllBytes($taskEngine,$taskEngineBytes)}
if((Invoke-UpdateTest $taskApp 'forced-copy-failure') -eq 0){throw 'Isolated copy-failure test did not abort'}
Assert-SameSnapshot $taskBefore (Get-UpdateSnapshot $taskApp)
if((Invoke-UpdateTest $taskApp 'valid-base') -ne 0){throw 'Valid update failed'}
$taskAfter=Get-UpdateSnapshot $taskApp
$taskManifest=Get-Content (Join-Path (Split-Path $taskInstaller) 'payload-manifest.json') -Raw | ConvertFrom-Json
foreach($taskProperty in $taskManifest.PSObject.Properties){
  if($taskAfter[$taskProperty.Name] -ne $taskProperty.Value.sha256){throw "Updated payload mismatch: $($taskProperty.Name)"}
}
foreach($taskKey in $taskBefore.Keys){
  if(!$taskManifest.PSObject.Properties[$taskKey] -and $taskBefore[$taskKey] -ne $taskAfter[$taskKey]){throw "Runtime/user file changed: $taskKey"}
}
$taskVersion=(Get-Item -LiteralPath (Join-Path $taskApp 'tiger_video_edit.exe')).VersionInfo.FileVersion
if($taskVersion -ne '3.0.1+3006'){throw "Unexpected application version: $taskVersion"}
[ordered]@{result='PASS';missingBase='refused';lockedApplication='refused unchanged';lockedLaterAsset='refused unchanged';wrongEngine='refused unchanged';copyFailure='rolled back unchanged';validBase='updated';version=$taskVersion;runtimesAndUserFiles='unchanged';isolatedDirectory=$taskArea} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $taskArea 'RESULT.json') -Encoding utf8
Get-Content (Join-Path $taskArea 'RESULT.json')
