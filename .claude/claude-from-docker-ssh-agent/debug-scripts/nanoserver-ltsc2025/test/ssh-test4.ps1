$keyFile = 'C:\jenkins_key.pem'
$port = '49913'

Write-Host "=== Testing SSH after LimitBlankPasswordUse=0 ==="
$proc = Start-Process -FilePath 'ssh.exe' `
    -ArgumentList "-4 -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -i $keyFile -l jenkins 127.0.0.1 -p $port `"echo hello123`"" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput C:\ssh-out4.txt `
    -RedirectStandardError C:\ssh-err4.txt

$proc | Wait-Process -Timeout 20 -ErrorAction SilentlyContinue
if (-not $proc.HasExited) {
    $proc.Kill()
    Write-Host "TIMED OUT after 20s"
} else {
    Write-Host "Exit code: $($proc.ExitCode)"
}
Write-Host "STDOUT:"
Get-Content C:\ssh-out4.txt -ErrorAction SilentlyContinue
Write-Host "STDERR:"
Get-Content C:\ssh-err4.txt -ErrorAction SilentlyContinue

Write-Host "`n=== Same test with pwsh command ==="
$proc2 = Start-Process -FilePath 'ssh.exe' `
    -ArgumentList "-4 -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -i $keyFile -l jenkins 127.0.0.1 -p $port `"pwsh.exe -NoLogo -C 'Write-Host f00'`"" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput C:\ssh-out4b.txt `
    -RedirectStandardError C:\ssh-err4b.txt

$proc2 | Wait-Process -Timeout 20 -ErrorAction SilentlyContinue
if (-not $proc2.HasExited) {
    $proc2.Kill()
    Write-Host "TIMED OUT after 20s"
} else {
    Write-Host "Exit code: $($proc2.ExitCode)"
}
Write-Host "STDOUT:"
Get-Content C:\ssh-out4b.txt -ErrorAction SilentlyContinue
Write-Host "STDERR:"
Get-Content C:\ssh-err4b.txt -ErrorAction SilentlyContinue
