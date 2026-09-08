# Test LogonUser with different logon types
# Also test starting sshd as jenkins via scheduled task (same-user fast path test)
$code = @"
using System;
using System.Runtime.InteropServices;

public class WinAuth2 {
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool LogonUser(string lpszUsername, string lpszDomain, string lpszPassword,
        int dwLogonType, int dwLogonProvider, out IntPtr phToken);

    [DllImport("kernel32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CloseHandle(IntPtr hObject);
}
"@
Add-Type -TypeDefinition $code -Language CSharp

$user = "jenkins"
$pass = "Jenkins2026!"
$host = $env:COMPUTERNAME

Write-Host "=== Testing LogonUser variants ==="
Write-Host "ComputerName: $host"

$types = @{
    2 = "LOGON32_LOGON_INTERACTIVE"
    3 = "LOGON32_LOGON_NETWORK"
    4 = "LOGON32_LOGON_BATCH"
    5 = "LOGON32_LOGON_SERVICE"
    8 = "LOGON32_LOGON_NETWORK_CLEARTEXT"
}

foreach ($logonType in $types.Keys) {
    $typeName = $types[$logonType]
    $token = [IntPtr]::Zero

    # Try with "."
    $result = [WinAuth2]::LogonUser($user, ".", $pass, $logonType, 0, [ref]$token)
    if ($result) {
        $err = 0
        Write-Host "${typeName} (domain='.'): SUCCESS, token=0x$('{0:X}' -f $token.ToInt64())"
        [WinAuth2]::CloseHandle($token) | Out-Null
    } else {
        $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-Host "${typeName} (domain='.'): FAILED err=$err"
    }

    # Try with hostname
    $token = [IntPtr]::Zero
    $result = [WinAuth2]::LogonUser($user, $host, $pass, $logonType, 0, [ref]$token)
    if ($result) {
        Write-Host "${typeName} (domain='$host'): SUCCESS"
        [WinAuth2]::CloseHandle($token) | Out-Null
    } else {
        $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-Host "${typeName} (domain='$host'): FAILED err=$err"
    }
}

Write-Host "`n=== Try schtasks with jenkins credentials ==="
# First stop sshd
$sshdPid = (Get-Process sshd -ErrorAction SilentlyContinue).Id
if ($sshdPid) {
    Stop-Process -Id $sshdPid -Force
    Start-Sleep -Seconds 1
    Write-Host "Stopped sshd PID $sshdPid"
}

# Create scheduled task running as jenkins
$tr = '"C:\Program Files\OpenSSH-Win64\sshd.exe" -f C:\ProgramData\ssh\sshd_config'
$createResult = schtasks.exe /create /tn 'sshd-jenkins' /tr $tr /sc once /st 00:00 /ru ".\jenkins" /rp "Jenkins2026!" /rl HIGHEST /f 2>&1
Write-Host "Create result: $createResult"

if ($createResult -match 'SUCCESS') {
    $runResult = schtasks.exe /run /tn 'sshd-jenkins' 2>&1
    Write-Host "Run result: $runResult"
    Start-Sleep -Seconds 3

    $sshdProcs = Get-Process sshd -ErrorAction SilentlyContinue
    Write-Host "sshd processes: $($sshdProcs.Count)"
    if ($sshdProcs) {
        Write-Host "sshd PIDs: $($sshdProcs.Id -join ', ')"
        # Verify the sshd is listening
        $listening = netstat -an 2>&1 | findstr ':22 '
        Write-Host "Port 22: $listening"
    }
} else {
    Write-Host "Failed to create task as jenkins"
    # Fall back to SYSTEM
    schtasks.exe /create /tn 'sshd-system' /tr $tr /sc once /st 00:00 /ru SYSTEM /rl HIGHEST /f 2>&1 | Write-Host
    schtasks.exe /run /tn 'sshd-system' 2>&1 | Write-Host
    Start-Sleep -Seconds 3
    Write-Host "Fallback to SYSTEM sshd: $(Get-Process sshd -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)"
}
