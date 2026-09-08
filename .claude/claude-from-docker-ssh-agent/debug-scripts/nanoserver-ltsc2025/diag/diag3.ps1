$ErrorActionPreference = 'Continue'
$SSH = 'C:\Windows\System32\OpenSSH\ssh.exe'
$keyFile = "C:\tmp\diagkey"

# kill any hanging ssh clients started after 21:00
Get-Process ssh -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -gt (Get-Date).AddMinutes(-60) } | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host "=== Fix sshd_config: global DEBUG3 ==="
docker exec sshdiag pwsh.exe -NoProfile -Command @"
`$c = Get-Content 'C:\ProgramData\ssh\sshd_config'
`$c = `$c | Where-Object { `$_ -notmatch '^LogLevel DEBUG3' }
`$c = `$c -replace '^LogLevel.*','LogLevel DEBUG3'
if (-not (`$c -match 'LogLevel DEBUG3')) { `$c = @('LogLevel DEBUG3') + `$c }
Set-Content 'C:\ProgramData\ssh\sshd_config' -Value `$c
Get-Content 'C:\ProgramData\ssh\sshd_config' | Select-String 'LogLevel'
"@ 2>&1

Write-Host "=== sshd -T config test ==="
docker exec sshdiag pwsh.exe -NoProfile -Command "& 'C:\Program Files\OpenSSH-Win64\sshd.exe' -T 2>&1 | Select-String 'loglevel|authorizedkeysfile|subsystem|permitrootlogin'" 2>&1

Write-Host "=== restart sshd ==="
docker exec sshdiag pwsh.exe -NoProfile -Command "Restart-Service sshd; Start-Sleep 3; (Get-Service sshd).Status" 2>&1

$port = (docker port sshdiag 22 | Select-Object -First 1).Split(':')[-1]
Write-Host "PORT: $port"

Remove-Item C:\tmp\ssh_out.txt,C:\tmp\ssh_err.txt -Force -ErrorAction SilentlyContinue
$p = Start-Process -FilePath $SSH -ArgumentList @('-vvv','-i',$keyFile,'-o','StrictHostKeyChecking=no','-o','BatchMode=yes','-o','ConnectTimeout=20','-4','-l','jenkins','127.0.0.1','-p',$port,'Write-Host hello') -PassThru -NoNewWindow -RedirectStandardOutput C:\tmp\ssh_out.txt -RedirectStandardError C:\tmp\ssh_err.txt
Write-Host "=== waiting up to 45s for ssh ==="
if (-not $p.WaitForExit(45000)) { Write-Host "SSH CLIENT HUNG - killing"; $p.Kill() } else { Write-Host "SSH EXITED code=$($p.ExitCode)" }
Start-Sleep -Seconds 3
Write-Host "=== SSH STDOUT ==="
Get-Content C:\tmp\ssh_out.txt -ErrorAction SilentlyContinue
Write-Host "=== SSH STDERR (last 60) ==="
Get-Content C:\tmp\ssh_err.txt -ErrorAction SilentlyContinue | Select-Object -Last 60
Write-Host "=== SSHD LOG (DEBUG3) ==="
docker exec sshdiag pwsh.exe -NoProfile -Command "Get-Content 'C:\ProgramData\ssh\logs\sshd.log' -Tail 200" 2>&1
