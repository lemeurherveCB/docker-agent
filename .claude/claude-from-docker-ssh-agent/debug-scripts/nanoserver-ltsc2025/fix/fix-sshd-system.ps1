# Fix sshd to run as true SYSTEM via Task Scheduler
Write-Host "=== Current sshd service config ==="
sc.exe qc sshd 2>&1

Write-Host "`n=== Reset sshd service to LocalSystem ==="
sc.exe config sshd obj= LocalSystem 2>&1

Write-Host "`n=== Stop sshd service if running ==="
Stop-Service sshd -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host "`n=== Check if Task Scheduler service is available ==="
sc.exe query schedule 2>&1

Write-Host "`n=== Check if schtasks.exe exists ==="
if (Test-Path 'C:\Windows\System32\schtasks.exe') {
    Write-Host "schtasks.exe FOUND"
} else {
    Write-Host "schtasks.exe NOT FOUND"
}

Write-Host "`n=== Try creating a scheduled task for sshd as SYSTEM ==="
$taskResult = schtasks.exe /create /tn 'sshd-system' /tr '"C:\Program Files\OpenSSH-Win64\sshd.exe" -f C:\ProgramData\ssh\sshd_config' /sc once /st 00:00 /ru SYSTEM /rl HIGHEST /f 2>&1
Write-Host "Create result: $taskResult"

$runResult = schtasks.exe /run /tn 'sshd-system' 2>&1
Write-Host "Run result: $runResult"

Start-Sleep -Seconds 3
Write-Host "`n=== sshd processes ==="
Get-Process sshd -ErrorAction SilentlyContinue

Write-Host "`n=== Port 22 listening? ==="
netstat -an 2>&1 | findstr ':22 '

Write-Host "`n=== Try SSH connection ==="
$keyFile = 'C:\jenkins_key.pem'
$port = '49913'

$sshOut = 'C:\fix-ssh-out.txt'
$sshErr = 'C:\fix-ssh-err.txt'
$proc = Start-Process -FilePath 'ssh.exe' `
    -ArgumentList "-4 -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=2 -i $keyFile -l jenkins 127.0.0.1 -p $port `"echo SYSTEM_SSHD_SUCCESS`"" `
    -NoNewWindow -PassThru -RedirectStandardOutput $sshOut -RedirectStandardError $sshErr

$proc | Wait-Process -Timeout 20 -ErrorAction SilentlyContinue
if (-not $proc.HasExited) {
    $proc.Kill()
    Write-Host "SSH TIMED OUT"
} else {
    Write-Host "SSH exit code: $($proc.ExitCode)"
}
Write-Host "STDOUT: $(Get-Content $sshOut -ErrorAction SilentlyContinue)"
Write-Host "STDERR: $(Get-Content $sshErr -ErrorAction SilentlyContinue)"

Write-Host "`n=== sshd debug log (last 20 lines) ==="
Get-Content 'C:\ProgramData\ssh\logs\sshd.log' -Tail 20 -ErrorAction SilentlyContinue
