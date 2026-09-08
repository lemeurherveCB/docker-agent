# Test LogonUser with different domain values and approaches

$code = @"
using System;
using System.Runtime.InteropServices;
public class AuthTest2 {
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool LogonUser(string user, string domain, string pass,
        int logonType, int logonProvider, out IntPtr token);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
    public static extern bool CloseHandle(IntPtr handle);
}
"@
Add-Type -TypeDefinition $code -Language CSharp

$hostname = $env:COMPUTERNAME
Write-Host "COMPUTERNAME: $hostname"

foreach ($domain in @(".", $hostname, "localhost", "WORKGROUP", "")) {
    $tok = [IntPtr]::Zero
    $r = [AuthTest2]::LogonUser("jenkins", $domain, "Jenkins@2025Svc!", 3, 0, [ref]$tok)
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Write-Host "LogonUser(domain='$domain') = $r, err=$err"
    if ($r) { [AuthTest2]::CloseHandle($tok) | Out-Null }
}

Write-Host "`n=== Try LOGON32_LOGON_NEW_CREDENTIALS (9) ==="
$tok2 = [IntPtr]::Zero
$r2 = [AuthTest2]::LogonUser("jenkins", ".", "Jenkins@2025Svc!", 9, 0, [ref]$tok2)
$err2 = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
Write-Host "LogonUser(type=9 NewCredentials) = $r2, err=$err2"
if ($r2) { [AuthTest2]::CloseHandle($tok2) | Out-Null }

Write-Host "`n=== Try seclogon service directly (runas) ==="
# Check if runas.exe is available
if (Test-Path "C:\Windows\System32\runas.exe") {
    Write-Host "runas.exe FOUND"
} else {
    Write-Host "runas.exe NOT FOUND"
}
