$keyFile = 'C:\jenkins_key.pem'
$port = '49913'

# Test: redirect ssh output to files so no pipe-buffering issues
Write-Host "=== SSH test with file-based output capture ==="
$proc = Start-Process -FilePath 'ssh.exe' `
    -ArgumentList "-4 -vvv -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -i $keyFile -l jenkins 127.0.0.1 -p $port `"echo hello123`"" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput C:\ssh-stdout.txt `
    -RedirectStandardError C:\ssh-stderr.txt

Write-Host "SSH process started PID=$($proc.Id)"

# Check interim output at 5s
Start-Sleep -Seconds 5
Write-Host "--- stderr at 5s ---"
Get-Content C:\ssh-stderr.txt -ErrorAction SilentlyContinue
Write-Host "--- stdout at 5s ---"
Get-Content C:\ssh-stdout.txt -ErrorAction SilentlyContinue

# Kill at 25s total
Start-Sleep -Seconds 20
if (-not $proc.HasExited) {
    $proc.Kill()
    Write-Host "`n=== KILLED after 25s ==="
} else {
    Write-Host "`n=== Exited with code $($proc.ExitCode) ==="
}

Write-Host "--- FINAL stderr ---"
Get-Content C:\ssh-stderr.txt -ErrorAction SilentlyContinue
Write-Host "--- FINAL stdout ---"
Get-Content C:\ssh-stdout.txt -ErrorAction SilentlyContinue

# Also check what commands sshd spawns inside the container
Write-Host "`n=== Processes in container ==="
docker exec test-2025 pwsh.exe -NoLogo -C "Get-Process | Where-Object { `$_.Name -match 'ssh|pwsh|cmd' } | Select-Object Id,Name,CPU"

# Check if jenkins user exists properly
Write-Host "`n=== Jenkins user info ==="
docker exec test-2025 pwsh.exe -NoLogo -C "net user jenkins 2>&1"

# Check if we can run a cmd as jenkins user in container
Write-Host "`n=== Test: run as jenkins user with runas ==="
docker exec test-2025 pwsh.exe -NoLogo -C "whoami"

Write-Host "`n=== Done ==="
