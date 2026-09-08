$ErrorActionPreference = 'Continue'
if (!(Test-Path "C:\tmp")) { New-Item -ItemType Directory -Path "C:\tmp" | Out-Null }
$keyFile = "C:\tmp\diagkey"
Remove-Item "$keyFile","$keyFile.pub" -Force -ErrorAction SilentlyContinue
& 'C:\Program Files\OpenSSH-Win64\ssh-keygen.exe' -t ed25519 -f $keyFile -N '""' -q
$pubKey = (Get-Content "$keyFile.pub") -join ''
Write-Host "PUBKEY: $pubKey"

docker rm -fv sshdiag 2>$null | Out-Null
docker run -d --name sshdiag -p 0:22 -e "JENKINS_AGENT_SSH_PUBKEY=$pubKey" jenkins/ssh-agent:nanoserver-ltsc2025-jdk21
Write-Host "=== waiting 25s ==="
Start-Sleep -Seconds 25
docker ps -a --filter name=sshdiag --format "{{.Names}} {{.Status}}"
$port = (docker port sshdiag 22).Split(':')[-1]
Write-Host "PORT: $port"
Write-Host "=== container logs ==="
docker logs sshdiag 2>&1
Write-Host "=== SSH ATTEMPT ==="
& 'C:\Program Files\OpenSSH-Win64\ssh.exe' -i $keyFile -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=30 -4 -l jenkins 127.0.0.1 -p $port "Write-Host hello" 2>&1
Write-Host "EXITCODE: $LASTEXITCODE"
Write-Host "=== logs dir ==="
docker exec sshdiag powershell.exe -Command "if (Test-Path 'C:\ProgramData\ssh\logs') { Get-ChildItem 'C:\ProgramData\ssh\logs' | Format-Table -AutoSize | Out-String } else { 'NO LOGS DIR' }" 2>&1
Write-Host "=== sshd.log ==="
docker exec sshdiag powershell.exe -Command "if (Test-Path 'C:\ProgramData\ssh\logs\sshd.log') { Get-Content 'C:\ProgramData\ssh\logs\sshd.log' } else { 'NO sshd.log' }" 2>&1
