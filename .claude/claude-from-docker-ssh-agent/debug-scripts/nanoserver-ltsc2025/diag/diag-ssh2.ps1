$ErrorActionPreference = 'Continue'
$IMG = 'jenkins/ssh-agent:nanoserver-ltsc2025-jdk21'
$NAME = 'diag2-ssh-nano'
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
$portOut = docker port $NAME 22
$P = ($portOut -split ':' | Select-Object -Last 1).Trim()
Write-Host "PORT=$P"

Write-Host '=== sshd_config (non-comment lines) ==='
docker exec $NAME pwsh.exe -NoLogo -C 'Get-Content C:/ProgramData/ssh/sshd_config | Where-Object { $_.Trim() -ne "" -and $_ -notmatch "^\s*#" }'

Write-Host '=== C:/ProgramData/ssh/logs contents ==='
docker exec $NAME pwsh.exe -NoLogo -C 'if (Test-Path C:/ProgramData/ssh/logs) { Get-ChildItem C:/ProgramData/ssh/logs | Select-Object -ExpandProperty Name } else { "NO LOGS DIR" }'

Write-Host '=== sshd.log tail (before connect) ==='
docker exec $NAME pwsh.exe -NoLogo -C 'if (Test-Path C:/ProgramData/ssh/logs/sshd.log) { Get-Content C:/ProgramData/ssh/logs/sshd.log -Tail 60 } else { "NO sshd.log" }'

Write-Host '=== authorized_keys ACL ==='
docker exec $NAME pwsh.exe -NoLogo -C 'icacls C:/Users/jenkins/.ssh/authorized_keys'

Write-Host '=== jenkins user info ==='
docker exec $NAME pwsh.exe -NoLogo -C 'net user jenkins'

# --- ssh attempt with stderr to a FILE (avoid pipe buffering) ---
$KEY = 'C:\Windows\Temp\diag_id'
Set-Content -Path $KEY -Value $PRIV -Encoding ascii -NoNewline:$false
icacls.exe $KEY /inheritance:r /grant:r "$($env:USERNAME):(R)" | Out-Null
Write-Host '=== key file ACL ==='
icacls.exe $KEY

$OUT = 'C:\Windows\Temp\ssh_out.txt'
$ERR = 'C:\Windows\Temp\ssh_err.txt'
Remove-Item -Force $OUT,$ERR -ErrorAction SilentlyContinue

$sshArgs = @(
  '-vvv','-4',
  '-i', $KEY,
  '-o','UserKnownHostsFile=NUL',
  '-o','StrictHostKeyChecking=no',
  '-o','ConnectTimeout=20',
  '-o','BatchMode=yes',
  '-o','IdentitiesOnly=yes',
  '-l','jenkins','127.0.0.1','-p',$P,
  'pwsh.exe -NoLogo -C "Write-Host f00"'
)
Write-Host "=== running: ssh.exe $($sshArgs -join ' ') ==="
$p = Start-Process -FilePath 'ssh.exe' -ArgumentList $sshArgs -NoNewWindow -PassThru -RedirectStandardOutput $OUT -RedirectStandardError $ERR
if (-not $p.WaitForExit(45000)) { Write-Host 'SSH_TIMED_OUT_45s'; Stop-Process -Id $p.Id -Force; Start-Sleep 2 } else { Write-Host "SSH_EXIT=$($p.ExitCode)" }

Write-Host '=== SSH STDOUT FILE ==='
Get-Content $OUT -ErrorAction SilentlyContinue
Write-Host '=== SSH STDERR FILE (-vvv) ==='
Get-Content $ERR -ErrorAction SilentlyContinue

Write-Host '=== sshd.log tail (AFTER connect attempt) ==='
docker exec $NAME pwsh.exe -NoLogo -C 'if (Test-Path C:/ProgramData/ssh/logs/sshd.log) { Get-Content C:/ProgramData/ssh/logs/sshd.log -Tail 120 } else { "NO sshd.log" }'

Write-Host '=== sshd processes in container after attempt ==='
docker exec $NAME pwsh.exe -NoLogo -C 'Get-Process sshd -ErrorAction SilentlyContinue | Select-Object Id,ProcessName | Format-Table -AutoSize | Out-String'

Write-Host '=== docker logs ==='
docker logs $NAME 2>&1 | Select-Object -Last 20

Remove-Item -Force $KEY -ErrorAction SilentlyContinue
docker rm -fv $NAME 2>&1 | Out-Null
Write-Host 'DIAG2_DONE'
