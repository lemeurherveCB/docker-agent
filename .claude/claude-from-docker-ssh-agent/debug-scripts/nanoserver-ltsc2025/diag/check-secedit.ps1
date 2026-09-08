# Check secedit.exe and privilege grants in container
Write-Host "=== secedit.exe available? ==="
if (Test-Path 'C:\Windows\System32\secedit.exe') {
    Write-Host "secedit.exe FOUND"
} else {
    Write-Host "secedit.exe NOT FOUND"
}

Write-Host "`n=== Export current security policy ==="
secedit.exe /export /cfg C:\current-policy.cfg /quiet 2>&1
if (Test-Path C:\current-policy.cfg) {
    Write-Host "Policy exported. SeTcbPrivilege entries:"
    Get-Content C:\current-policy.cfg | Where-Object { $_ -match 'SeTcb|SeAssignPrimary|SeCreate' }
} else {
    Write-Host "Export failed"
}

Write-Host "`n=== Can we apply a policy granting SeTcbPrivilege? ==="
# Create a minimal security template
$template = @"
[Version]
signature="$CHICAGO$"
Revision=1
[Privilege Rights]
SeTcbPrivilege = *S-1-5-18,*S-1-5-80-0
SeAssignPrimaryTokenPrivilege = *S-1-5-18,*S-1-5-80-0
SeCreateTokenPrivilege = *S-1-5-18
"@
Set-Content C:\secedit-template.inf $template
secedit.exe /configure /db C:\secedit.sdb /cfg C:\secedit-template.inf /quiet /areas PRIVILEGES 2>&1
Write-Host "secedit configure result: $LASTEXITCODE"

Write-Host "`n=== Check privileges after secedit ==="
secedit.exe /export /cfg C:\policy-after.cfg /quiet 2>&1
if (Test-Path C:\policy-after.cfg) {
    Get-Content C:\policy-after.cfg | Where-Object { $_ -match 'SeTcb|SeAssignPrimary|SeCreate' }
}

Write-Host "`n=== Test am_system() after secedit ==="
$code = @"
using System;
using System.Runtime.InteropServices;
public class SysCheck {
    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool AllocateAndInitializeSid(ref SIA pIA, byte n, uint r0, uint r1, uint r2, uint r3, uint r4, uint r5, uint r6, uint r7, out IntPtr pSid);
    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool CheckTokenMembership(IntPtr hToken, IntPtr pSid, out bool isMember);
    [DllImport("advapi32.dll")]
    public static extern IntPtr FreeSid(IntPtr pSid);
    [StructLayout(LayoutKind.Sequential)]
    public struct SIA { [MarshalAs(UnmanagedType.ByValArray, SizeConst=6)] public byte[] Value; }
    public static bool AmSystem() {
        IntPtr sid = IntPtr.Zero;
        bool r = false;
        try {
            var a = new SIA { Value = new byte[] { 0,0,0,0,0,5 } };
            AllocateAndInitializeSid(ref a, 1, 18, 0,0,0,0,0,0,0, out sid);
            CheckTokenMembership(IntPtr.Zero, sid, out r);
        } finally { if (sid != IntPtr.Zero) FreeSid(sid); }
        return r;
    }
}
"@
Add-Type -TypeDefinition $code -Language CSharp
Write-Host "am_system() = $([SysCheck]::AmSystem())"
