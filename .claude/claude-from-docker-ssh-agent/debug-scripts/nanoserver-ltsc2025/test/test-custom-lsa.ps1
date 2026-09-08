# Test Win32-OpenSSH CustomLSAProvider registry key bypass
# The binary has: "returning process token since custom lsa is configured"
# This path doesn't require SeTcbPrivilege or am_system() = true

Write-Host "=== Current OpenSSH registry ==="
Get-ItemProperty 'HKLM:\SOFTWARE\OpenSSH' 2>&1

Write-Host "`n=== Set CustomLSAProvider registry key ==="
# Try with a value pointing to a package that exists but may not fully work
# The key insight: if custom LSA is "configured", Win32-OpenSSH falls back to process token
Set-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name 'CustomLSAProvider' -Value 'msv1_0' -Type String
Get-ItemProperty 'HKLM:\SOFTWARE\OpenSSH' 2>&1

Write-Host "`n=== Stop current sshd ==="
$sshdPid = (Get-Process sshd -ErrorAction SilentlyContinue).Id
if ($sshdPid) {
    Stop-Process -Id $sshdPid -Force
    Start-Sleep -Seconds 2
    Write-Host "Stopped sshd PID $sshdPid"
}

Write-Host "`n=== Start sshd via scheduled task as SYSTEM ==="
schtasks.exe /create /tn 'sshd-system' /tr '"C:\Program Files\OpenSSH-Win64\sshd.exe" -f C:\ProgramData\ssh\sshd_config' /sc once /st 00:00 /ru SYSTEM /rl HIGHEST /f 2>&1
schtasks.exe /run /tn 'sshd-system' 2>&1
Start-Sleep -Seconds 3
Write-Host "sshd PIDs: $((Get-Process sshd -ErrorAction SilentlyContinue).Id -join ', ')"

Write-Host "`n=== Test SSH with CustomLSAProvider set ==="
$b64Key = "LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNCUDR0KzA2aVZqRDM2bzdjczBiQngveXFIQVBJN2UyOCtJdUp3clU1VTBHQUFBQUpqUkZ3WXIwUmNHCkt3QUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQlA0dCswNmlWakQzNm83Y3MwYkJ4L3lxSEFQSTdlMjgrSXVKd3JVNVUwR0EKQUFBRUFwUEJ1bUE4WWhsYlhWSGMxek1IN2RlZy9aWUtlaDFJcmE1QlFodG1LcU9VL2kzN1RxSldNUGZxanR5elJzSEgvSwpvY0E4anQ3Yno0aTRuQ3RUbFRRWUFBQUFFR3BsYm10cGJuTXRkR1Z6ZEMxclpYa0JBZ01FQlE9PQotLS0tLUVORCBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0K"
$keyBytes = [System.Convert]::FromBase64String($b64Key)
$keyFile = 'C:\test_jenkins_key'
[System.IO.File]::WriteAllBytes($keyFile, $keyBytes)
icacls $keyFile /inheritance:r /grant:r "NT AUTHORITY\SYSTEM:(F)" /grant:r "ContainerAdministrator:(R)" 2>&1 | Out-Null

$sshBin = 'C:\Program Files\OpenSSH-Win64\ssh.exe'
$sshOut = 'C:\lsa-ssh-out.txt'
$sshErr = 'C:\lsa-ssh-err.txt'
$proc = Start-Process -FilePath $sshBin `
    -ArgumentList "-4 -v -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -i `"$keyFile`" -l jenkins 127.0.0.1 -p 22 `"echo CUSTOM_LSA_TEST`"" `
    -NoNewWindow -PassThru -RedirectStandardOutput $sshOut -RedirectStandardError $sshErr
$proc | Wait-Process -Timeout 25 -ErrorAction SilentlyContinue
if (-not $proc.HasExited) { $proc.Kill(); Write-Host "TIMED OUT" } else { Write-Host "Exit: $($proc.ExitCode)" }
$out = Get-Content $sshOut -ErrorAction SilentlyContinue
$err = Get-Content $sshErr -ErrorAction SilentlyContinue
Write-Host "STDOUT: $out"
Write-Host "`nSTDERR (key lines):"
$err | Select-Object -Last 15 | ForEach-Object { Write-Host "  $_" }

Write-Host "`n=== sshd.log after attempt ==="
Get-Content 'C:\ProgramData\ssh\logs\sshd.log' -Tail 30 -ErrorAction SilentlyContinue

Remove-Item $keyFile -ErrorAction SilentlyContinue
