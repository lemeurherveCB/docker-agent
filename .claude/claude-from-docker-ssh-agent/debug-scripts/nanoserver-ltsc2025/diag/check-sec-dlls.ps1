# Compare security DLLs between nanoserver and servercore
$dlls = @("msv1_0.dll", "samlib.dll", "samsrv.dll", "lsasrv.dll", "secur32.dll", "ntlmshared.dll", "wdigest.dll")
foreach ($dll in $dlls) {
    $f = "C:\Windows\System32\$dll"
    if (Test-Path $f) {
        $sz = (Get-Item $f).Length
        Write-Host "FOUND $dll size=$sz"
    } else {
        Write-Host "MISSING $dll"
    }
}

Write-Host "`n=== Try LogonUser with existing jenkins user ==="
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
$r = [AuthTest]::LogonUser("jenkins", ".", "Jenkins@2025Svc!", 3, 0, [ref]$tok)
$err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
Write-Host "LogonUser(jenkins) = $r, err=$err"

# Try with ContainerAdministrator
$r2 = [AuthTest]::LogonUser("ContainerAdministrator", ".", "", 3, 0, [ref]$tok)
$err2 = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
Write-Host "LogonUser(ContainerAdmin) = $r2, err=$err2"
