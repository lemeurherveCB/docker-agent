$ErrorActionPreference = 'Continue'
$IMG = 'jenkins/ssh-agent:nanoserver-ltsc2025-jdk21'
$NAME = 'diag-ssh-nano'
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
Write-Host '=== docker run ==='
docker run --detach --tty --name=$NAME --publish-all $IMG "$PUB"
Start-Sleep -Seconds 20

Write-Host '=== docker logs (entrypoint output) ==='
docker logs $NAME 2>&1

Write-Host '=== port mapping ==='
$portOut = docker port $NAME 22
Write-Host $portOut
$P = ($portOut -split ':' | Select-Object -Last 1).Trim()
Write-Host "PORT=$P"

Write-Host '=== container: sshd service state ==='
docker exec $NAME pwsh.exe -NoLogo -C "Get-Service sshd,ssh-agent | Format-Table -AutoSize Name,Status,StartType | Out-String" 2>&1

Write-Host '=== container: sshd process ==='
docker exec $NAME pwsh.exe -NoLogo -C "Get-Process sshd -ErrorAction SilentlyContinue | Format-Table -AutoSize Id,ProcessName | Out-String" 2>&1

Write-Host '=== container: listening on 22 ==='
docker exec $NAME pwsh.exe -NoLogo -C "(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { \$_.LocalPort -eq 22 } | Format-Table -AutoSize LocalAddress,LocalPort | Out-String)" 2>&1

Write-Host '=== container: host keys ==='
docker exec $NAME pwsh.exe -NoLogo -C "Get-ChildItem C:/ProgramData/ssh -ErrorAction SilentlyContinue | Select-Object -Expand Name" 2>&1

Write-Host '=== container: authorized_keys ==='
docker exec $NAME pwsh.exe -NoLogo -C "Get-Content C:/Users/jenkins/.ssh/authorized_keys -ErrorAction SilentlyContinue" 2>&1

Write-Host '=== container: sshd_config (non-comment) ==='
docker exec $NAME pwsh.exe -NoLogo -C "Get-Content C:/ProgramData/ssh/sshd_config -ErrorAction SilentlyContinue | Where-Object { \$_ -notmatch '^\s*#' -and \$_ -notmatch '^\s*$' }" 2>&1

Write-Host '=== container: container IP ==='
$ip = docker inspect --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" $NAME
Write-Host "IP=$ip"

Write-Host '=== host: TCP connect test to 127.0.0.1:$P ==='
$client = New-Object System.Net.Sockets.TcpClient
try {
  $iar = $client.BeginConnect('127.0.0.1', [int]$P, $null, $null)
  $ok = $iar.AsyncWaitHandle.WaitOne(10000)
  Write-Host "TCP_CONNECT_127.0.0.1:${P}=$ok"
  if ($ok) {
    $client.EndConnect($iar)
    $stream = $client.GetStream()
    $stream.ReadTimeout = 10000
    $buf = New-Object byte[] 256
    try {
      $n = $stream.Read($buf, 0, 256)
      Write-Host ("BANNER({0} bytes)={1}" -f $n, ([System.Text.Encoding]::ASCII.GetString($buf, 0, $n)).Trim())
    } catch {
      Write-Host "BANNER_READ_FAILED: $($_.Exception.Message)"
    }
  }
} catch {
  Write-Host "TCP_CONNECT_FAILED: $($_.Exception.Message)"
} finally { $client.Close() }

Write-Host '=== host: TCP + banner directly to container IP:22 ==='
$client2 = New-Object System.Net.Sockets.TcpClient
try {
  $iar2 = $client2.BeginConnect($ip, 22, $null, $null)
  $ok2 = $iar2.AsyncWaitHandle.WaitOne(10000)
  Write-Host "TCP_CONNECT_${ip}:22=$ok2"
  if ($ok2) {
    $client2.EndConnect($iar2)
    $s2 = $client2.GetStream()
    $s2.ReadTimeout = 10000
    $b2 = New-Object byte[] 256
    try {
      $n2 = $s2.Read($b2, 0, 256)
      Write-Host ("BANNER_DIRECT({0} bytes)={1}" -f $n2, ([System.Text.Encoding]::ASCII.GetString($b2, 0, $n2)).Trim())
    } catch { Write-Host "BANNER_DIRECT_READ_FAILED: $($_.Exception.Message)" }
  }
} catch { Write-Host "TCP_CONNECT_DIRECT_FAILED: $($_.Exception.Message)" } finally { $client2.Close() }

Write-Host '=== host: ssh -vvv (60s cap, no LogLevel=quiet) ==='
$KEY = "$env:TEMP\diag_id_ed25519"
Set-Content -Path $KEY -Value $PRIV -Encoding ascii
icacls.exe $KEY /inheritance:r /grant:r "${env:USERNAME}:(R)" | Out-Null
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'ssh.exe'
$psi.Arguments = "-vvv -4 -i `"$KEY`" -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=20 -o BatchMode=yes -l jenkins 127.0.0.1 -p $P `"pwsh.exe -NoLogo -C `\`"Write-Host 'f00'`\`"`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$proc = [System.Diagnostics.Process]::Start($psi)
$so = $proc.StandardOutput.ReadToEndAsync()
$se = $proc.StandardError.ReadToEndAsync()
if (-not $proc.WaitForExit(60000)) { Write-Host 'SSH_TIMED_OUT_60s'; $proc.Kill(); $proc.WaitForExit() }
Write-Host "SSH_EXIT=$($proc.ExitCode)"
Write-Host "SSH_STDOUT=$($so.GetAwaiter().GetResult())"
Write-Host "SSH_STDERR_BEGIN"
Write-Host $se.GetAwaiter().GetResult()
Write-Host "SSH_STDERR_END"
Remove-Item -Force $KEY -ErrorAction SilentlyContinue

Write-Host '=== container: sshd log file if any ==='
docker exec $NAME pwsh.exe -NoLogo -C "if (Test-Path C:/ProgramData/ssh/logs) { Get-ChildItem C:/ProgramData/ssh/logs | ForEach-Object { Write-Host ('--- ' + \$_.FullName); Get-Content \$_.FullName -Tail 100 } } else { Write-Host 'no logs dir' }" 2>&1

Write-Host '=== container: recent System/Application events for sshd ==='
docker exec $NAME pwsh.exe -NoLogo -C "Get-WinEvent -FilterHashtable @{LogName='Application'} -MaxEvents 40 -ErrorAction SilentlyContinue | ForEach-Object { '{0} [{1}] {2}' -f \$_.TimeCreated, \$_.ProviderName, (\$_.Message -replace '\r?\n',' | ') }" 2>&1

Write-Host '=== docker logs (final) ==='
docker logs $NAME 2>&1

docker rm -fv $NAME 2>&1 | Out-Null
Write-Host 'DIAG_DONE'
