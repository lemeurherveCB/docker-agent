$ErrorActionPreference = 'Continue'
$SSH = 'C:\Windows\System32\OpenSSH\ssh.exe'
$KEYGEN = 'C:\Windows\System32\OpenSSH\ssh-keygen.exe'
if (!(Test-Path "C:\tmp")) { New-Item -ItemType Directory -Path "C:\tmp" | Out-Null }
$keyFile = "C:\tmp\diagkey"
Remove-Item "$keyFile","$keyFile.pub" -Force -ErrorAction SilentlyContinue
& $KEYGEN -t ed25519 -f $keyFile -N '""' -q
$pubKey = (Get-Content "$keyFile.pub") -join ''
Write-Host "PUBKEY: $pubKey"

docker rm -fv sshdiag 2>$null | Out-Null
docker run -d --name sshdiag -p 0:22 -e "JENKINS_AGENT_SSH_PUBKEY=$pubKey" jenkins/ssh-agent:nanoserver-ltsc2025-jdk21 | Out-Null
Write-Host "=== waiting 25s ==="
Start-Sleep -Seconds 25
$port = (docker port sshdiag 22 | Select-Object -First 1).Split(':')[-1]
Write-Host "PORT: $port"

Write-Host "=== authorized_keys check ==="
docker exec sshdiag pwsh.exe -NoProfile -Command "Get-Content C:\Users\jenkins\.ssh\authorized_keys" 2>&1

Write-Host "=== ENABLE DEBUG3 ==="
docker exec sshdiag pwsh.exe -NoProfile -Command "Add-Content 'C:\ProgramData\ssh\sshd_config' 'LogLevel DEBUG3'; Restart-Service sshd; Start-Sleep 3; (Get-Service sshd).Status" 2>&1

Write-Host "=== sshd service account ==="
docker exec sshdiag pwsh.exe -NoProfile -Command "reg query 'HKLM\SYSTEM\CurrentControlSet\Services\sshd' /v ObjectName" 2>&1
docker exec sshdiag pwsh.exe -NoProfile -Command "sc.exe qc sshd" 2>&1

Write-Host "=== whoami /priv (ContainerAdministrator) ==="
docker exec sshdiag pwsh.exe -NoProfile -Command "whoami /priv" 2>&1
Write-Host "=== whoami /user ==="
docker exec sshdiag pwsh.exe -NoProfile -Command "whoami /user" 2>&1

Write-Host "=== SSH ATTEMPT (verbose) ==="
& $SSH -vvv -i $keyFile -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=30 -4 -l jenkins 127.0.0.1 -p $port "Write-Host hello" 2>&1 | Select-Object -Last 40
Write-Host "SSH EXITCODE: $LASTEXITCODE"

Start-Sleep -Seconds 3
Write-Host "=== DOCKER LOGS (tailed sshd.log) ==="
docker logs sshdiag 2>&1 | Select-Object -Last 250
