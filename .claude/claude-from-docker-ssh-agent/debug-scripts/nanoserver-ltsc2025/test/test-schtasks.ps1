Write-Host "=== Test schtasks in container ==="
schtasks.exe /? 2>&1 | Select-String "CREATE|QUERY" | Select-Object -First 3

Write-Host "`n=== Create scheduled task for sshd as SYSTEM ==="
Stop-Service sshd -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# Create task to run sshd as SYSTEM
$result = schtasks.exe /create /tn 'sshd-system' /tr '"C:\Program Files\OpenSSH-Win64\sshd.exe" -f C:\ProgramData\ssh\sshd_config' /sc once /st 00:00 /ru SYSTEM /rl HIGHEST /f 2>&1
Write-Host "Task create result: $result"

# Run the task
$result = schtasks.exe /run /tn 'sshd-system' 2>&1
Write-Host "Task run result: $result"

Start-Sleep -Seconds 3
Write-Host "`n=== sshd process after scheduled task start ==="
Get-Process sshd -ErrorAction SilentlyContinue | Select-Object Id,Name

Write-Host "`n=== Test SSH connection ==="
$keyFile = 'C:\jenkins_key.pem'
$port = '49913'  # This needs to match the published port

$proc = Start-Process -FilePath 'ssh.exe' `
    -ArgumentList "-4 -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -i $keyFile -l jenkins 127.0.0.1 -p $port `"echo hello_from_system_sshd`"" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput C:\sshtask-out.txt `
    -RedirectStandardError C:\sshtask-err.txt

$proc | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue
if (-not $proc.HasExited) {
    $proc.Kill()
    Write-Host "TIMED OUT"
} else {
    Write-Host "Exit code: $($proc.ExitCode)"
}
Write-Host "STDOUT:"
Get-Content C:\sshtask-out.txt -ErrorAction SilentlyContinue
Write-Host "STDERR:"
Get-Content C:\sshtask-err.txt -ErrorAction SilentlyContinue
