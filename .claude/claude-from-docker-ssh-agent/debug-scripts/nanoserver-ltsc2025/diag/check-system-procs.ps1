# Check all container processes and their token SYSTEM status
# ContainerAdministrator has SeDebugPrivilege - can we find a SYSTEM token?

$code = @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Diagnostics;

public class TokenChecker {
    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool OpenProcessToken(IntPtr hProcess, uint dwDesiredAccess, out IntPtr phToken);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool CheckTokenMembership(IntPtr TokenHandle, IntPtr SidToCheck, out bool IsMember);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool AllocateAndInitializeSid(ref SID_IDENTIFIER_AUTHORITY pIdentifierAuthority,
        byte nSubAuthorityCount, uint nSubAuthority0, uint nSubAuthority1, uint nSubAuthority2, uint nSubAuthority3,
        uint nSubAuthority4, uint nSubAuthority5, uint nSubAuthority6, uint nSubAuthority7, out IntPtr pSid);

    [DllImport("advapi32.dll")]
    public static extern IntPtr FreeSid(IntPtr pSid);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);

    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool DuplicateTokenEx(IntPtr hExistingToken, uint dwDesiredAccess,
        IntPtr lpTokenAttributes, int ImpersonationLevel, int TokenType, out IntPtr phNewToken);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool SetThreadToken(IntPtr pHandle, IntPtr hToken);

    [StructLayout(LayoutKind.Sequential)]
    public struct SID_IDENTIFIER_AUTHORITY {
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=6)]
        public byte[] Value;
    }

    static IntPtr GetSystemSid() {
        IntPtr sid = IntPtr.Zero;
        var auth = new SID_IDENTIFIER_AUTHORITY { Value = new byte[] { 0,0,0,0,0,5 } };
        AllocateAndInitializeSid(ref auth, 1, 18, 0,0,0,0,0,0,0, out sid);
        return sid;
    }

    public static bool IsProcessSystem(int pid) {
        IntPtr procHandle = IntPtr.Zero;
        IntPtr token = IntPtr.Zero;
        IntPtr systemSid = IntPtr.Zero;
        bool result = false;
        try {
            procHandle = OpenProcess(0x400 | 0x8, false, pid); // PROCESS_QUERY_INFORMATION | PROCESS_VM_READ
            if (procHandle == IntPtr.Zero) return false;
            if (!OpenProcessToken(procHandle, 0x0008, out token)) return false; // TOKEN_QUERY
            systemSid = GetSystemSid();
            CheckTokenMembership(token, systemSid, out result);
        } catch { }
        finally {
            if (systemSid != IntPtr.Zero) FreeSid(systemSid);
            if (token != IntPtr.Zero) CloseHandle(token);
            if (procHandle != IntPtr.Zero) CloseHandle(procHandle);
        }
        return result;
    }
}
"@
Add-Type -TypeDefinition $code -Language CSharp -ErrorAction Stop

Write-Host "=== All processes and SYSTEM token status ==="
Get-Process | ForEach-Object {
    try {
        $isSystem = [TokenChecker]::IsProcessSystem($_.Id)
        Write-Host "$($_.Name.PadRight(25)) PID=$($_.Id.ToString().PadRight(6)) SYSTEM=$isSystem"
    } catch {
        Write-Host "$($_.Name.PadRight(25)) PID=$($_.Id.ToString().PadRight(6)) ERROR"
    }
}
