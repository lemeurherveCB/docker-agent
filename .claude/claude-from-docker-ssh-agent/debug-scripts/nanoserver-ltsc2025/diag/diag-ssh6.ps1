$ErrorActionPreference = 'Continue'
$IMG = 'jenkins/ssh-agent:nanoserver-ltsc2025-jdk21'
$NAME = 'diag6-ssh-nano'
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

$helper = @'
Write-Host ('sshd_service_account=' + (Get-CimInstance Win32_Service -Filter "Name='sshd'" -ErrorAction SilentlyContinue).StartName)
Add-Content -Path 'C:/ProgramData/ssh/sshd_config' -Value 'LogLevel DEBUG3'
Stop-Service sshd -Force
Start-Sleep -Seconds 3
Remove-Item -Force 'C:/ProgramData/ssh/logs/sshd6.log' -ErrorAction SilentlyContinue
Start-Service sshd
Start-Sleep -Seconds 5
Write-Host ('sshd_status=' + (Get-Service sshd).Status)
Write-Host ('log_size_before=' + (Get-Item 'C:/ProgramData/ssh/logs/sshd.log' -ErrorAction SilentlyContinue).Length)
'@
Set-Content -Path 'C:\Windows\Temp\diag6_helper.ps1' -Value $helper -Encoding ascii
docker cp 'C:\Windows\Temp\diag6_helper.ps1' "${NAME}:C:/helper6.ps1" | Out-Null
Write-Host '=== container helper output ==='
docker exec $NAME pwsh.exe -NoLogo -File C:/helper6.ps1

$KEY = 'C:\Windows\Temp\diag6_id'
Set-Content -Path $KEY -Value $PRIV -Encoding ascii
icacls.exe $KEY /inheritance:r /grant:r "$($env:USERNAME):(R)" | Out-Null
$OUT = 'C:\Windows\Temp\ssh6_out.txt'
$ERR = 'C:\Windows\Temp\ssh6_err.txt'
Remove-Item -Force $OUT,$ERR -ErrorAction SilentlyContinue

Write-Host '=== ssh (service sshd, DEBUG3) running whoami ==='
$sshArgs = @('-v','-4','-i',$KEY,'-o','UserKnownHostsFile=NUL','-o','StrictHostKeyChecking=no','-o','ConnectTimeout=20','-o','BatchMode=yes','-l','jenkins','127.0.0.1','-p',"$P",'whoami')
$p = Start-Process -FilePath 'ssh.exe' -ArgumentList $sshArgs -NoNewWindow -PassThru -RedirectStandardOutput $OUT -RedirectStandardError $ERR
if (-not $p.WaitForExit(45000)) { Write-Host 'SSH_TIMED_OUT_45s'; Stop-Process -Id $p.Id -Force } else { Write-Host "SSH_EXIT=$($p.ExitCode)" }
Write-Host '--- ssh stdout ---'
Get-Content $OUT -ErrorAction SilentlyContinue
Write-Host '--- ssh stderr tail 6 ---'
Get-Content $ERR -ErrorAction SilentlyContinue | Select-Object -Last 6

Start-Sleep -Seconds 4
Write-Host '=== service sshd.log tail 60 ==='
docker exec $NAME pwsh.exe -NoLogo -Command 'Get-Content C:/ProgramData/ssh/logs/sshd.log -Tail 60'

Remove-Item -Force $KEY -ErrorAction SilentlyContinue
docker rm -fv $NAME 2>&1 | Out-Null
Write-Host 'DIAG6_DONE'
