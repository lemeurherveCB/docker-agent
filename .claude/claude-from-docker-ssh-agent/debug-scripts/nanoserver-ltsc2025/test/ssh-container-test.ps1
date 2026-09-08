$keyFile = 'C:\jenkins_key.pem'
$port = '49913'

# Fix key permissions
icacls.exe $keyFile /inheritance:r /grant:r 'Administrator:(F)' | Out-Null
icacls.exe $keyFile /remove 'BUILTIN\Users' | Out-Null
icacls.exe $keyFile /remove 'Everyone' | Out-Null
Write-Host "Key permissions set"

# Test 1: simple echo (uses DefaultShell which is pwsh.exe)
Write-Host "`n--- Test 1: simple echo (via DefaultShell=pwsh.exe) ---"
$before = Get-Date
$output = ssh.exe -4 -v -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes -i $keyFile -l jenkins 127.0.0.1 -p $port "echo hello123" 2>&1
$after = Get-Date
Write-Host "Exit: $LASTEXITCODE  Duration: $(($after-$before).TotalSeconds)s"
Write-Host "Output: $output"

# Test 2: pwsh -NoLogo -C Write-Host
Write-Host "`n--- Test 2: pwsh.exe -NoLogo -C Write-Host ---"
$before = Get-Date
$output = ssh.exe -4 -v -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes -i $keyFile -l jenkins 127.0.0.1 -p $port "pwsh.exe -NoLogo -C `"Write-Host 'f00'`"" 2>&1
$after = Get-Date
Write-Host "Exit: $LASTEXITCODE  Duration: $(($after-$before).TotalSeconds)s"
Write-Host "Output: $output"

# Test 3: Show what DefaultShell is in container
Write-Host "`n--- Test 3: check DefaultShell registry in container ---"
$output = docker exec test-2025 pwsh.exe -NoLogo -C "(Get-ItemProperty 'HKLM:\SOFTWARE\OpenSSH' -ErrorAction SilentlyContinue).DefaultShell" 2>&1
Write-Host "DefaultShell: $output"

# Test 4: check authorized_keys content
Write-Host "`n--- Test 4: authorized_keys in container ---"
$output = docker exec test-2025 pwsh.exe -NoLogo -C "Get-Content 'C:\Users\jenkins\.ssh\authorized_keys' -ErrorAction SilentlyContinue" 2>&1
Write-Host "authorized_keys: $output"

# Test 5: sshd log
Write-Host "`n--- Test 5: sshd log tail ---"
$output = docker exec test-2025 pwsh.exe -NoLogo -C "Get-Content 'C:\ProgramData\ssh\logs\sshd.log' -ErrorAction SilentlyContinue -Tail 20" 2>&1
Write-Host "sshd log: $output"
