# Use CreateProcessWithLogonW to start sshd as jenkins (doesn't need SeServiceLogonRight)
# This simulates what happens when Docker USER=jenkins and ENTRYPOINT calls Start-Process

Write-Host "=== Ensure jenkins has password (may already be set) ==="
net user jenkins "Jenkins@2025Svc!" 2>&1

Write-Host "`n=== Stop all sshd ==="
Stop-Process -Name sshd -Force -ErrorAction SilentlyContinue
Stop-Service sshd -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
sc.exe config sshd obj= LocalSystem 2>&1 | Out-Null
Start-Sleep -Seconds 2

Write-Host "`n=== CreateProcessWithLogonW to run sshd as jenkins ==="
$code = @"
using System;
using System.Runtime.InteropServices;

public class ProcHelper {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb;
        public string lpReserved, lpDesktop, lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess, hThread;
        public int dwProcessId, dwThreadId;
    }
    const int CREATE_NO_WINDOW = 0x08000000;
    const int LOGON_WITH_PROFILE = 0x1;
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool CreateProcessWithLogonW(
        string userName, string domain, string password,
        int logonFlags, string appName, string cmdLine,
        int creationFlags, IntPtr env, string curDir,
        ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    public static int Run(string user, string domain, string pass, string cmdLine) {
        var si = new STARTUPINFO { cb = Marshal.SizeOf(typeof(STARTUPINFO)) };
        PROCESS_INFORMATION pi;
        if (CreateProcessWithLogonW(user, domain, pass, LOGON_WITH_PROFILE, null, cmdLine,
            CREATE_NO_WINDOW, IntPtr.Zero, null, ref si, out pi)) {
            return pi.dwProcessId;
        }
        return -Marshal.GetLastWin32Error();
    }
}
"@
Add-Type -TypeDefinition $code -Language CSharp

$sshdCmd = '"C:\Program Files\OpenSSH-Win64\sshd.exe" -f C:\ProgramData\ssh\sshd_config -E C:\sshd-jenkins.log'
$pid2 = [ProcHelper]::Run("jenkins", ".", "Jenkins@2025Svc!", $sshdCmd)
Write-Host "CreateProcessWithLogonW result: PID=$pid2 (negative = error code)"

if ($pid2 -gt 0) {
    Start-Sleep -Seconds 4
    $p = Get-Process sshd -ErrorAction SilentlyContinue
    Write-Host "sshd processes: $($p.Id -join ', ')"
    netstat -an | findstr ':22 '
} else {
    Write-Host "Failed to start sshd as jenkins. Trying scheduled task approach..."
    # Fallback: scheduled task as jenkins
    schtasks.exe /create /tn 'sshd-jenkins-test' `
        /tr '"C:\Program Files\OpenSSH-Win64\sshd.exe" -f C:\ProgramData\ssh\sshd_config -E C:\sshd-jenkins.log' `
        /sc once /st 00:00 /ru "jenkins" /rp "Jenkins@2025Svc!" /f 2>&1
    Write-Host "Task create: $LASTEXITCODE"
    schtasks.exe /run /tn 'sshd-jenkins-test' 2>&1
    Start-Sleep -Seconds 4
    $p = Get-Process sshd -ErrorAction SilentlyContinue
    Write-Host "sshd via task: $($p.Id -join ', ')"
}

if (-not (Get-Process sshd -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: sshd not running"
    exit 1
}

Write-Host "`n=== Test SSH as jenkins ==="
$b64Key = "LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNCUDR0KzA2aVZqRDM2bzdjczBiQngveXFIQVBJN2UyOCtJdUp3clU1VTBHQUFBQUpqUkZ3WXIwUmNHCkt3QUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQlA0dCswNmlWakQzNm83Y3MwYkJ4L3lxSEFQSTdlMjgrSXVKd3JVNVUwR0EKQUFBRUFwUEJ1bUE4WWhsYlhWSGMxek1IN2RlZy9aWUtlaDFJcmE1QlFodG1LcU9VL2kzN1RxSldNUGZxanR5elJzSEgvSwpvY0E4anQ3Yno0aTRuQ3RUbFRRWUFBQUFFR3BsYm10cGJuTXRkR1Z6ZEMxclpYa0JBZ01FQlE5PQotLS0tLUVORCBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0K"
$b64Key = "LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNCUDR0KzA2aVZqRDM2bzdjczBiQngveXFIQVBJN2UyOCtJdUp3clU1VTBHQUFBQUpqUkZ3WXIwUmNHCkt3QUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQlA0dCswNmlWakQzNm83Y3MwYkJ4L3lxSEFQSTdlMjgrSXVKd3JVNVUwR0EKQUFBRUFwUEJ1bUE4WWhsYlhWSGMxek1IN2RlZy9aWUtlaDFJcmE1QlFodG1LcU9VL2kzN1RxSldNUGZxanR5elJzSEgvSwpvY0E4anQ3Yno0aTRuQ3RUbFRRWUFBQUFFR3BsYm10cGJuTXRkR1Z6ZEMxclpYa0JBZ01FQlE9PQotLS0tLUVORCBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0K"
$keyFile = 'C:\test_jenkins_key'
[System.IO.File]::WriteAllBytes($keyFile, [System.Convert]::FromBase64String($b64Key))
icacls $keyFile /inheritance:r /grant:r "NT AUTHORITY\SYSTEM:(F)" /grant:r "ContainerAdministrator:(R)" 2>&1 | Out-Null

$sshBin = 'C:\Program Files\OpenSSH-Win64\ssh.exe'
$sshProc = Start-Process -FilePath $sshBin `
    -ArgumentList "-4 -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -i `"$keyFile`" -l jenkins 127.0.0.1 whoami" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput 'C:\cplw-out.txt' -RedirectStandardError 'C:\cplw-err.txt'
$sshProc | Wait-Process -Timeout 25 -ErrorAction SilentlyContinue
if (-not $sshProc.HasExited) { $sshProc.Kill(); Write-Host "TIMED OUT" }
else { Write-Host "SSH exit: $($sshProc.ExitCode)" }

Write-Host "STDOUT: $(Get-Content 'C:\cplw-out.txt' -ErrorAction SilentlyContinue)"

if ($sshProc.ExitCode -ne 0) {
    Write-Host "STDERR (last 12):"
    Get-Content 'C:\cplw-err.txt' -ErrorAction SilentlyContinue | Select-Object -Last 12
}

Write-Host "`n=== sshd-jenkins.log (key lines) ==="
Start-Sleep -Seconds 1
Get-Content 'C:\sshd-jenkins.log' -ErrorAction SilentlyContinue | Where-Object {
    $_ -match 'token|am_system|EqualSid|process|custom|fail|error|fork|Accepted|PATH|whoami'
} | Select-Object -Last 20

Stop-Process -Name sshd -Force -ErrorAction SilentlyContinue
schtasks.exe /delete /tn 'sshd-jenkins-test' /f 2>&1 | Out-Null
Remove-Item $keyFile -ErrorAction SilentlyContinue
Write-Host "DONE"
