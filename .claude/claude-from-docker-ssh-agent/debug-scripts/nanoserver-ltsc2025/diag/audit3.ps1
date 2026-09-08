Write-Output "===SC_SDSHOW_SCMANAGER==="
& sc.exe sdshow scmanager 2>&1 | ForEach-Object { Write-Output $_ }
Write-Output "===SC_SDSHOW_SSHD==="
& sc.exe sdshow sshd 2>&1 | ForEach-Object { Write-Output $_ }
Write-Output "===SC_QSIDTYPE_SSHD==="
& sc.exe qsidtype sshd 2>&1 | ForEach-Object { Write-Output $_ }
Write-Output "===SSHD_ACCT_LSA_PRIVS==="
$reg = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
Write-Output ("secedit present: {0}" -f [bool](Get-Command secedit.exe -ErrorAction SilentlyContinue))
Write-Output ("ntrights present: {0}" -f [bool](Get-Command ntrights.exe -ErrorAction SilentlyContinue))
Write-Output "===SSHD_PARAMS==="
if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\sshd') {
  $s = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\sshd'
  foreach ($p in ($s.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })) { Write-Output ("{0} = {1}" -f $p.Name, ($p.Value -join ',')) }
} else { Write-Output "NO_SSHD_KEY" }
Write-Output "===OS==="
Write-Output ((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID)
Write-Output ((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ProductName)
Write-Output ((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR)
Write-Output "===END3==="
