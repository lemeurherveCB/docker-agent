$key = @"
-----BEGIN RSA PRIVATE KEY-----
MIIEoQIBAAKCAQEAvnRN27LdPPQq2OH3GiFFGWX/SH5TCPVePLR21ngMFV8nAthX
gYrFkRi/t+Wafe3ByTu2XYUDlXHKGIPIoAKo4gz5dIjUFfoac1ZuCDIbEiqPEjkk
4tkfc2qr/BnIZsOYQi4Mbu+Z40VZEsAQU7eBinnZaHE1qGMHjS1xfrRtp2rdeO1E
Bz92FJ8dfnkUnohTXo3qPVSFGIPbh7UKEoKcyCosRO1P41iWD1rVsH1SLLXYAh2t
49L7IPiplg09Dep6H47LyQVbxU9eXY8yMtUrRuwEk9IUX/IqpxNhk5hngHPP3Jjs
P0hyyrYSPkZlbs3izd9kk3y09Wn/ElHidiEk0QIBJQKCAQEAlUZmiZoHWUnAt9Oz
1jXAiYdLi9ih8kPGZu5PTia9XNvgTlaJxmXZHrKIbYpyK1l8NfCIBBwlZ0tZNc8S
3kdGGPVpkrBu4MryIwxkFELyn4kkB104lh/MiuTnqeqx1AEWeQ9V2mjEuQzXHIiy
2dUEqs40x3tTkdETwa3/AnG9upCsS8DpUmBa50hHvkc8pfmDrCbDAB7QjrgxAv7N
TjZQz1BslDnqULBs0weqD/YG60Vxdbu8ULHcMKYHmlk06a2lxF2A+CbvC+eLyD5B
+YHsD2CnpNhmBxLXfjnKuMhT6ybtop1hZW4zy0jLsyvAgM/kSb/iH9XJ17nfdlMm
NChQcQKBgQDvKs+81jDhoP+fZXi7bnVwlo2UzuTXNkUO1fLCFHWpJXMXu4wY6iMY
klEjXmN68Ijj0n3Enw7yM4/HBcnvRlw78zbDbKxwz5WRVc8w4/Ct4z8TX9Il1srR
Qa9vPhju8KazY1XxNMidMJmcR6cjG7glzKorE9faHc9aIskPP93y1wKBgQDL288f
tk0F/RcikCnfq8Ligm3GkZfP7lyf0T9lXHg0Qe9d3esvVHe02blMGm0vgsKy4Aip
jlyyM8ExI5yF2zUbOqLxDhWWqL6EnlYXEI4s5h/4AJOPrERGdOU/Ix7G312mqcmi
FlRVug8II64O7IgVU6pWyckOSMf6llyH/ItYlwKBgDotAhktLnwSZ7EmhSasKmd+
kSQyU1bxhmtkeVHNoBRjDiheDVIrHUsqgnBjEUdq8N14Y8gLA6KymJgx1yxdOQep
3ONtdg2aRvnWmi58olPPfguhr6hW12NVKqxbNn9PSyS3TEGXN7eIXLdPswiKM7Yq
3Ui/ozUOK4SgrXJpey07AoGAG4xoGQrMI2dj/cB0XH7+qPzeZvEUg+Hw11OgyIIe
FOZQx37al7F39dg7ooAcl7e5ch5GXBooM8HN/7i0SXCmT8mnUQHnPd9zsQ56ViTU
8U+Hx5FgDH8QJTJkKyBr8Vx0cHfPI73UC5WvARmUD9rGSBI5nQaC9BesUkuro6yB
iIMCgYAnlf3vd9/s8izGoHH1K2MJgGQT06Wn4ESjKpqqayqiXHccHGgeXeAiONa1
uiWcmBF4XtMTVXUGcS6DCm/jf/4JDI8B1eJCVQKLbZXZbENWnptDtj098NTt9NdV
TUwLP4n7pK4J2sCIs6fRD5kEYms4BnddXeRuI2fGZHGH70Ci/Q==
-----END RSA PRIVATE KEY-----
"@

$port = (docker port pester-jenkins-ssh-agent-nanoserver-ltsc2025-jdk21 22 2>$null) -replace '.*:',''
if (-not $port) { Write-Host "ERROR: no container port"; exit 1 }
Write-Host "Container port: $port"

$keyFile = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($keyFile, $key)
icacls $keyFile /inheritance:r /grant:r "${env:USERNAME}:(R)" | Out-Null

Write-Host "=== SSH attempt (verbose) ==="
& "C:\Windows\System32\OpenSSH\ssh.exe" -v `
  -i $keyFile `
  -o UserKnownHostsFile=NUL `
  -o StrictHostKeyChecking=no `
  -o ConnectTimeout=15 `
  -o BatchMode=yes `
  -l jenkins localhost -p $port `
  "Write-Host hello_from_container"
Write-Host "exit: $LASTEXITCODE"

Write-Host "=== sshd.log last 30 lines ==="
docker exec pester-jenkins-ssh-agent-nanoserver-ltsc2025-jdk21 pwsh.exe -NonInteractive -C '$lines = Get-Content C:/ProgramData/ssh/logs/sshd.log -ErrorAction SilentlyContinue; if ($lines) { $lines | Select-Object -Last 30 } else { Write-Host "LOG EMPTY" }'

Remove-Item $keyFile -Force
