# Test LogonUser in servercore container
net user testauth "TestAuth@2025!" /ADD /ACTIVE:YES /EXPIRES:NEVER /PASSWORDREQ:YES 2>&1

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
Write-Host "LogonUser interactive (2):"
$r = [AuthTest]::LogonUser("testauth", ".", "TestAuth@2025!", 2, 0, [ref]$tok)
Write-Host "Result: $r, error: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"

Write-Host "LogonUser network (3):"
$r = [AuthTest]::LogonUser("testauth", ".", "TestAuth@2025!", 3, 0, [ref]$tok)
Write-Host "Result: $r, error: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"

net user testauth /DELETE 2>&1
