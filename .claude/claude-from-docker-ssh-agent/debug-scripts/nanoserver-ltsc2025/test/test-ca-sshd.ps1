# THE REAL FIX:
# - sshd runs as ContainerAdministrator (not LocalSystem)
# - LSAAuthenticationPackage = "msv1_0"
# Flow: am_system()=FALSE → get_sid("jenkins")=NULL → escape hatch → process token!

Write-Host "=== Stop all sshd ==="
Stop-Process -Name sshd -Force -ErrorAction SilentlyContinue
Stop-Service sshd -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
Start-Sleep -Seconds 2

Write-Host "=== Verify LSAAuthenticationPackage ==="
Set-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name 'LSAAuthenticationPackage' -Value 'msv1_0' -Type String
Get-ItemProperty 'HKLM:\SOFTWARE\OpenSSH' | Select-Object LSAAuthenticationPackage, DefaultShell

Write-Host "`n=== Run sshd AS CONTAINERADMINISTRATOR (not service) ==="
# This process will run as ContainerAdministrator since that's who docker exec runs as
# No LocalSystem - so am_system() = FALSE!
$sshdProc = Start-Process -FilePath 'C:\Program Files\OpenSSH-Win64\sshd.exe' `
    -ArgumentList '-f C:\ProgramData\ssh\sshd_config -E C:\sshd-ca.log' `
    -NoNewWindow -PassThru
Start-Sleep -Seconds 3
Write-Host "sshd PID: $($sshdProc.Id)"
netstat -an 2>&1 | findstr ':22 '

Write-Host "`n=== Write key, test SSH ==="
$b64Key = "LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNCUDR0KzA2aVZqRDM2bzdjczBiQngveXFIQVBJN2UyOCtJdUp3clU1VTBHQUFBQUpqUkZ3WXIwUmNHCkt3QUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQlA0dCswNmlWakQzNm83Y3MwYkJ4L3lxSEFQSTdlMjgrSXVKd3JVNVUwR0EKQUFBRUFwUEJ1bUE4WWhsYlhWSGMxek1IN2RlZy9aWUtlaDFJcmE1QlFodG1LcU9VL2kzN1RxSldNUGZxanR5elJzSEgvSwpvY0E4anQ3Yno0aTRuQ3RUbFRRWUFBQUFFR3BsYm10cGJuTXRkR1Z6ZEMxclpYa0JBZ01FQlE9PQotLS0tLUVORCBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0K"
$keyFile = 'C:\test_jenkins_key'
[System.IO.File]::WriteAllBytes($keyFile, [System.Convert]::FromBase64String($b64Key))
icacls $keyFile /inheritance:r /grant:r "NT AUTHORITY\SYSTEM:(F)" /grant:r "ContainerAdministrator:(R)" 2>&1 | Out-Null

$sshBin = 'C:\Program Files\OpenSSH-Win64\ssh.exe'
$proc = Start-Process -FilePath $sshBin `
    -ArgumentList "-4 -v -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -i `"$keyFile`" -l jenkins 127.0.0.1 -p 22 `"echo CA_SSHD_ESCAPE_HATCH_TEST`"" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput 'C:\ca-ssh-out.txt' -RedirectStandardError 'C:\ca-ssh-err.txt'
$proc | Wait-Process -Timeout 25 -ErrorAction SilentlyContinue
if (-not $proc.HasExited) { $proc.Kill(); Write-Host "TIMED OUT" } else { Write-Host "Exit: $($proc.ExitCode)" }
Write-Host "STDOUT: $(Get-Content 'C:\ca-ssh-out.txt' -ErrorAction SilentlyContinue)"
Write-Host "`nSTDERR (last 12):"
Get-Content 'C:\ca-ssh-err.txt' -ErrorAction SilentlyContinue | Select-Object -Last 12

Write-Host "`n=== sshd log (critical lines) ==="
Start-Sleep -Seconds 1
Get-Content 'C:\sshd-ca.log' -ErrorAction SilentlyContinue | Where-Object {
    $_ -match 'token|system|lsa|process|custom|auth|fail|error|fork|child'
} | Select-Object -Last 20

if (-not $sshdProc.HasExited) { $sshdProc.Kill() }
Remove-Item $keyFile -ErrorAction SilentlyContinue
