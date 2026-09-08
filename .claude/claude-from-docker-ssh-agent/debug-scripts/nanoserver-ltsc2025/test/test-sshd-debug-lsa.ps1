# Run sshd in debug mode to see full token creation path with CustomLSAProvider
# Start debug sshd on port 2222 to avoid conflict, then connect and capture output

Write-Host "=== Current CustomLSAProvider ==="
Get-ItemProperty 'HKLM:\SOFTWARE\OpenSSH' -Name CustomLSAProvider -ErrorAction SilentlyContinue

Write-Host "`n=== Stop existing sshd ==="
Stop-Process -Name sshd -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Write private key for test
$b64Key = "LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNCUDR0KzA2aVZqRDM2bzdjczBiQngveXFIQVBJN2UyOCtJdUp3clU1VTBHQUFBQUpqUkZ3WXIwUmNHCkt3QUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQlA0dCswNmlWakQzNm83Y3MwYkJ4L3lxSEFQSTdlMjgrSXVKd3JVNVUwR0EKQUFBRUFwUEJ1bUE4WWhsYlhWSGMxek1IN2RlZy9aWUtlaDFJcmE1QlFodG1LcU9VL2kzN1RxSldNUGZxanR5elJzSEgvSwpvY0E4anQ3Yno0aTRuQ3RUbFRRWUFBQUFFR3BsYm10cGJuTXRkR1Z6ZEMxclpYa0JBZ01FQlE9PQotLS0tLUVORCBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0K"
$keyFile = 'C:\test_jenkins_key'
[System.IO.File]::WriteAllBytes($keyFile, [System.Convert]::FromBase64String($b64Key))
icacls $keyFile /inheritance:r /grant:r "NT AUTHORITY\SYSTEM:(F)" /grant:r "ContainerAdministrator:(R)" 2>&1 | Out-Null

# Start sshd in debug mode, output to files
$sshdArgs = '-ddd -p 2222 -f C:\ProgramData\ssh\sshd_config'
Write-Host "Starting sshd -ddd on port 2222..."
$sshdProc = Start-Process -FilePath 'C:\Program Files\OpenSSH-Win64\sshd.exe' `
    -ArgumentList $sshdArgs `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput 'C:\sshd-debug2-stdout.txt' `
    -RedirectStandardError 'C:\sshd-debug2-stderr.txt'
Start-Sleep -Seconds 2
Write-Host "sshd debug PID: $($sshdProc.Id)"

# Now attempt SSH connection to port 2222
$sshBin = 'C:\Program Files\OpenSSH-Win64\ssh.exe'
Write-Host "Attempting SSH to port 2222..."
$sshProc = Start-Process -FilePath $sshBin `
    -ArgumentList "-4 -v -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=2 -i `"$keyFile`" -l jenkins 127.0.0.1 -p 2222 `"echo DBG_LSA_TEST`"" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput 'C:\ssh-debug2-out.txt' `
    -RedirectStandardError 'C:\ssh-debug2-err.txt'

$sshProc | Wait-Process -Timeout 20 -ErrorAction SilentlyContinue
if (-not $sshProc.HasExited) { $sshProc.Kill(); Write-Host "SSH TIMEOUT" }
else { Write-Host "SSH exit: $($sshProc.ExitCode)" }
Write-Host "SSH stdout: $(Get-Content 'C:\ssh-debug2-out.txt' -ErrorAction SilentlyContinue)"

# Stop sshd
Start-Sleep -Seconds 1
if (-not $sshdProc.HasExited) { $sshdProc.Kill() }

Write-Host "`n=== sshd debug3 output (key lines) ==="
Get-Content 'C:\sshd-debug2-stderr.txt' -ErrorAction SilentlyContinue | Where-Object {
    $_ -match 'token|system|lsa|logon|jenkins|user|auth|Error|error|fail|custom|privilege'
} | Select-Object -Last 40

Write-Host "`n=== SSH client stderr (last 10) ==="
Get-Content 'C:\ssh-debug2-err.txt' -ErrorAction SilentlyContinue | Select-Object -Last 10

Remove-Item $keyFile -ErrorAction SilentlyContinue

Write-Host "`n=== Restart normal sshd as SYSTEM ==="
schtasks.exe /create /tn 'sshd-system' /tr '"C:\Program Files\OpenSSH-Win64\sshd.exe" -f C:\ProgramData\ssh\sshd_config' /sc once /st 00:00 /ru SYSTEM /rl HIGHEST /f 2>&1
schtasks.exe /run /tn 'sshd-system' 2>&1
Start-Sleep -Seconds 2
Write-Host "sshd PIDs: $((Get-Process sshd -ErrorAction SilentlyContinue).Id -join ', ')"
