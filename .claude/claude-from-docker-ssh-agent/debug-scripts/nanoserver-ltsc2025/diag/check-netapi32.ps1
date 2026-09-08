# Check netapi32.dll and LogonUser in nanoserver-ltsc2025

Write-Host "=== netapi32.dll info ==="
$f = 'C:\Windows\System32\netapi32.dll'
if (Test-Path $f) {
    $item = Get-Item $f
    Write-Host "Size: $($item.Length) bytes"
    $fv = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($f)
    Write-Host "Version: $($fv.FileVersion)"
    Write-Host "Description: $($fv.FileDescription)"
    Write-Host "ProductName: $($fv.ProductName)"
} else {
    Write-Host "NOT FOUND"
}

Write-Host "`n=== Test LogonUser with jenkins password ==="
$code = @"
using System;
using System.Runtime.InteropServices;
public class AuthTest {
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool LogonUser(string user, string domain, string pass,
        int logonType, int logonProvider, out IntPtr token);
}
"@
Add-Type -TypeDefinition $code -Language CSharp

$tok = [IntPtr]::Zero
$r = [AuthTest]::LogonUser("jenkins", ".", "Jenkins@2025Svc!", 2, 0, [ref]$tok)
$err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
Write-Host "LogonUser result: $r, error: $err"
Write-Host "  1355=NO_SUCH_DOMAIN, 1326=WRONG_PASSWORD, 1327=ACCOUNT_RESTRICTION, 0=SUCCESS"

Write-Host "`n=== Test LogonUser with LOGON_TYPE_NETWORK (3) ==="
$r2 = [AuthTest]::LogonUser("jenkins", ".", "Jenkins@2025Svc!", 3, 0, [ref]$tok)
$err2 = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
Write-Host "LogonUser(type=3) result: $r2, error: $err2"

Write-Host "`n=== Test LogonUser with empty password ==="
$r3 = [AuthTest]::LogonUser("jenkins", ".", "", 3, 0, [ref]$tok)
$err3 = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
Write-Host "LogonUser(empty pass) result: $r3, error: $err3"

Write-Host "`n=== Try Move-Item Force to replace netapi32.dll ==="
# First, check if we can try to replace netapi32.dll with a copy
$src = "$env:TEMP\netapi32_test.txt"
[System.IO.File]::WriteAllText($src, "test")
try {
    Copy-Item -Force $src $f -ErrorAction Stop
    Write-Host "COPY SUCCEEDED (file is replaceable!)"
    # Restore the original
    Copy-Item -Force 'C:\Windows\System32\netapi32.dll' 'C:\Windows\System32\netapi32.dll.bak' -ErrorAction SilentlyContinue
} catch {
    Write-Host "COPY FAILED: $_"
    Write-Host "(Protected file - can't overwrite)"
}
Remove-Item $src -ErrorAction SilentlyContinue
