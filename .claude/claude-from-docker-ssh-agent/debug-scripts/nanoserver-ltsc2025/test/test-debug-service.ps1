# Run sshd -ddd as LocalSystem service context on port 2222
# We need to see if the LSA escape hatch triggers

Write-Host "=== Stop sshd service ==="
Stop-Service sshd -Force -ErrorAction SilentlyContinue
Stop-Process -Name sshd -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host "=== Verify registry ==="
Get-ItemProperty 'HKLM:\SOFTWARE\OpenSSH' | Select-Object LSAAuthenticationPackage

Write-Host "`n=== Create sshtask with LocalSystem ==="
# Use schtasks but with LocalSystem (same as service)
schtasks.exe /create /tn 'sshd-local-debug' `
    /tr '"C:\Program Files\OpenSSH-Win64\sshd.exe" -ddd -p 2222 -f C:\ProgramData\ssh\sshd_config -E C:\sshd-dbg3.log' `
    /sc once /st 00:00 /ru SYSTEM /rl HIGHEST /f 2>&1
schtasks.exe /run /tn 'sshd-local-debug' 2>&1
Start-Sleep -Seconds 3
Write-Host "sshd processes: $((Get-Process sshd -ErrorAction SilentlyContinue).Id -join ', ')"

Write-Host "`n=== Test SSH ==="
$b64Key = "LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNCUDR0KzA2aVZqRDM2bzdjczBiQngveXFIQVBJN2UyOCtJdUp3clU1VTBHQUFBQUpqUkZ3WXIwUmNHCkt3QUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQlA0dCswNmlWakQzNm83Y3MwYkJ4L3lxSEFQSTdlMjgrSXVKd3JVNVUwR0EKQUFBRUFwUEJ1bUE4WWhsYlhWSGMxek1IN2RlZy9aWUtlaDFJcmE1QlFodG1LcU9VL2kzN1RxSldNUGZxanR5elJzSEgvSwpvY0E4anQ3Yno0aTRuQ3RUbFRRWUFBQUFFR3BsYm10cGJuTXRkR1Z6ZEMxclpYa0JBZ01FQlE9PQotLS0tLUVORCBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0K"
$keyFile = 'C:\test_jenkins_key'
[System.IO.File]::WriteAllBytes($keyFile, [System.Convert]::FromBase64String($b64Key))
icacls $keyFile /inheritance:r /grant:r "NT AUTHORITY\SYSTEM:(F)" /grant:r "ContainerAdministrator:(R)" 2>&1 | Out-Null

$sshBin = 'C:\Program Files\OpenSSH-Win64\ssh.exe'
$sshProc = Start-Process -FilePath $sshBin `
    -ArgumentList "-4 -v -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=2 -i `"$keyFile`" -l jenkins 127.0.0.1 -p 2222 `"echo DEBUG_SVC_TEST`"" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput 'C:\svc-ssh-out.txt' -RedirectStandardError 'C:\svc-ssh-err.txt'
$sshProc | Wait-Process -Timeout 25 -ErrorAction SilentlyContinue
if (-not $sshProc.HasExited) { $sshProc.Kill(); Write-Host "TIMEOUT" }
else { Write-Host "SSH exit: $($sshProc.ExitCode)" }
Write-Host "SSH stdout: $(Get-Content 'C:\svc-ssh-out.txt' -ErrorAction SilentlyContinue)"

Start-Sleep -Seconds 1
Stop-Process -Name sshd -Force -ErrorAction SilentlyContinue

Write-Host "`n=== sshd debug output (token/system/lsa/auth lines) ==="
Get-Content 'C:\sshd-dbg3.log' -ErrorAction SilentlyContinue | Where-Object {
    $_ -match 'token|system|lsa|LSA|logon|auth|process|custom|jenkins|fork|child|privilege|Error|error|failed'
} | Select-Object -Last 40

Remove-Item $keyFile -ErrorAction SilentlyContinue
