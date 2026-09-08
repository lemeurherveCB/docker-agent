# Run inside the container
Write-Host "=== Windows Event Log (OpenSSH) ==="
try {
    Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 10 -ErrorAction Stop | Format-List TimeCreated,Id,Message
} catch { Write-Host "OpenSSH/Operational log: $_" }

try {
    Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='OpenSSH*'} -MaxEvents 10 -ErrorAction Stop | Format-List TimeCreated,Id,Message
} catch { Write-Host "Application/OpenSSH events: $_" }

Write-Host "`n=== Check jenkins SID via PowerShell ==="
try {
    $acct = [System.Security.Principal.NTAccount]"jenkins"
    $sid = $acct.Translate([System.Security.Principal.SecurityIdentifier])
    Write-Host "jenkins SID: $($sid.Value)"
} catch { Write-Host "Failed to translate jenkins: $_" }

Write-Host "`n=== Check ContainerAdministrator SID ==="
try {
    $acct = [System.Security.Principal.NTAccount]"ContainerAdministrator"
    $sid = $acct.Translate([System.Security.Principal.SecurityIdentifier])
    Write-Host "ContainerAdministrator SID: $($sid.Value)"
} catch { Write-Host "Failed: $_" }

Write-Host "`n=== Test LogonUser for jenkins (via Win32 API reflection) ==="
$code = @"
using System;
using System.Runtime.InteropServices;
public class WinAuth {
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool LogonUser(string username, string domain, string password,
        int logonType, int logonProvider, out IntPtr token);
    [DllImport("kernel32.dll")]
    public static extern int GetLastError();
}
"@
try {
    Add-Type -TypeDefinition $code -Language CSharp
    $token = [IntPtr]::Zero
    # LOGON32_LOGON_NETWORK=3, LOGON32_PROVIDER_DEFAULT=0
    $result = [WinAuth]::LogonUser("jenkins", ".", "Jenkins2026!", 3, 0, [ref]$token)
    if ($result) {
        Write-Host "LogonUser SUCCESS, token=0x$('{0:X}' -f $token.ToInt64())"
    } else {
        $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-Host "LogonUser FAILED, error=$err (0x$('{0:X8}' -f $err))"
    }
} catch { Write-Host "LogonUser test failed: $_" }

Write-Host "`n=== Check jenkins user SAM entry ==="
net user jenkins 2>&1

Write-Host "`n=== Start sshd -d and connect (debug output) ==="
# Remove old log
Remove-Item C:\sshd-debug.log -ErrorAction SilentlyContinue

# Start sshd in debug mode on same port (stop service first)
Stop-Service sshd -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$sshdProc = Start-Process -FilePath 'C:\Program Files\OpenSSH-Win64\sshd.exe' `
    -ArgumentList '-d -p 22 -f C:\ProgramData\ssh\sshd_config' `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput C:\sshd-debug-stdout.log `
    -RedirectStandardError C:\sshd-debug.log

Start-Sleep -Seconds 2
Write-Host "sshd -d started, PID=$($sshdProc.Id)"

Write-Host "`n=== Connection attempt output captured to C:\sshd-debug.log ==="
Write-Host "Ready for connection..."

# Now try to connect to ourselves (sshd listens on 22 but from the container perspective...)
# Actually we can't SSH from inside container to itself easily, so just wait briefly for external connection
Start-Sleep -Seconds 15
Write-Host "Capture done"

$sshdProc.Kill()
Write-Host "`n=== sshd debug output ==="
Get-Content C:\sshd-debug.log -ErrorAction SilentlyContinue
