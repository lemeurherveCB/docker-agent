$dlls = @('netlogon.dll','logoncli.dll','lsasrv.dll','msv1_0.dll','samlib.dll','samsrv.dll','secur32.dll','ntlmshared.dll','netapi32.dll','wkscli.dll','kerberos.dll','credssp.dll','tspkg.dll','pku2u.dll','wdigest.dll','cryptdll.dll','advapi32.dll')
Write-Output "===DLLS==="
foreach ($d in $dlls) {
  $p = Join-Path $env:SystemRoot ('System32\' + $d)
  if (Test-Path $p) {
    $f = Get-Item $p
    $v = ''
    try { $v = $f.VersionInfo.FileVersion } catch {}
    Write-Output ("{0}|{1}|{2}" -f $d, $f.Length, $v)
  } else {
    Write-Output ("{0}|MISSING|" -f $d)
  }
}
Write-Output "===LSA_KEY==="
try {
  $lsa = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -ErrorAction Stop
  foreach ($n in ($lsa.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })) {
    Write-Output ("{0} = {1}" -f $n.Name, ($n.Value -join ','))
  }
} catch { Write-Output "LSA_KEY_ERROR: $_" }
Write-Output "===NETLOGON_SVC_KEY==="
if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon') {
  Write-Output "EXISTS"
  $n = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon'
  foreach ($p in ($n.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })) { Write-Output ("{0} = {1}" -f $p.Name, ($p.Value -join ',')) }
} else { Write-Output "NOT_EXISTS" }
Write-Output "===SAMSS_SVC_KEY==="
if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\SamSs') {
  Write-Output "EXISTS"
  $n = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\SamSs'
  foreach ($p in ($n.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })) { Write-Output ("{0} = {1}" -f $p.Name, ($p.Value -join ',')) }
} else { Write-Output "NOT_EXISTS" }
Write-Output "===SERVICES==="
try { Get-Service | Where-Object { $_.Name -match 'Netlogon|SamSs|sshd|LanmanWorkstation|KeyIso' } | ForEach-Object { Write-Output ("{0}|{1}|{2}" -f $_.Name, $_.Status, $_.StartType) } } catch { Write-Output "GETSERVICE_ERROR: $_" }
Write-Output "===SC_QUERY_SCMANAGER==="
& sc.exe query scmanager 2>&1 | ForEach-Object { Write-Output $_ }
Write-Output "===SC_QC_SSHD==="
& sc.exe qc sshd 2>&1 | ForEach-Object { Write-Output $_ }
Write-Output "===SC_QPRIVS_SSHD==="
& sc.exe qprivs sshd 2>&1 | ForEach-Object { Write-Output $_ }
Write-Output "===SC_QUERY_NETLOGON==="
& sc.exe query Netlogon 2>&1 | ForEach-Object { Write-Output $_ }
Write-Output "===SC_QUERY_SAMSS==="
& sc.exe query SamSs 2>&1 | ForEach-Object { Write-Output $_ }
Write-Output "===WHOAMI_PRIV==="
& whoami.exe /priv 2>&1 | ForEach-Object { Write-Output $_ }
Write-Output "===WHOAMI_USER==="
& whoami.exe /user 2>&1 | ForEach-Object { Write-Output $_ }
Write-Output "===SECURITY_PROVIDERS==="
try { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders' -ErrorAction Stop).SecurityProviders } catch { Write-Output "ERR: $_" }
Write-Output "===SSP_SUBKEYS==="
try { Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders' -ErrorAction Stop | ForEach-Object { Write-Output $_.PSChildName } } catch { Write-Output "ERR: $_" }
Write-Output "===END==="
