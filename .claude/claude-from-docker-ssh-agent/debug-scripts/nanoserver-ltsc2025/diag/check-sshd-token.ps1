# Diagnose sshd token and privileges, test SeTcbPrivilege and LsaRegisterLogonProcess
Write-Host "=== whoami (this docker exec process) ==="
whoami.exe 2>&1

Write-Host "`n=== whoami /priv (this docker exec process) ==="
whoami.exe /priv 2>&1

Write-Host "`n=== whoami /groups (this docker exec process) ==="
whoami.exe /groups 2>&1 | Select-Object -First 20

Write-Host "`n=== sshd process token check via Win32 API ==="
$code = @"
using System;
using System.Runtime.InteropServices;
using System.ComponentModel;

public class TokenInfo {
    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool CheckTokenMembership(IntPtr TokenHandle, IntPtr SidToCheck, out bool IsMember);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool AllocateAndInitializeSid(ref SID_IDENTIFIER_AUTHORITY pIdentifierAuthority,
        byte nSubAuthorityCount, uint nSubAuthority0, uint nSubAuthority1, uint nSubAuthority2, uint nSubAuthority3,
        uint nSubAuthority4, uint nSubAuthority5, uint nSubAuthority6, uint nSubAuthority7, out IntPtr pSid);

    [DllImport("advapi32.dll")]
    public static extern IntPtr FreeSid(IntPtr pSid);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentProcess();

    [StructLayout(LayoutKind.Sequential)]
    public struct SID_IDENTIFIER_AUTHORITY {
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=6)]
        public byte[] Value;
    }

    public static bool IsCurrentProcessSystem() {
        IntPtr currentToken = IntPtr.Zero;
        IntPtr systemSid = IntPtr.Zero;
        bool isSystem = false;

        try {
            var ntAuth = new SID_IDENTIFIER_AUTHORITY { Value = new byte[] { 0, 0, 0, 0, 0, 5 } }; // SECURITY_NT_AUTHORITY
            AllocateAndInitializeSid(ref ntAuth, 1, 18, 0, 0, 0, 0, 0, 0, 0, out systemSid); // SECURITY_LOCAL_SYSTEM_RID=18

            // CheckTokenMembership with null = current process token
            CheckTokenMembership(IntPtr.Zero, systemSid, out isSystem);
            return isSystem;
        } finally {
            if (systemSid != IntPtr.Zero) FreeSid(systemSid);
        }
    }

    public static string GetCurrentUserSid() {
        IntPtr token = IntPtr.Zero;
        try {
            if (!OpenProcessToken(GetCurrentProcess(), 0x0008, out token)) // TOKEN_QUERY
                return "OpenProcessToken failed: " + new Win32Exception(Marshal.GetLastWin32Error()).Message;
            return "Token handle opened OK";
        } finally {
            if (token != IntPtr.Zero) {
                var k32 = typeof(System.IO.File).Assembly;
                // just return
            }
        }
    }
}
"@
try {
    Add-Type -TypeDefinition $code -Language CSharp
    Write-Host "Am SYSTEM (this process)? $([TokenInfo]::IsCurrentProcessSystem())"
} catch {
    Write-Host "TokenInfo type error: $_"
}

Write-Host "`n=== Test LsaRegisterLogonProcess (requires SeTcbPrivilege) ==="
$lsaCode = @"
using System;
using System.Runtime.InteropServices;

public class LsaTest {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
    public struct LSA_STRING {
        public ushort Length;
        public ushort MaximumLength;
        public string Buffer;
    }

    [DllImport("secur32.dll")]
    public static extern int LsaRegisterLogonProcess(ref LSA_STRING LogonProcessName, out IntPtr LsaHandle, out ulong SecurityMode);

    [DllImport("secur32.dll")]
    public static extern int LsaDeregisterLogonProcess(IntPtr LsaHandle);

    public static string Test() {
        var name = "test";
        var lsaName = new LSA_STRING {
            Buffer = name,
            Length = (ushort)name.Length,
            MaximumLength = (ushort)(name.Length + 1)
        };
        IntPtr handle;
        ulong secMode;
        int status = LsaRegisterLogonProcess(ref lsaName, out handle, out secMode);
        if (status == 0) {
            LsaDeregisterLogonProcess(handle);
            return "LsaRegisterLogonProcess SUCCESS (SeTcbPrivilege IS available)";
        } else {
            return string.Format("LsaRegisterLogonProcess FAILED: NTSTATUS=0x{0:X8} (SeTcbPrivilege likely missing)", (uint)status);
        }
    }
}
"@
try {
    Add-Type -TypeDefinition $lsaCode -Language CSharp
    Write-Host ([LsaTest]::Test())
} catch {
    Write-Host "LsaTest error: $_"
}

Write-Host "`n=== Check sshd process PID and owner ==="
$sshdProc = Get-Process sshd -ErrorAction SilentlyContinue
if ($sshdProc) {
    Write-Host "sshd PID: $($sshdProc.Id)"
    # Get token info via handle
    $sshdHandle = [System.Diagnostics.Process]::GetProcessById($sshdProc.Id).Handle
    Write-Host "Got sshd handle: $sshdHandle"
} else {
    Write-Host "sshd not running"
}
