# Test SSH from EC2 host to container port, run with full path
Write-Host "=== sshd status ==="
Get-Process sshd -ErrorAction SilentlyContinue | Select-Object Id,Name

Write-Host "`n=== Port 22 ==="
netstat -an 2>&1 | findstr ':22 '

Write-Host "`n=== Find ssh.exe ==="
$sshExe = Get-Command ssh.exe -ErrorAction SilentlyContinue
if ($sshExe) { Write-Host "Found: $($sshExe.Source)" }
else {
    $candidates = @(
        'C:\Program Files\OpenSSH-Win64\ssh.exe',
        'C:\Windows\System32\OpenSSH\ssh.exe',
        'C:\Program Files\OpenSSH\ssh.exe'
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { Write-Host "Found: $c"; $sshExe = @{Source=$c}; break }
    }
}

if (-not $sshExe) {
    Write-Host "ssh.exe NOT found anywhere"
    exit 1
}

$sshBin = if ($sshExe -is [hashtable]) { $sshExe.Source } else { $sshExe.Source }
Write-Host "Using: $sshBin"

Write-Host "`n=== Check authorized_keys for jenkins ==="
$authKeys = 'C:\Users\jenkins\.ssh\authorized_keys'
if (Test-Path $authKeys) {
    Write-Host "Exists, content:"
    Get-Content $authKeys
} else {
    Write-Host "NOT FOUND: $authKeys"
    # Check alternate location
    $altKeys = 'C:\ProgramData\ssh\administrators_authorized_keys'
    if (Test-Path $altKeys) { Write-Host "Alt keys: $(Get-Content $altKeys | Select-Object -First 1)..." }
}

Write-Host "`n=== Check jenkins_key.pem ==="
if (Test-Path 'C:\jenkins_key.pem') {
    Write-Host "Key file exists"
    icacls 'C:\jenkins_key.pem' 2>&1
} else { Write-Host "NOT FOUND" }

Write-Host "`n=== SSH test from inside container to 127.0.0.1:22 ==="
$keyFile = 'C:\jenkins_key.pem'
$sshOut = 'C:\ssh-inside-out.txt'
$sshErr = 'C:\ssh-inside-err.txt'
$proc = Start-Process -FilePath $sshBin `
    -ArgumentList "-4 -v -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=2 -i `"$keyFile`" -l jenkins 127.0.0.1 -p 22 `"echo HELLO_FROM_SYSTEM_SSHD`"" `
    -NoNewWindow -PassThru -RedirectStandardOutput $sshOut -RedirectStandardError $sshErr

$proc | Wait-Process -Timeout 25 -ErrorAction SilentlyContinue
if (-not $proc.HasExited) {
    $proc.Kill()
    Write-Host "TIMED OUT"
} else {
    Write-Host "Exit code: $($proc.ExitCode)"
}
Write-Host "STDOUT: $(Get-Content $sshOut -ErrorAction SilentlyContinue)"
Write-Host "STDERR:"
Get-Content $sshErr -ErrorAction SilentlyContinue | Select-Object -Last 30

Write-Host "`n=== sshd log (last 20 lines) ==="
Get-Content 'C:\ProgramData\ssh\logs\sshd.log' -Tail 20 -ErrorAction SilentlyContinue
