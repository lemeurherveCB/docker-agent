Write-Host "=== sshd service account ==="
sc.exe qc sshd 2>&1

Write-Host "`n=== sshd log ==="
Get-Content 'C:\ProgramData\ssh\logs\sshd.log' -ErrorAction SilentlyContinue -Tail 30

Write-Host "`n=== Windows Event Log - OpenSSH ==="
try {
    Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 10 -ErrorAction Stop | Format-List TimeCreated,Id,Message
} catch {
    Write-Host "No OpenSSH/Operational log: $_"
}

Write-Host "`n=== Application Event Log (OpenSSH) ==="
try {
    Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='OpenSSH*'} -MaxEvents 10 -ErrorAction Stop | Format-List TimeCreated,Id,Message
} catch {
    Write-Host "No Application/OpenSSH events: $_"
}

Write-Host "`n=== Current registry LimitBlankPasswordUse ==="
Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name LimitBlankPasswordUse -ErrorAction SilentlyContinue

Write-Host "`n=== Test: set jenkins password and retry ==="
net user jenkins 'Jenkins2026!' /PASSWORDREQ:YES
net user jenkins

Write-Host "`n=== Now retry SSH with new password set ==="
$keyFile = 'C:\jenkins_key.pem'
$port = '49913'
$proc = Start-Process -FilePath 'ssh.exe' `
    -ArgumentList "-4 -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -i $keyFile -l jenkins 127.0.0.1 -p $port `"echo hello123`"" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput C:\ssh-diag-out.txt `
    -RedirectStandardError C:\ssh-diag-err.txt

$proc | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue
if (-not $proc.HasExited) { $proc.Kill(); Write-Host "TIMED OUT" } else { Write-Host "Exit: $($proc.ExitCode)" }
Get-Content C:\ssh-diag-out.txt -ErrorAction SilentlyContinue
Get-Content C:\ssh-diag-err.txt -ErrorAction SilentlyContinue
