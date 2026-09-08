$ErrorActionPreference = 'Continue'
$IMG = 'jenkins/ssh-agent:nanoserver-ltsc2025-jdk21'
$NAME = 'diag4-ssh-nano'
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

# helper: build a small .ps1 inside the container to avoid all quote-stripping issues
docker rm -fv $NAME 2>&1 | Out-Null
docker run --detach --tty --name=$NAME --publish-all $IMG "$PUB" | Out-Null
Start-Sleep -Seconds 20
$P = ((docker port $NAME 22) -split ':' | Select-Object -Last 1).Trim()
Write-Host "PORT=$P"

# Local helper script to copy into the container
$helper = @'
Write-Host ('pwsh_at_PSHOME_exists=' + (Test-Path 'C:\Program Files\PowerShell\pwsh.exe'))
Write-Host ('pwsh_resolved=' + (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source)
Write-Host ('cmd_exists=' + (Test-Path 'C:\Windows\System32\cmd.exe'))
Write-Host ('winps_exists=' + (Test-Path 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'))
Write-Host ('sftp_server_exists=' + (Test-Path 'C:\Program Files\OpenSSH\sftp-server.exe'))
Write-Host ('ssh_shellhost_exists=' + (Test-Path 'C:\Program Files\OpenSSH\ssh-shellhost.exe'))
Write-Host ('OpenSSH_dir_listing:')
Get-ChildItem 'C:\Program Files\OpenSSH' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
Write-Host '--- setting LogLevel DEBUG3 ---'
Add-Content -Path 'C:/ProgramData/ssh/sshd_config' -Value 'LogLevel DEBUG3'
Restart-Service sshd
Start-Sleep -Seconds 5
Write-Host ('sshd_status=' + (Get-Service sshd).Status)
Set-Content -Path 'C:/ProgramData/ssh/logs/sshd.log' -Value '' -ErrorAction SilentlyContinue
Write-Host 'log_reset_done'
'@
$helperPath = 'C:\Windows\Temp\diag4_helper.ps1'
Set-Content -Path $helperPath -Value $helper -Encoding ascii
docker cp $helperPath "${NAME}:C:/helper.ps1" | Out-Null
Write-Host '=== container helper output ==='
docker exec $NAME pwsh.exe -NoLogo -File C:/helper.ps1

$KEY = 'C:\Windows\Temp\diag4_id'
Set-Content -Path $KEY -Value $PRIV -Encoding ascii
icacls.exe $KEY /inheritance:r /grant:r "$($env:USERNAME):(R)" | Out-Null
$OUT = 'C:\Windows\Temp\ssh4_out.txt'
$ERR = 'C:\Windows\Temp\ssh4_err.txt'
Remove-Item -Force $OUT,$ERR -ErrorAction SilentlyContinue

Write-Host '=== ssh attempt: remote command "whoami" ==='
$sshArgs = @('-vv','-4','-i',$KEY,'-o','UserKnownHostsFile=NUL','-o','StrictHostKeyChecking=no','-o','ConnectTimeout=20','-o','BatchMode=yes','-l','jenkins','127.0.0.1','-p',"$P",'whoami')
$p = Start-Process -FilePath 'ssh.exe' -ArgumentList $sshArgs -NoNewWindow -PassThru -RedirectStandardOutput $OUT -RedirectStandardError $ERR
if (-not $p.WaitForExit(45000)) { Write-Host 'SSH_TIMED_OUT_45s'; Stop-Process -Id $p.Id -Force } else { Write-Host "SSH_EXIT=$($p.ExitCode)" }
Write-Host '--- ssh stdout ---'
Get-Content $OUT -ErrorAction SilentlyContinue
Write-Host '--- ssh stderr tail 12 ---'
Get-Content $ERR -ErrorAction SilentlyContinue | Select-Object -Last 12

Start-Sleep -Seconds 3
Write-Host '=== SSHD DEBUG3 LOG (full) ==='
docker exec $NAME pwsh.exe -NoLogo -Command 'Get-Content C:/ProgramData/ssh/logs/sshd.log'

Remove-Item -Force $KEY -ErrorAction SilentlyContinue
docker rm -fv $NAME 2>&1 | Out-Null
Write-Host 'DIAG4_DONE'
