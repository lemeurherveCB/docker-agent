# Look for container/privilege-related config options in sshd.exe
Write-Host "=== Win32-OpenSSH registry keys ==="
Get-ChildItem 'HKLM:\SOFTWARE\OpenSSH' -ErrorAction SilentlyContinue | Format-List
Get-ItemProperty 'HKLM:\SOFTWARE\OpenSSH' -ErrorAction SilentlyContinue | Format-List

Write-Host "`n=== sshd_config current ==="
Get-Content 'C:\ProgramData\ssh\sshd_config' 2>&1

Write-Host "`n=== sshd.exe version ==="
& 'C:\Program Files\OpenSSH-Win64\sshd.exe' -V 2>&1

Write-Host "`n=== Check sshd.exe strings for 'container' or 'system' or 'token' ==="
$sshdPath = 'C:\Program Files\OpenSSH-Win64\sshd.exe'
$bytes = [System.IO.File]::ReadAllBytes($sshdPath)
$ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
# Find strings related to our issue
$patterns = @('container', 'ContainerAdmin', 'am_system', 'SeTcbPrivilege', 'logon_user', 'token_user', 'LOGON32', 'usermgr')
foreach ($p in $patterns) {
    $idx = $ascii.IndexOf($p, [System.StringComparison]::OrdinalIgnoreCase)
    if ($idx -ge 0) {
        Write-Host "FOUND '$p' at offset $idx"
    }
}

Write-Host "`n=== All string constants in sshd.exe mentioning 'system' (case insensitive) ==="
# Extract ASCII strings of length >= 10 that contain 'system' or 'logon'
$strings = @()
$current = ''
for ($i = 0; $i -lt $bytes.Length; $i++) {
    $b = $bytes[$i]
    if ($b -ge 0x20 -and $b -le 0x7E) {
        $current += [char]$b
    } else {
        if ($current.Length -ge 10) {
            if ($current -match 'system|logon|token|privilege|container|am_sys' ) {
                $strings += $current
            }
        }
        $current = ''
    }
}
$strings | Where-Object { $_ -match 'system|logon|token|privilege|container|am_sys' } | Select-Object -Unique | ForEach-Object { Write-Host "  $_" }

Write-Host "`n=== OpenSSH ssh_config man page / help for server options ==="
& 'C:\Program Files\OpenSSH-Win64\sshd.exe' -T 2>&1 | Select-String -Pattern 'privilege|container|logon|token' | Select-Object -First 20
