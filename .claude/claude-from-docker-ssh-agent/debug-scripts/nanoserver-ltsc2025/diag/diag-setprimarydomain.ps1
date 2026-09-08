# End-to-end test of SetPrimaryDomain.ps1 inside a fresh nanoserver-ltsc2025-jdk21 container.
# Runs on the EC2 host (powershell.exe). Requires IMAGE and C:\work\SetPrimaryDomain.ps1.
# Shows whether the SYSTEM bootstrap works and whether registry blobs persist.
# Usage: powershell.exe -File diag-setprimarydomain.ps1

$ErrorActionPreference = 'Continue'
$image = 'jenkins/ssh-agent:nanoserver-ltsc2025-jdk21'

docker rm -f dbg 2>&1 | Out-Null
docker run -d --name dbg --user ContainerAdministrator $image pwsh.exe -Command 'Start-Sleep 3600' | Out-Null
Start-Sleep -Seconds 5

docker cp C:\work\SetPrimaryDomain.ps1 dbg:C:\SetPrimaryDomain.ps1
docker cp C:\work\verify-lsa-blobs.ps1 dbg:C:\verify-lsa-blobs.ps1

Write-Host "=== BEFORE: LSA policy blobs (via sysrun) ==="
# We have to run verify as SYSTEM too since ContainerAdministrator can't read HKLM\SECURITY
# Quick sysrun for verify:
$verifyCmd = 'C:\verify-sys.cmd'
docker exec dbg pwsh.exe -NoProfile -Command @"
  `$pwshExe = (Get-Command pwsh.exe).Source
  Set-Content 'C:\verify-sys.cmd' ("@echo off``r``n`"`$pwshExe`" -NoProfile -File C:\verify-lsa-blobs.ps1 > C:\verify.log 2>&1 && echo done > C:\verify.done``r``n")
  sc.exe create __verchk binPath= 'cmd.exe /c start `"`" /b C:\verify-sys.cmd' | Out-Null
  sc.exe start  __verchk | Out-Null
  sc.exe delete __verchk | Out-Null
  `$d = [datetime]::UtcNow.AddSeconds(30)
  while (!(Test-Path C:\verify.done) -and [datetime]::UtcNow -lt `$d) { Start-Sleep -Milliseconds 500 }
  if (Test-Path C:\verify.log) { Get-Content C:\verify.log }
  Remove-Item C:\verify.done,C:\verify.log,C:\verify-sys.cmd -Force -ErrorAction SilentlyContinue
"@

Write-Host "=== RUN SetPrimaryDomain.ps1 as ContainerAdministrator ==="
docker exec dbg pwsh.exe -NoProfile -File C:\SetPrimaryDomain.ps1
Write-Host "=== SCRIPT EXITCODE: $LASTEXITCODE ==="

Write-Host "=== AFTER: LSA policy blobs (via sysrun) ==="
docker exec dbg pwsh.exe -NoProfile -Command @"
  `$pwshExe = (Get-Command pwsh.exe).Source
  Set-Content 'C:\verify-sys.cmd' ("@echo off``r``n`"`$pwshExe`" -NoProfile -File C:\verify-lsa-blobs.ps1 > C:\verify.log 2>&1 && echo done > C:\verify.done``r``n")
  sc.exe create __verchk binPath= 'cmd.exe /c start `"`" /b C:\verify-sys.cmd' | Out-Null
  sc.exe start  __verchk | Out-Null
  sc.exe delete __verchk | Out-Null
  `$d = [datetime]::UtcNow.AddSeconds(30)
  while (!(Test-Path C:\verify.done) -and [datetime]::UtcNow -lt `$d) { Start-Sleep -Milliseconds 500 }
  if (Test-Path C:\verify.log) { Get-Content C:\verify.log }
  Remove-Item C:\verify.done,C:\verify.log,C:\verify-sys.cmd -Force -ErrorAction SilentlyContinue
"@

docker rm -f dbg 2>&1 | Out-Null
