# Test LSAAuthenticationPackage with verbose output + sshd debug mode

Write-Host "=== OpenSSH registry ==="
Get-ItemProperty 'HKLM:\SOFTWARE\OpenSSH' | Select-Object LSAAuthenticationPackage, DefaultShell

Write-Host "`n=== Write key file ==="
$b64Key = "LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNCUDR0KzA2aVZqRDM2bzdjczBiQngveXFIQVBJN2UyOCtJdUp3clU1VTBHQUFBQUpqUkZ3WXIwUmNHCkt3QUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQlA0dCswNmlWakQzNm83Y3MwYkJ4L3lxSEFQSTdlMjgrSXVKd3JVNVUwR0EKQUFBRUFwUEJ1bUE4WWhsYlhWSGMxek1IN2RlZy9aWUtlaDFJcmE1QlFodG1LcU9VL2kzN1RxSldNUGZxanR5elJzSEgvSwpvY0E4anQ3Yno0aTRuQ3RUbFRRWUFBQUFFR3BsYm10cGJuTXRkR1Z6ZEMxclpYa0JBZ01FQlE9PQotLS0tLUVORCBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0K"
$keyFile = 'C:\test_jenkins_key'
[System.IO.File]::WriteAllBytes($keyFile, [System.Convert]::FromBase64String($b64Key))
icacls $keyFile /inheritance:r /grant:r "NT AUTHORITY\SYSTEM:(F)" /grant:r "ContainerAdministrator:(R)" 2>&1 | Out-Null

Write-Host "`n=== Kill sshd, start debug sshd on port 2222 ==="
Stop-Process -Name sshd -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$sshdProc = Start-Process -FilePath 'C:\Program Files\OpenSSH-Win64\sshd.exe' `
    -ArgumentList '-ddd -p 2222 -f C:\ProgramData\ssh\sshd_config' `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput 'C:\sshdv-out.txt' `
    -RedirectStandardError 'C:\sshdv-err.txt'
Start-Sleep -Seconds 2

Write-Host "`n=== SSH -v to port 2222 ==="
$sshBin = 'C:\Program Files\OpenSSH-Win64\ssh.exe'
$sshProc = Start-Process -FilePath $sshBin `
    -ArgumentList "-4 -v -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=2 -i `"$keyFile`" -l jenkins 127.0.0.1 -p 2222 `"echo LSA_AUTH_PACKAGE_TEST`"" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput 'C:\sshv-out.txt' `
    -RedirectStandardError 'C:\sshv-err.txt'
$sshProc | Wait-Process -Timeout 25 -ErrorAction SilentlyContinue
if (-not $sshProc.HasExited) { $sshProc.Kill(); Write-Host "SSH TIMEOUT" }
else { Write-Host "SSH exit: $($sshProc.ExitCode)" }

Start-Sleep -Seconds 1
if (-not $sshdProc.HasExited) { $sshdProc.Kill() }

Write-Host "SSH stdout: $(Get-Content 'C:\sshv-out.txt' -ErrorAction SilentlyContinue)"
Write-Host "`nSSH stderr:"
Get-Content 'C:\sshv-err.txt' -ErrorAction SilentlyContinue | Select-Object -Last 15

Write-Host "`n=== sshd debug output (key lines) ==="
Get-Content 'C:\sshdv-err.txt' -ErrorAction SilentlyContinue | Where-Object {
    $_ -match 'token|system|lsa|logon|jenkins|auth|Error|error|fail|custom|privilege|LSA|process'
} | Select-Object -Last 30

Remove-Item $keyFile -ErrorAction SilentlyContinue

Write-Host "`n=== Restart normal sshd ==="
schtasks.exe /create /tn 'sshd-system' /tr '"C:\Program Files\OpenSSH-Win64\sshd.exe" -f C:\ProgramData\ssh\sshd_config' /sc once /st 00:00 /ru SYSTEM /rl HIGHEST /f 2>&1 | Out-Null
schtasks.exe /run /tn 'sshd-system' 2>&1 | Out-Null
Start-Sleep -Seconds 2
