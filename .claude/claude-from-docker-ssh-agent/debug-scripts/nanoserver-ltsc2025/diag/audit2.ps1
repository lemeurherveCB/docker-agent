$dlls = @('netlogon.dll','logoncli.dll','lsasrv.dll','msv1_0.dll','samlib.dll','samsrv.dll','secur32.dll','ntlmshared.dll','netapi32.dll','wkscli.dll','kerberos.dll','credssp.dll','tspkg.dll','pku2u.dll','wdigest.dll','cryptdll.dll','advapi32.dll','sechost.dll','lsass.exe','samcli.dll','schannel.dll','ncrypt.dll','bcrypt.dll')
Write-Output "===DLL_DETAIL==="
foreach ($d in $dlls) {
  $p = Join-Path $env:SystemRoot ('System32\' + $d)
  $i = Get-Item $p -ErrorAction SilentlyContinue
  if ($i) {
    $h = (Get-FileHash $p -Algorithm SHA256).Hash.Substring(0,16)
    Write-Output ("{0}|{1}|{2}|{3}|{4}" -f $d, $i.Length, $i.VersionInfo.FileVersion, $i.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ss'), $h)
  } else {
    Write-Output ("{0}|MISSING|||" -f $d)
  }
}
Write-Output "===ADVAPI_SEARCH==="
Get-ChildItem -Path $env:SystemRoot -Recurse -Filter 'advapi32.dll' -ErrorAction SilentlyContinue | ForEach-Object { Write-Output ("{0}|{1}" -f $_.FullName, $_.Length) }
Write-Output "===APISET_ADVAPI==="
Get-ChildItem (Join-Path $env:SystemRoot 'System32') -Filter 'api-ms-win-*advapi*' -ErrorAction SilentlyContinue | ForEach-Object { Write-Output $_.Name }
Write-Output "===LSA_SUBKEYS==="
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -ErrorAction SilentlyContinue | ForEach-Object { Write-Output $_.PSChildName }
Write-Output "===END2==="
