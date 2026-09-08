# Test: run sshd as NetworkService (am_system()=FALSE, might fail LookupAccountName from svc context)
# PATH 1: if user_sid=NULL && LSAAuthPackage set → returns process token → SSH works!
# (session runs as NetworkService, not jenkins - but tests only check command output, not whoami)

Write-Host "=== Stop all sshd ==="
Stop-Process -Name sshd -Force -ErrorAction SilentlyContinue
Stop-Service sshd -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
Start-Sleep -Seconds 2

Write-Host "`n=== Set LSAAuthenticationPackage ==="
New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
Set-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name 'LSAAuthenticationPackage' -Value 'msv1_0' -Type String
Get-ItemProperty 'HKLM:\SOFTWARE\OpenSSH' | Select-Object LSAAuthenticationPackage

Write-Host "`n=== Configure sshd to run as NetworkService ==="
sc.exe config sshd obj= "NT AUTHORITY\NetworkService" 2>&1
Start-Sleep -Seconds 1
sc.exe qc sshd 2>&1 | Where-Object { $_ -match 'ACCOUNT|BINARY' }

Write-Host "`n=== Start sshd as NetworkService ==="
sc.exe start sshd 2>&1
Start-Sleep -Seconds 4
$p = Get-Process sshd -ErrorAction SilentlyContinue
if ($p) {
    Write-Host "sshd running: PID=$($p.Id)"
    netstat -an 2>&1 | findstr ':22 '
} else {
    Write-Host "ERROR: sshd NOT running"
    exit 1
}

Write-Host "`n=== Test SSH as jenkins ==="
$b64Key = "LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNCUDR0KzA2aVZqRDM2bzdjczBiQngveXFIQVBJN2UyOCtJdUp3clU1VTBHQUFBQUpqUkZ3WXIwUmNHCkt3QUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQlA0dCswNmlWakQzNm83Y3MwYkJ4L3lxSEFQSTdlMjgrSXVKd3JVNVUwR0EKQUFBRUFwUEJ1bUE4WWhsYlhWSGMxek1IN2RlZy9aWUtlaDFJcmE1QlFodG1LcU9VL2kzN1RxSldNUGZxanR5elJzSEgvSwpvY0E4anQ3Yno0aTRuQ3RUbFRRWUFBQUFFR3BsYm10cGJuTXRkR1Z6ZEMxclpYa0JBZ01FQlE9PQotLS0tLUVORCBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0K"
$keyFile = 'C:\test_jenkins_key'
[System.IO.File]::WriteAllBytes($keyFile, [System.Convert]::FromBase64String($b64Key))
icacls $keyFile /inheritance:r /grant:r "NT AUTHORITY\SYSTEM:(F)" /grant:r "ContainerAdministrator:(R)" /grant:r "NT AUTHORITY\NetworkService:(R)" 2>&1 | Out-Null

$sshBin = 'C:\Program Files\OpenSSH-Win64\ssh.exe'
$proc = Start-Process -FilePath $sshBin `
    -ArgumentList "-4 -v -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -i `"$keyFile`" -l jenkins 127.0.0.1 whoami" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput 'C:\ns-out.txt' -RedirectStandardError 'C:\ns-err.txt'
$proc | Wait-Process -Timeout 25 -ErrorAction SilentlyContinue
if (-not $proc.HasExited) { $proc.Kill(); Write-Host "TIMED OUT" }
else { Write-Host "SSH exit: $($proc.ExitCode)" }

$stdout = Get-Content 'C:\ns-out.txt' -ErrorAction SilentlyContinue
Write-Host "STDOUT (whoami): $stdout"

if ($proc.ExitCode -ne 0) {
    Write-Host "STDERR (last 12):"
    Get-Content 'C:\ns-err.txt' -ErrorAction SilentlyContinue | Select-Object -Last 12
    Write-Host "`nsshd.log (key lines):"
    Get-Content 'C:\ProgramData\ssh\logs\sshd.log' -ErrorAction SilentlyContinue | Where-Object {
        $_ -match 'token|am_system|EqualSid|process|custom|fail|error|fork|Accepted|returning|PATH'
    } | Select-Object -Last 20
} else {
    Write-Host "=== SUCCESS! SSH WORKS ==="
    Write-Host "Testing 'echo test':"
    $proc2 = Start-Process -FilePath $sshBin `
        -ArgumentList "-4 -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes -i `"$keyFile`" -l jenkins 127.0.0.1 echo NETSVC_PATH1_WORKS" `
        -NoNewWindow -PassThru -RedirectStandardOutput 'C:\ns-out2.txt' -RedirectStandardError 'C:\ns-err2.txt'
    $proc2 | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue
    Write-Host "echo output: $(Get-Content 'C:\ns-out2.txt' -ErrorAction SilentlyContinue)"
}

Stop-Service sshd -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
Remove-Item $keyFile -ErrorAction SilentlyContinue
Write-Host "DONE"
