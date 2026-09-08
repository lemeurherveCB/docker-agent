$ErrorActionPreference = 'Continue'
$IMG = 'jenkins/ssh-agent:nanoserver-ltsc2025-jdk21'
$NAME = 'diag5-ssh-nano'
$PUB = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE/i37TqJWMPfqjtyzRsHH/KocA8jt7bz4i4nCtTlTQY jenkins-test-key'
$PRIV = @"
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBP4t+06iVjD36o7cs0bBx/yqHAPI7e28+IuJwrU5U0GAAAAJjRFwYr0RcG
KwAAAAtzc2gtZWQyNTUxOQAAACBP4t+06iVjD36o7cs0bBx/yqHAPI7e28+IuJwrU5U0GA
AAAEApPBumA8YhlbXVHc1zMH7deg/ZYKeh1Ira5BQhtmKqOU/i37TqJWMPfqjtyzRsHH/K
ocA8jt7bz4i4nCtTlTQYAAAAEGplbmtpbnMtdGVzdC1rZXkBAgMEBQ==
-----END OPENSSH PRIVATE KEY-----
"@

docker rm -fv $NAME 2>&1 | Out-Null
docker run --detach --tty --name=$NAME --publish-all $IMG "$PUB" | Out-Null
Start-Sleep -Seconds 20
$IP = docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $NAME
Write-Host "CONTAINER_IP=$IP"

$helper = @'
Write-Host '--- OpenSSH-Win64 listing ---'
Get-ChildItem 'C:\Program Files\OpenSSH-Win64' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
Write-Host '--- launching sshd -ddd on port 2222 ---'
$exe = 'C:\Program Files\OpenSSH-Win64\sshd.exe'
Start-Process -FilePath $exe -ArgumentList '-ddd','-p','2222','-E','C:\sshd-debug.log' -NoNewWindow
Start-Sleep -Seconds 4
Write-Host ('debug_sshd_running=' + [bool](Get-Process sshd -ErrorAction SilentlyContinue).Count)
'@
$helperPath = 'C:\Windows\Temp\diag5_helper.ps1'
Set-Content -Path $helperPath -Value $helper -Encoding ascii
docker cp $helperPath "${NAME}:C:/helper5.ps1" | Out-Null
Write-Host '=== container helper output ==='
docker exec $NAME pwsh.exe -NoLogo -File C:/helper5.ps1

$KEY = 'C:\Windows\Temp\diag5_id'
Set-Content -Path $KEY -Value $PRIV -Encoding ascii
icacls.exe $KEY /inheritance:r /grant:r "$($env:USERNAME):(R)" | Out-Null
$OUT = 'C:\Windows\Temp\ssh5_out.txt'
$ERR = 'C:\Windows\Temp\ssh5_err.txt'
Remove-Item -Force $OUT,$ERR -ErrorAction SilentlyContinue

Write-Host "=== ssh to ${IP}:2222 (debug sshd) running 'whoami' ==="
$sshArgs = @('-v','-4','-i',$KEY,'-o','UserKnownHostsFile=NUL','-o','StrictHostKeyChecking=no','-o','ConnectTimeout=20','-o','BatchMode=yes','-l','jenkins',$IP,'-p','2222','whoami')
$p = Start-Process -FilePath 'ssh.exe' -ArgumentList $sshArgs -NoNewWindow -PassThru -RedirectStandardOutput $OUT -RedirectStandardError $ERR
if (-not $p.WaitForExit(45000)) { Write-Host 'SSH_TIMED_OUT_45s'; Stop-Process -Id $p.Id -Force } else { Write-Host "SSH_EXIT=$($p.ExitCode)" }
Write-Host '--- ssh stdout ---'
Get-Content $OUT -ErrorAction SilentlyContinue
Write-Host '--- ssh stderr tail 10 ---'
Get-Content $ERR -ErrorAction SilentlyContinue | Select-Object -Last 10

Start-Sleep -Seconds 3
Write-Host '=== SSHD -ddd SERVER LOG (last 90 lines) ==='
docker exec $NAME pwsh.exe -NoLogo -Command 'if (Test-Path C:/sshd-debug.log) { Get-Content C:/sshd-debug.log -Tail 90 } else { Write-Output NO_DEBUG_LOG }'

Remove-Item -Force $KEY -ErrorAction SilentlyContinue
docker rm -fv $NAME 2>&1 | Out-Null
Write-Host 'DIAG5_DONE'
