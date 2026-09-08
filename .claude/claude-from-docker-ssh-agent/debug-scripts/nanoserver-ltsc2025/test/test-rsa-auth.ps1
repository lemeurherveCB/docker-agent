icacls.exe C:\testkey.pem /inheritance:r /grant:r "Administrator:(R)" | Out-Null
Write-Host "Permissions set"
$r = ssh.exe -4 -v -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes -i C:\testkey.pem -l jenkins 127.0.0.1 -p 50053 "Write-Host hello" 2>&1
Write-Host "Exit: $LASTEXITCODE"
Write-Host "Output: $r"
