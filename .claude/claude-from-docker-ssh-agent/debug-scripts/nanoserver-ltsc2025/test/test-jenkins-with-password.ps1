# PATH 2 fix with jenkins password set for service logon
# sc.exe auto-grants SeServiceLogonRight when setting service account

Write-Host "=== Set password for jenkins ==="
net user jenkins "Jenkins@2025Svc!" 2>&1
Write-Host "net user exit: $LASTEXITCODE"

Write-Host "`n=== Disable blank password restriction (belt+suspenders) ==="
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LimitBlankPasswordUse' -Value 0

Write-Host "`n=== Stop all sshd ==="
Stop-Process -Name sshd -Force -ErrorAction SilentlyContinue
Stop-Service sshd -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
Start-Sleep -Seconds 2

Write-Host "`n=== Configure sshd to run as jenkins (sc.exe grants SeServiceLogonRight) ==="
sc.exe config sshd obj= ".\jenkins" password= "Jenkins@2025Svc!" 2>&1

Write-Host "`n=== Start sshd as jenkins ==="
sc.exe start sshd 2>&1
Start-Sleep -Seconds 4

$proc = Get-Process sshd -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "SUCCESS: sshd running as jenkins, PID=$($proc.Id)"
    sc.exe qc sshd 2>&1 | Where-Object { $_ -match 'ACCOUNT' }
} else {
    Write-Host "FAILED: sshd not running"
    # Check Windows event log
    Get-EventLog -LogName System -Source "Service Control Manager" -Newest 3 -ErrorAction SilentlyContinue | Format-List
    exit 1
}

Write-Host "`n=== Test SSH as jenkins (expect whoami = jenkins) ==="
$b64Key = "LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNCUDR0KzA2aVZqRDM2bzdjczBiQngveXFIQVBJN2UyOCtJdUp3clU1VTBHQUFBQUpqUkZ3WXIwUmNHCkt3QUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQlA0dCswNmlWakQzNm83Y3MwYkJ4L3lxSEFQSTdlMjgrSXVKd3JVNVUwR0EKQUFBRUFwUEJ1bUE4WWhsYlhWSGMxek1IN2RlZy9aWUtlaDFJcmE1QlFodG1LcU9VL2kzN1RxSldNUGZxanR5elJzSEgvSwpvY0E4anQ3Yno0aTRuQ3RUbFRRWUFBQUFFR3BsYm10cGJuTXRkR1Z6ZEMxclpYa0JBZ01FQlE9PQotLS0tLUVORCBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0K"
$keyFile = 'C:\test_jenkins_key'
[System.IO.File]::WriteAllBytes($keyFile, [System.Convert]::FromBase64String($b64Key))
icacls $keyFile /inheritance:r /grant:r "NT AUTHORITY\SYSTEM:(F)" /grant:r "ContainerAdministrator:(R)" 2>&1 | Out-Null

$sshBin = 'C:\Program Files\OpenSSH-Win64\ssh.exe'
$result = Start-Process -FilePath $sshBin `
    -ArgumentList "-4 -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -i `"$keyFile`" -l jenkins 127.0.0.1 whoami" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput 'C:\p2-out.txt' -RedirectStandardError 'C:\p2-err.txt'
$result | Wait-Process -Timeout 25 -ErrorAction SilentlyContinue
if (-not $result.HasExited) { $result.Kill(); Write-Host "TIMED OUT" }
else { Write-Host "SSH exit: $($result.ExitCode)" }

Write-Host "STDOUT: $(Get-Content 'C:\p2-out.txt' -ErrorAction SilentlyContinue)"
if ($result.ExitCode -ne 0) {
    Write-Host "STDERR (last 12):"
    Get-Content 'C:\p2-err.txt' -ErrorAction SilentlyContinue | Select-Object -Last 12
    Write-Host "`nsshd.log (key lines):"
    Get-Content 'C:\ProgramData\ssh\logs\sshd.log' -ErrorAction SilentlyContinue | Where-Object {
        $_ -match 'token|am_system|equal|EqualSid|process|custom|fail|error|fork|Accepted|PATH'
    } | Select-Object -Last 20
}

Stop-Service sshd -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
Remove-Item $keyFile -ErrorAction SilentlyContinue
Write-Host "DONE"
