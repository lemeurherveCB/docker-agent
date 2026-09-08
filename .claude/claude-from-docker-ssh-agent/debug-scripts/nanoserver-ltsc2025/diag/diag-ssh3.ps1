$ErrorActionPreference = 'Continue'
$IMG = 'jenkins/ssh-agent:nanoserver-ltsc2025-jdk21'
$NAME = 'diag3-ssh-nano'
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
$P = ((docker port $NAME 22) -split ':' | Select-Object -Last 1).Trim()
Write-Host "PORT=$P"

Write-Host '=== DefaultShell registry ==='
docker exec $NAME pwsh.exe -NoLogo -C 'Get-ItemProperty "HKLM:\SOFTWARE\OpenSSH" -ErrorAction SilentlyContinue | Format-List * | Out-String'

Write-Host '=== cmd.exe / powershell.exe presence ==='
docker exec $NAME pwsh.exe -NoLogo -C '"cmd.exe: " + (Test-Path C:/Windows/System32/cmd.exe); "pwsh: " + (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source; "wpsh: " + (Test-Path C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe)'

Write-Host '=== raise sshd LogLevel to DEBUG3 and restart ==='
docker exec $NAME pwsh.exe -NoLogo -C 'Add-Content -Path C:/ProgramData/ssh/sshd_config -Value "`nLogLevel DEBUG3"; Restart-Service sshd; Start-Sleep 5; (Get-Service sshd).Status'
Start-Sleep -Seconds 5
docker exec $NAME pwsh.exe -NoLogo -C 'Clear-Content C:/ProgramData/ssh/logs/sshd.log -ErrorAction SilentlyContinue; "log cleared"'

$KEY = 'C:\Windows\Temp\diag3_id'
Set-Content -Path $KEY -Value $PRIV -Encoding ascii
icacls.exe $KEY /inheritance:r /grant:r "$($env:USERNAME):(R)" | Out-Null
$OUT = 'C:\Windows\Temp\ssh3_out.txt'
$ERR = 'C:\Windows\Temp\ssh3_err.txt'
Remove-Item -Force $OUT,$ERR -ErrorAction SilentlyContinue

$sshArgs = @('-vv','-4','-i',$KEY,'-o','UserKnownHostsFile=NUL','-o','StrictHostKeyChecking=no','-o','ConnectTimeout=20','-o','BatchMode=yes','-l','jenkins','127.0.0.1','-p',$P,'pwsh.exe -NoLogo -C "Write-Host f00"')
Write-Host '=== ssh attempt ==='
$p = Start-Process -FilePath 'ssh.exe' -ArgumentList $sshArgs -NoNewWindow -PassThru -RedirectStandardOutput $OUT -RedirectStandardError $ERR
if (-not $p.WaitForExit(45000)) { Write-Host 'SSH_TIMED_OUT_45s'; Stop-Process -Id $p.Id -Force } else { Write-Host "SSH_EXIT=$($p.ExitCode)" }
Write-Host '=== ssh stdout ==='
Get-Content $OUT -ErrorAction SilentlyContinue
Write-Host '=== ssh stderr tail 25 ==='
Get-Content $ERR -ErrorAction SilentlyContinue | Select-Object -Last 25

Start-Sleep -Seconds 3
Write-Host '=== SSHD DEBUG3 LOG ==='
docker exec $NAME pwsh.exe -NoLogo -C 'Get-Content C:/ProgramData/ssh/logs/sshd.log -ErrorAction SilentlyContinue'

Write-Host '=== try a plain shell session (no command) ==='
$OUT2 = 'C:\Windows\Temp\ssh3b_out.txt'
$ERR2 = 'C:\Windows\Temp\ssh3b_err.txt'
$sshArgs2 = @('-vv','-4','-T','-i',$KEY,'-o','UserKnownHostsFile=NUL','-o','StrictHostKeyChecking=no','-o','ConnectTimeout=20','-o','BatchMode=yes','-l','jenkins','127.0.0.1','-p',$P,'whoami')
$p2 = Start-Process -FilePath 'ssh.exe' -ArgumentList $sshArgs2 -NoNewWindow -PassThru -RedirectStandardOutput $OUT2 -RedirectStandardError $ERR2
if (-not $p2.WaitForExit(45000)) { Write-Host 'SSH2_TIMED_OUT_45s'; Stop-Process -Id $p2.Id -Force } else { Write-Host "SSH2_EXIT=$($p2.ExitCode)" }
Write-Host '=== ssh2 stdout (whoami) ==='
Get-Content $OUT2 -ErrorAction SilentlyContinue
Write-Host '=== ssh2 stderr tail 15 ==='
Get-Content $ERR2 -ErrorAction SilentlyContinue | Select-Object -Last 15

Remove-Item -Force $KEY -ErrorAction SilentlyContinue
docker rm -fv $NAME 2>&1 | Out-Null
Write-Host 'DIAG3_DONE'
