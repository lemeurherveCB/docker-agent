$keyFile = 'C:\jenkins_key.pem'
$port = '49913'

Write-Host "=== Step 1: key permissions ==="
icacls.exe $keyFile /inheritance:r /grant:r 'Administrator:(F)' 2>&1 | Write-Host

Write-Host "=== Step 2: container port check ==="
docker port test-2025 22

Write-Host "=== Step 3: SSH echo test (30s timeout) ==="
$proc = New-Object System.Diagnostics.Process
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'ssh.exe'
$psi.Arguments = "-4 -v -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -i $keyFile -l jenkins 127.0.0.1 -p $port ""echo hello123"""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$proc.StartInfo = $psi
[void]$proc.Start()
$stdoutTask = $proc.StandardOutput.ReadToEndAsync()
$stderrTask = $proc.StandardError.ReadToEndAsync()
$completed = $proc.WaitForExit(30000)
if (-not $completed) {
    $proc.Kill()
    $proc.WaitForExit()
    Write-Host "SSH TIMED OUT after 30s"
} else {
    Write-Host "SSH exit code: $($proc.ExitCode)"
}
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
Write-Host "STDOUT: $stdout"
Write-Host "STDERR (verbose): $stderr"

Write-Host "=== Step 4: Check DefaultShell registry in container ==="
docker exec test-2025 pwsh.exe -NoLogo -C "(Get-ItemProperty 'HKLM:\SOFTWARE\OpenSSH' -ErrorAction SilentlyContinue).DefaultShell"

Write-Host "=== Step 5: Check authorized_keys ==="
docker exec test-2025 pwsh.exe -NoLogo -C "Get-Content 'C:\Users\jenkins\.ssh\authorized_keys' -ErrorAction SilentlyContinue"

Write-Host "=== Step 6: Check sshd_config in container ==="
docker exec test-2025 pwsh.exe -NoLogo -C "Get-Content 'C:\ProgramData\ssh\sshd_config' -ErrorAction SilentlyContinue"

Write-Host "=== Done ==="
