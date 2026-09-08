# Set-LsaPrimaryDomain.ps1 -- shippable, idempotent version.
#
# nanoserver:ltsc2025 ships with an EMPTY LSA Primary Domain name, which makes every real local
# logon fail with ERROR_NO_SUCH_DOMAIN (1355) / STATUS_NO_SUCH_DOMAIN (0xC00000DF). That breaks
# Win32-OpenSSH's S4U token generation for the local `jenkins` account.
# nanoserver:ltsc2022 sets it to WORKGROUP, which is why ltsc2022 images work.
# Ref: https://github.com/microsoft/Windows-Containers/issues/640
#
# Must run elevated (ContainerAdministrator or SYSTEM). No-op when already non-empty.
[CmdletBinding()]
Param([string]$DomainName = 'WORKGROUP')

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct LSA_UNICODE_STRING { public ushort Length; public ushort MaximumLength; public IntPtr Buffer; }

[StructLayout(LayoutKind.Sequential)]
public struct LSA_OBJECT_ATTRIBUTES {
    public int Length; public IntPtr RootDirectory; public IntPtr ObjectName;
    public uint Attributes; public IntPtr SecurityDescriptor; public IntPtr SecurityQualityOfService; }

[StructLayout(LayoutKind.Sequential)]
public struct POLICY_DOMAIN_INFO { public LSA_UNICODE_STRING Name; public IntPtr Sid; }

public static class LsaPd {
    public const uint POLICY_VIEW_LOCAL_INFORMATION = 0x00000001;
    public const uint POLICY_TRUST_ADMIN            = 0x00000008;
    public const int  PolicyPrimaryDomainInformation = 3;

    [DllImport("advapi32.dll")] public static extern uint LsaOpenPolicy(IntPtr s, ref LSA_OBJECT_ATTRIBUTES oa, uint a, out IntPtr h);
    [DllImport("advapi32.dll")] public static extern uint LsaQueryInformationPolicy(IntPtr h, int c, out IntPtr b);
    [DllImport("advapi32.dll")] public static extern uint LsaSetInformationPolicy(IntPtr h, int c, ref POLICY_DOMAIN_INFO i);
    [DllImport("advapi32.dll")] public static extern uint LsaFreeMemory(IntPtr b);
    [DllImport("advapi32.dll")] public static extern uint LsaClose(IntPtr h);
    [DllImport("advapi32.dll")] public static extern int  LsaNtStatusToWinError(uint st);
}
'@

$M = [System.Runtime.InteropServices.Marshal]

$oa = New-Object LSA_OBJECT_ATTRIBUTES
$oa.Length = $M::SizeOf([type]'LSA_OBJECT_ATTRIBUTES')
$h = [IntPtr]::Zero
$st = [LsaPd]::LsaOpenPolicy([IntPtr]::Zero, [ref]$oa,
        ([LsaPd]::POLICY_VIEW_LOCAL_INFORMATION -bor [LsaPd]::POLICY_TRUST_ADMIN), [ref]$h)
if ($st -ne 0) { throw ('LsaOpenPolicy failed: NTSTATUS 0x{0:X8} (Win32 {1})' -f $st, [LsaPd]::LsaNtStatusToWinError($st)) }

try {
    $current = ''
    $buf = [IntPtr]::Zero
    if ([LsaPd]::LsaQueryInformationPolicy($h, [LsaPd]::PolicyPrimaryDomainInformation, [ref]$buf) -eq 0) {
        $info = [POLICY_DOMAIN_INFO]($M::PtrToStructure($buf, [type]'POLICY_DOMAIN_INFO'))
        if ($info.Name.Buffer -ne [IntPtr]::Zero -and $info.Name.Length -gt 0) {
            $current = $M::PtrToStringUni($info.Name.Buffer, [int]($info.Name.Length / 2))
        }
        [LsaPd]::LsaFreeMemory($buf) | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace($current)) {
        Write-Host ('LSA primary domain already set to "{0}" - nothing to do.' -f $current)
        return
    }

    $nameBuf = $M::StringToHGlobalUni($DomainName)
    try {
        $u = New-Object LSA_UNICODE_STRING
        $u.Buffer = $nameBuf
        $u.Length = [uint16]($DomainName.Length * 2)
        $u.MaximumLength = [uint16]($DomainName.Length * 2 + 2)
        $pd = New-Object POLICY_DOMAIN_INFO
        $pd.Name = $u
        $pd.Sid = [IntPtr]::Zero   # NULL Sid => workgroup, not domain-joined
        $st = [LsaPd]::LsaSetInformationPolicy($h, [LsaPd]::PolicyPrimaryDomainInformation, [ref]$pd)
        if ($st -ne 0) {
            throw ('LsaSetInformationPolicy failed: NTSTATUS 0x{0:X8} (Win32 {1})' -f $st, [LsaPd]::LsaNtStatusToWinError($st))
        }
    } finally { $M::FreeHGlobal($nameBuf) }

    Write-Host ('LSA primary domain set to "{0}".' -f $DomainName)
} finally {
    [LsaPd]::LsaClose($h) | Out-Null
}
