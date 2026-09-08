# Create the private key file and test SSH to itself (port 22)
$privKey = @"
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBP4t+06iVjD36o7cs0bBx/yqHAPI7e28+IuJwrU5U0GAAAAJjRFwYr0RcG
KwAAAAtzc2gtZWQyNTUxOQAAACBP4t+06iVjD36o7cs0bBx/yqHAPI7e28+IuJwrU5U0GA
AAAEApPBumA8YhlbXVHc1zMH7deg/ZYKeh1Ira5BQhtmKqOU/i37TqJWMPfqjtyzRsHH/K
ocA8jt7bz4i4nCtTlTQYAAAAEGplbmtpbnMtdGVzdC1rZXkBAgMEBQ==
-----END OPENSSH PRIVATE KEY-----
"@

$keyFile = 'C:\test_jenkins_key'
Set-Content -Path $keyFile -Value $privKey -Encoding UTF8 -NoNewline

# Fix permissions: only SYSTEM + ContainerAdministrator
icacls $keyFile /inheritance:r /grant:r "NT AUTHORITY\SYSTEM:(F)" /grant:r "ContainerAdministrator:(R)" 2>&1

Write-Host "`n=== Check sshd process and user ==="
$sshdProcs = Get-Process sshd -ErrorAction SilentlyContinue
Write-Host "sshd processes: $($sshdProcs.Count)"
foreach ($p in $sshdProcs) {
    Write-Host "  PID=$($p.Id)"
}

Write-Host "`n=== Check am_system via whoami for sshd ==="
# We can't directly check, but we can look at the process owner
try {
    $wmi = Get-WmiObject -Query "SELECT * FROM Win32_Process WHERE ProcessId=$($sshdProcs[0].Id)" -ErrorAction Stop
    $owner = $wmi.GetOwner()
    Write-Host "sshd owner: $($owner.Domain)\$($owner.User)"
} catch {
    Write-Host "Could not get owner: $_"
}

Write-Host "`n=== SSH test with key (port 22 inside container) ==="
$sshBin = 'C:\Program Files\OpenSSH-Win64\ssh.exe'
$sshOut = 'C:\key-ssh-out.txt'
$sshErr = 'C:\key-ssh-err.txt'

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
Write-Host "STDERR (last 20 lines):"
Get-Content $sshErr -ErrorAction SilentlyContinue | Select-Object -Last 20

Write-Host "`n=== sshd log (last 20 lines) ==="
Get-Content 'C:\ProgramData\ssh\logs\sshd.log' -Tail 20 -ErrorAction SilentlyContinue

Remove-Item $keyFile -ErrorAction SilentlyContinue
