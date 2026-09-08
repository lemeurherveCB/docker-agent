# Write private key using base64 to ensure correct binary content (LF line endings, no BOM)
$b64Key = "LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNCUDR0KzA2aVZqRDM2bzdjczBiQngveXFIQVBJN2UyOCtJdUp3clU1VTBHQUFBQUpqUkZ3WXIwUmNHCkt3QUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQlA0dCswNmlWakQzNm83Y3MwYkJ4L3lxSEFQSTdlMjgrSXVKd3JVNVUwR0EKQUFBRUFwUEJ1bUE4WWhsYlhWSGMxek1IN2RlZy9aWUtlaDFJcmE1QlFodG1LcU9VL2kzN1RxSldNUGZxanR5elJzSEgvSwpvY0E4anQ3Yno0aTRuQ3RUbFRRWUFBQUFFR3BsYm10cGJuTXRkR1Z6ZEMxclpYa0JBZ01FQlE9PQotLS0tLUVORCBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0K"
$keyBytes = [System.Convert]::FromBase64String($b64Key)
$keyFile = 'C:\test_jenkins_key'
[System.IO.File]::WriteAllBytes($keyFile, $keyBytes)

# Fix permissions
icacls $keyFile /inheritance:r /grant:r "NT AUTHORITY\SYSTEM:(F)" /grant:r "ContainerAdministrator:(R)" 2>&1

Write-Host "Key file written: $(Test-Path $keyFile)"
Write-Host "Key size: $((Get-Item $keyFile).Length) bytes"

Write-Host "`n=== sshd running? ==="
Get-Process sshd -ErrorAction SilentlyContinue | Select-Object Id,Name

Write-Host "`n=== SSH test (127.0.0.1:22) ==="
$sshBin = 'C:\Program Files\OpenSSH-Win64\ssh.exe'
$sshOut = 'C:\b64-ssh-out.txt'
$sshErr = 'C:\b64-ssh-err.txt'

$proc = Start-Process -FilePath $sshBin `
    -ArgumentList "-4 -v -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -i `"$keyFile`" -l jenkins 127.0.0.1 -p 22 `"echo SYSTEM_SSHD_WORKS`"" `
    -NoNewWindow -PassThru -RedirectStandardOutput $sshOut -RedirectStandardError $sshErr

$proc | Wait-Process -Timeout 30 -ErrorAction SilentlyContinue
if (-not $proc.HasExited) {
    $proc.Kill()
    Write-Host "SSH TIMED OUT after 30s"
} else {
    Write-Host "SSH exit code: $($proc.ExitCode)"
}
Write-Host "STDOUT: $(Get-Content $sshOut -ErrorAction SilentlyContinue)"
Write-Host "`nSTDERR (last 25 lines):"
Get-Content $sshErr -ErrorAction SilentlyContinue | Select-Object -Last 25

Write-Host "`n=== sshd.log (last 25 lines) ==="
Get-Content 'C:\ProgramData\ssh\logs\sshd.log' -Tail 25 -ErrorAction SilentlyContinue

Remove-Item $keyFile -ErrorAction SilentlyContinue
