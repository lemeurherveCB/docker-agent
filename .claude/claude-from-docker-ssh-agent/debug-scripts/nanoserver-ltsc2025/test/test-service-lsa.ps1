# The fix: sshd runs as SERVICE (not scheduled task) + LSAAuthenticationPackage set
# Service context: LookupAccountName("jenkins") fails 1332 → user_sid=NULL → escape hatch!

Write-Host "=== Reset sshd to run as LocalSystem SERVICE ==="
Stop-Process -Name sshd -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
sc.exe config sshd obj= LocalSystem 2>&1
sc.exe config sshd start= demand 2>&1

Write-Host "`n=== Verify LSAAuthenticationPackage set ==="
Set-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name 'LSAAuthenticationPackage' -Value 'msv1_0' -Type String
Get-ItemProperty 'HKLM:\SOFTWARE\OpenSSH' | Select-Object LSAAuthenticationPackage, DefaultShell

Write-Host "`n=== Start sshd as SERVICE ==="
Start-Service sshd
Start-Sleep -Seconds 3
Get-Process sshd -ErrorAction SilentlyContinue | Select-Object Id, Name

Write-Host "`n=== sc.exe qc sshd (verify service account) ==="
sc.exe qc sshd 2>&1 | Where-Object { $_ -match 'NAME|SERVICE' }

Write-Host "`n=== Write key, test SSH ==="
$b64Key = "LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNCUDR0KzA2aVZqRDM2bzdjczBiQngveXFIQVBJN2UyOCtJdUp3clU1VTBHQUFBQUpqUkZ3WXIwUmNHCkt3QUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQlA0dCswNmlWakQzNm83Y3MwYkJ4L3lxSEFQSTdlMjgrSXVKd3JVNVUwR0EKQUFBRUFwUEJ1bUE4WWhsYlhWSGMxek1IN2RlZy9aWUtlaDFJcmE1QlFodG1LcU9VL2kzN1RxSldNUGZxanR5elJzSEgvSwpvY0E4anQ3Yno0aTRuQ3RUbFRRWUFBQUFFR3BsYm10cGJuTXRkR1Z6ZEMxclpYa0JBZ01FQlE9PQotLS0tLUVORCBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0K"
$keyFile = 'C:\test_jenkins_key'
[System.IO.File]::WriteAllBytes($keyFile, [System.Convert]::FromBase64String($b64Key))
icacls $keyFile /inheritance:r /grant:r "NT AUTHORITY\SYSTEM:(F)" /grant:r "ContainerAdministrator:(R)" 2>&1 | Out-Null

$sshBin = 'C:\Program Files\OpenSSH-Win64\ssh.exe'
$proc = Start-Process -FilePath $sshBin `
    -ArgumentList "-4 -v -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -i `"$keyFile`" -l jenkins 127.0.0.1 -p 22 `"echo SERVICE_LSA_SUCCESS`"" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput 'C:\svc-lsa-out.txt' `
    -RedirectStandardError 'C:\svc-lsa-err.txt'
$proc | Wait-Process -Timeout 25 -ErrorAction SilentlyContinue
if (-not $proc.HasExited) { $proc.Kill(); Write-Host "TIMED OUT" } else { Write-Host "Exit: $($proc.ExitCode)" }
Write-Host "STDOUT: $(Get-Content 'C:\svc-lsa-out.txt' -ErrorAction SilentlyContinue)"
Write-Host "`nSTDERR (last 10):"
Get-Content 'C:\svc-lsa-err.txt' -ErrorAction SilentlyContinue | Select-Object -Last 10

Write-Host "`n=== sshd.log last 20 ==="
Get-Content 'C:\ProgramData\ssh\logs\sshd.log' -Tail 20 -ErrorAction SilentlyContinue

Remove-Item $keyFile -ErrorAction SilentlyContinue
