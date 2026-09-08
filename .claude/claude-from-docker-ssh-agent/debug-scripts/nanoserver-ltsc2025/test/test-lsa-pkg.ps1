# THE FIX: LSAAuthenticationPackage registry key
# When am_system()=false AND get_sid(user)=NULL AND LSAAuthenticationPackage is set,
# Win32-OpenSSH returns the process token (ContainerAdministrator) directly!

Write-Host "=== Remove old CustomLSAProvider, set LSAAuthenticationPackage ==="
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name 'CustomLSAProvider' -ErrorAction SilentlyContinue
Set-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name 'LSAAuthenticationPackage' -Value 'msv1_0' -Type String
Get-ItemProperty 'HKLM:\SOFTWARE\OpenSSH'

Write-Host "`n=== Restart sshd with new config ==="
Stop-Process -Name sshd -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
schtasks.exe /create /tn 'sshd-system' /tr '"C:\Program Files\OpenSSH-Win64\sshd.exe" -f C:\ProgramData\ssh\sshd_config' /sc once /st 00:00 /ru SYSTEM /rl HIGHEST /f 2>&1
schtasks.exe /run /tn 'sshd-system' 2>&1
Start-Sleep -Seconds 3
Write-Host "sshd PID: $((Get-Process sshd -ErrorAction SilentlyContinue).Id)"

Write-Host "`n=== Test SSH with LSAAuthenticationPackage set ==="
$b64Key = "LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNCUDR0KzA2aVZqRDM2bzdjczBiQngveXFIQVBJN2UyOCtJdUp3clU1VTBHQUFBQUpqUkZ3WXIwUmNHCkt3QUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQlA0dCswNmlWakQzNm83Y3MwYkJ4L3lxSEFQSTdlMjgrSXVKd3JVNVUwR0EKQUFBRUFwUEJ1bUE4WWhsYlhWSGMxek1IN2RlZy9aWUtlaDFJcmE1QlFodG1LcU9VL2kzN1RxSldNUGZxanR5elJzSEgvSwpvY0E4anQ3Yno0aTRuQ3RUbFRRWUFBQUFFR3BsYm10cGJuTXRkR1Z6ZEMxclpYa0JBZ01FQlE9PQotLS0tLUVORCBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0K"
$keyFile = 'C:\test_jenkins_key'
[System.IO.File]::WriteAllBytes($keyFile, [System.Convert]::FromBase64String($b64Key))
icacls $keyFile /inheritance:r /grant:r "NT AUTHORITY\SYSTEM:(F)" /grant:r "ContainerAdministrator:(R)" 2>&1 | Out-Null

$sshBin = 'C:\Program Files\OpenSSH-Win64\ssh.exe'
$proc = Start-Process -FilePath $sshBin `
    -ArgumentList "-4 -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -i `"$keyFile`" -l jenkins 127.0.0.1 -p 22 `"echo SSH_WORKS_WITH_LSA_PKG`"" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput 'C:\lsa2-out.txt' `
    -RedirectStandardError 'C:\lsa2-err.txt'
$proc | Wait-Process -Timeout 25 -ErrorAction SilentlyContinue
if (-not $proc.HasExited) { $proc.Kill(); Write-Host "TIMED OUT" } else { Write-Host "Exit: $($proc.ExitCode)" }
Write-Host "STDOUT: $(Get-Content 'C:\lsa2-out.txt' -ErrorAction SilentlyContinue)"
Write-Host "STDERR (last 8):"
Get-Content 'C:\lsa2-err.txt' -ErrorAction SilentlyContinue | Select-Object -Last 8

Write-Host "`n=== sshd.log last 20 ==="
Get-Content 'C:\ProgramData\ssh\logs\sshd.log' -Tail 20 -ErrorAction SilentlyContinue

Remove-Item $keyFile -ErrorAction SilentlyContinue
