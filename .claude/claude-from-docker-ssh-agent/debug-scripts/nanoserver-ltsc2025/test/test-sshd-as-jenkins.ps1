# PATH 2 FIX: run sshd service AS jenkins user
# am_system()=FALSE, process_sid=jenkins, user_sid=jenkins → EqualSid=TRUE → process token returned
# Shell session runs as jenkins!

Write-Host "=== Current user ==="
whoami.exe

Write-Host "`n=== Stop all sshd ==="
Stop-Process -Name sshd -Force -ErrorAction SilentlyContinue
Stop-Service sshd -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
Start-Sleep -Seconds 2

Write-Host "`n=== jenkins user info ==="
net user jenkins 2>&1 | Select-String 'Active|Administrators|Password'

Write-Host "`n=== Set sshd service to run as jenkins ==="
sc.exe config sshd obj= ".\jenkins" password= "" 2>&1
Start-Sleep -Seconds 1

Write-Host "`n=== Verify service config ==="
sc.exe qc sshd 2>&1 | Where-Object { $_ -match 'SERVICE_START|ACCOUNT|BINARY' }

Write-Host "`n=== Ensure LSAAuthenticationPackage set (needed only as backup) ==="
Set-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name 'LSAAuthenticationPackage' -Value 'msv1_0' -Type String

Write-Host "`n=== Start sshd as jenkins service ==="
Start-Service sshd 2>&1
Start-Sleep -Seconds 3
if (Get-Process sshd -ErrorAction SilentlyContinue) {
    Write-Host "sshd running: PID $(( Get-Process sshd).Id)"
} else {
    Write-Host "ERROR: sshd not running"
    sc.exe start sshd 2>&1
    Start-Sleep -Seconds 2
    Get-Process sshd -ErrorAction SilentlyContinue
}

Write-Host "`n=== Test SSH as jenkins ==="
$b64Key = "LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNCUDR0KzA2aVZqRDM2bzdjczBiQngveXFIQVBJN2UyOCtJdUp3clU1VTBHQUFBQUpqUkZ3WXIwUmNHCkt3QUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQlA0dCswNmlWakQzNm83Y3MwYkJ4L3lxSEFQSTdlMjgrSXVKd3JVNVUwR0EKQUFBRUFwUEJ1bUE4WWhsYlhWSGMxek1IN2RlZy9aWUtlaDFJcmE1QlFodG1LcU9VL2kzN1RxSldNUGZxanR5elJzSEgvSwpvY0E4anQ3Yno0aTRuQ3RUbFRRWUFBQUFFR3BsYm10cGJuTXRkR1Z6ZEMxclpYa0JBZ01FQlE9PQotLS0tLUVORCBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0K"
$keyFile = 'C:\test_jenkins_key'
[System.IO.File]::WriteAllBytes($keyFile, [System.Convert]::FromBase64String($b64Key))
icacls $keyFile /inheritance:r /grant:r "NT AUTHORITY\SYSTEM:(F)" /grant:r "ContainerAdministrator:(R)" 2>&1 | Out-Null

$sshBin = 'C:\Program Files\OpenSSH-Win64\ssh.exe'
$proc = Start-Process -FilePath $sshBin `
    -ArgumentList "-4 -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -i `"$keyFile`" -l jenkins 127.0.0.1 whoami" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput 'C:\jenkins-ssh-out.txt' `
    -RedirectStandardError 'C:\jenkins-ssh-err.txt'
$proc | Wait-Process -Timeout 25 -ErrorAction SilentlyContinue
if (-not $proc.HasExited) { $proc.Kill(); Write-Host "TIMED OUT" } else { Write-Host "SSH exit: $($proc.ExitCode)" }

$stdout = Get-Content 'C:\jenkins-ssh-out.txt' -ErrorAction SilentlyContinue
$stderr = Get-Content 'C:\jenkins-ssh-err.txt' -ErrorAction SilentlyContinue
Write-Host "STDOUT (whoami result): $stdout"
if ($proc.ExitCode -ne 0) {
    Write-Host "`nSTDERR (last 15):"
    $stderr | Select-Object -Last 15
}

Write-Host "`n=== sshd log (key lines) ==="
Get-Content 'C:\ProgramData\ssh\logs\sshd.log' -ErrorAction SilentlyContinue | Where-Object {
    $_ -match 'token|system|equal|process|custom|auth|fail|error|fork|Accepted|session'
} | Select-Object -Last 20

Stop-Service sshd -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
Remove-Item $keyFile -ErrorAction SilentlyContinue
Write-Host "`nDONE"
