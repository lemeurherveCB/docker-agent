# Fix: run sshd as jenkins user (PATH 2 in Win32-OpenSSH)
# Requires: disable LimitBlankPasswordUse + grant SeServiceLogonRight

Write-Host "=== Step 1: Allow blank-password accounts to run services ==="
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LimitBlankPasswordUse' -Value 0
Write-Host "LimitBlankPasswordUse = $(Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' LimitBlankPasswordUse)"

Write-Host "`n=== Step 2: Grant SeServiceLogonRight to jenkins via LsaAddAccountRights ==="
$lsaCode = @"
using System;
using System.Runtime.InteropServices;

public class LsaUtil {
    [StructLayout(LayoutKind.Sequential)]
    public struct LSA_UNICODE_STRING {
        public ushort Length;
        public ushort MaximumLength;
        public IntPtr Buffer;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct LSA_OBJECT_ATTRIBUTES {
        public int Length;
        public IntPtr RootDirectory;
        public IntPtr ObjectName;
        public int Attributes;
        public IntPtr SecurityDescriptor;
        public IntPtr SecurityQualityOfService;
    }
    [DllImport("advapi32.dll")]
    public static extern uint LsaOpenPolicy(ref LSA_UNICODE_STRING SystemName, ref LSA_OBJECT_ATTRIBUTES ObjAttr, int AccessMask, out IntPtr PolicyHandle);
    [DllImport("advapi32.dll")]
    public static extern uint LsaAddAccountRights(IntPtr PolicyHandle, byte[] AccountSid, LSA_UNICODE_STRING[] UserRights, ulong CountOfRights);
    [DllImport("advapi32.dll")]
    public static extern int LsaClose(IntPtr hnd);

    public static int AddRight(byte[] sidBytes, string right) {
        var attrs = new LSA_OBJECT_ATTRIBUTES { Length = Marshal.SizeOf(typeof(LSA_OBJECT_ATTRIBUTES)) };
        var sysName = new LSA_UNICODE_STRING();
        IntPtr pol = IntPtr.Zero;
        uint r = LsaOpenPolicy(ref sysName, ref attrs, 0x0800, out pol);
        if (pol == IntPtr.Zero) return (int)r;
        var str = new LSA_UNICODE_STRING {
            Length = (ushort)(right.Length * 2),
            MaximumLength = (ushort)(right.Length * 2 + 2),
            Buffer = Marshal.StringToHGlobalUni(right)
        };
        r = LsaAddAccountRights(pol, sidBytes, new[] { str }, 1);
        LsaClose(pol);
        Marshal.FreeHGlobal(str.Buffer);
        return (int)r;
    }
}
"@
Add-Type -TypeDefinition $lsaCode -Language CSharp

$acct = New-Object System.Security.Principal.NTAccount("jenkins")
$sid = $acct.Translate([System.Security.Principal.SecurityIdentifier])
$sidBytes = New-Object byte[]($sid.BinaryLength)
$sid.GetBinaryForm($sidBytes, 0)
$ret = [LsaUtil]::AddRight($sidBytes, "SeServiceLogonRight")
Write-Host "LsaAddAccountRights result: $ret (0 = success)"

Write-Host "`n=== Step 3: Stop sshd, configure to run as jenkins ==="
Stop-Process -Name sshd -Force -ErrorAction SilentlyContinue
Stop-Service sshd -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
Start-Sleep -Seconds 2

sc.exe config sshd obj= ".\jenkins" password= "" 2>&1
Start-Sleep -Seconds 1

Write-Host "`n=== Step 4: Start sshd as jenkins ==="
sc.exe start sshd 2>&1
Start-Sleep -Seconds 4

if (Get-Process sshd -ErrorAction SilentlyContinue) {
    Write-Host "sshd running OK as jenkins"
    sc.exe qc sshd 2>&1 | Where-Object { $_ -match 'ACCOUNT|BINARY' }
} else {
    Write-Host "sshd NOT running - checking event log"
    sc.exe start sshd 2>&1
}

Write-Host "`n=== Step 5: SSH as jenkins ==="
$b64Key = "LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNCUDR0KzA2aVZqRDM2bzdjczBiQngveXFIQVBJN2UyOCtJdUp3clU1VTBHQUFBQUpqUkZ3WXIwUmNHCkt3QUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQlA0dCswNmlWakQzNm83Y3MwYkJ4L3lxSEFQSTdlMjgrSXVKd3JVNVUwR0EKQUFBRUFwUEJ1bUE4WWhsYlhWSGMxek1IN2RlZy9aWUtlaDFJcmE1QlFodG1LcU9VL2kzN1RxSldNUGZxanR5elJzSEgvSwpvY0E4anQ3Yno0aTRuQ3RUbFRRWUFBQUFFR3BsYm10cGJuTXRkR1Z6ZEMxclpYa0JBZ01FQlE9PQotLS0tLUVORCBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0K"
$keyFile = 'C:\test_jenkins_key'
[System.IO.File]::WriteAllBytes($keyFile, [System.Convert]::FromBase64String($b64Key))
icacls $keyFile /inheritance:r /grant:r "NT AUTHORITY\SYSTEM:(F)" /grant:r "ContainerAdministrator:(R)" 2>&1 | Out-Null

$sshBin = 'C:\Program Files\OpenSSH-Win64\ssh.exe'
$proc = Start-Process -FilePath $sshBin `
    -ArgumentList "-4 -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -i `"$keyFile`" -l jenkins 127.0.0.1 whoami" `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput 'C:\jenkins-path2-out.txt' `
    -RedirectStandardError 'C:\jenkins-path2-err.txt'
$proc | Wait-Process -Timeout 25 -ErrorAction SilentlyContinue
if (-not $proc.HasExited) { $proc.Kill(); Write-Host "TIMED OUT" }
else { Write-Host "SSH exit: $($proc.ExitCode)" }

$stdout = Get-Content 'C:\jenkins-path2-out.txt' -ErrorAction SilentlyContinue
Write-Host "STDOUT (whoami): $stdout"

if ($proc.ExitCode -ne 0) {
    Write-Host "STDERR (last 12):"
    Get-Content 'C:\jenkins-path2-err.txt' -ErrorAction SilentlyContinue | Select-Object -Last 12
    Write-Host "`nsshd log (key lines):"
    Get-Content 'C:\ProgramData\ssh\logs\sshd.log' -ErrorAction SilentlyContinue | Where-Object {
        $_ -match 'token|system|equal|process|auth|fail|error|fork|Accepted'
    } | Select-Object -Last 15
}

Stop-Service sshd -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
Remove-Item $keyFile -ErrorAction SilentlyContinue
Write-Host "`nDONE"
