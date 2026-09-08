# lsa-primary-domain.ps1
#
# Diagnose / fix the nanoserver-ltsc2025 "ERROR_NO_SUCH_DOMAIN (1355)" local-logon failure.
#
# Root cause (Microsoft, rawahars): mcr.microsoft.com/windows/nanoserver:ltsc2025 ships with an
# EMPTY LSA Primary Domain name. Any real local logon (LogonUser / LsaLogonUser MSV1_0) needs it
# to be non-empty, so it fails with ERROR_NO_SUCH_DOMAIN 1355 / STATUS_NO_SUCH_DOMAIN 0xC00000DF.
# ltsc2022 sets it to WORKGROUP; servercore:ltsc2025 has it set (hence 1326, wrong password).
# Ref: https://github.com/microsoft/Windows-Containers/issues/640
#
# Usage (inside the container, as ContainerAdministrator or SYSTEM):
#   pwsh -File C:\lsa-primary-domain.ps1 -QueryOnly          # dump current LSA policy state
#   pwsh -File C:\lsa-primary-domain.ps1                     # set primary domain to WORKGROUP + verify
#   pwsh -File C:\lsa-primary-domain.ps1 -DomainName WORKGROUP -TestUser jenkins

[CmdletBinding()]
Param(
    [string]$DomainName = 'WORKGROUP',
    [switch]$QueryOnly,
    [string]$TestUser = 'jenkins',
    # Deliberately wrong: we only care whether the failure code moves 1355 -> 1326.
    [string]$TestPassword = 'ThisPasswordIsWrong!123'
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

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
    public uint Attributes;
    public IntPtr SecurityDescriptor;
    public IntPtr SecurityQualityOfService;
}

// POLICY_PRIMARY_DOMAIN_INFO (class 3) and POLICY_ACCOUNT_DOMAIN_INFO (class 5) are
// layout-identical: { LSA_UNICODE_STRING; PSID; }
[StructLayout(LayoutKind.Sequential)]
public struct POLICY_DOMAIN_INFO {
    public LSA_UNICODE_STRING Name;
    public IntPtr Sid;
}

public static class Lsa {
    // POLICY_VIEW_LOCAL_INFORMATION 0x00000001 | POLICY_TRUST_ADMIN 0x00000008 = 0x9
    // NOTE: 0x31 (seen in some snippets) does NOT include POLICY_TRUST_ADMIN and will make
    // LsaSetInformationPolicy fail with STATUS_ACCESS_DENIED 0xC0000022.
    public const uint POLICY_VIEW_LOCAL_INFORMATION = 0x00000001;
    public const uint POLICY_TRUST_ADMIN            = 0x00000008;

    [DllImport("advapi32.dll")]
    public static extern uint LsaOpenPolicy(IntPtr SystemName, ref LSA_OBJECT_ATTRIBUTES oa, uint access, out IntPtr handle);
    [DllImport("advapi32.dll")]
    public static extern uint LsaQueryInformationPolicy(IntPtr handle, int infoClass, out IntPtr buffer);
    [DllImport("advapi32.dll")]
    public static extern uint LsaSetInformationPolicy(IntPtr handle, int infoClass, ref POLICY_DOMAIN_INFO info);
    [DllImport("advapi32.dll")]
    public static extern uint LsaFreeMemory(IntPtr buffer);
    [DllImport("advapi32.dll")]
    public static extern uint LsaClose(IntPtr handle);
    [DllImport("advapi32.dll")]
    public static extern int LsaNtStatusToWinError(uint status);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool ConvertSidToStringSid(IntPtr sid, out IntPtr stringSid);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool LogonUser(string user, string domain, string password, int logonType, int logonProvider, out IntPtr token);
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")]
    public static extern IntPtr LocalFree(IntPtr h);
}
'@

$M = [System.Runtime.InteropServices.Marshal]

function Assert-Nt([uint32]$status, [string]$what) {
    if ($status -ne 0) {
        $win = [Lsa]::LsaNtStatusToWinError($status)
        throw ('{0} failed: NTSTATUS 0x{1:X8} (Win32 {2})' -f $what, $status, $win)
    }
}

function Open-LsaPolicy([uint32]$access) {
    $oa = New-Object LSA_OBJECT_ATTRIBUTES
    $oa.Length = $M::SizeOf([type]'LSA_OBJECT_ATTRIBUTES')
    $h = [IntPtr]::Zero
    Assert-Nt ([Lsa]::LsaOpenPolicy([IntPtr]::Zero, [ref]$oa, $access, [ref]$h)) 'LsaOpenPolicy'
    return $h
}

function Get-DomainInfo([IntPtr]$h, [int]$class, [string]$label) {
    $buf = [IntPtr]::Zero
    $st = [Lsa]::LsaQueryInformationPolicy($h, $class, [ref]$buf)
    if ($st -ne 0) {
        Write-Host ('  {0,-24} QUERY FAILED NTSTATUS 0x{1:X8} (Win32 {2})' -f $label, $st, [Lsa]::LsaNtStatusToWinError($st))
        return $null
    }
    $info = [POLICY_DOMAIN_INFO]($M::PtrToStructure($buf, [type]'POLICY_DOMAIN_INFO'))
    $name = ''
    if ($info.Name.Buffer -ne [IntPtr]::Zero -and $info.Name.Length -gt 0) {
        $name = $M::PtrToStringUni($info.Name.Buffer, [int]($info.Name.Length / 2))
    }
    $sid = '<NULL>'
    if ($info.Sid -ne [IntPtr]::Zero) {
        $sp = [IntPtr]::Zero
        if ([Lsa]::ConvertSidToStringSid($info.Sid, [ref]$sp)) {
            $sid = $M::PtrToStringUni($sp)
            [Lsa]::LocalFree($sp) | Out-Null
        } else { $sid = '<unprintable>' }
    }
    [Lsa]::LsaFreeMemory($buf) | Out-Null
    Write-Host ('  {0,-24} Name="{1}" (len={2}) Sid={3}' -f $label, $name, $info.Name.Length, $sid)
    return [pscustomobject]@{ Name = $name; Sid = $sid }
}

function Set-PrimaryDomainName([IntPtr]$h, [string]$name) {
    $buf = $M::StringToHGlobalUni($name)
    try {
        $info = New-Object POLICY_DOMAIN_INFO
        $u = New-Object LSA_UNICODE_STRING
        $u.Buffer = $buf
        $u.Length = [uint16]($name.Length * 2)
        $u.MaximumLength = [uint16]($name.Length * 2 + 2)
        $info.Name = $u
        $info.Sid = [IntPtr]::Zero   # NULL Sid == workgroup (not domain-joined)
        Assert-Nt ([Lsa]::LsaSetInformationPolicy($h, 3, [ref]$info)) 'LsaSetInformationPolicy(PolicyPrimaryDomainInformation)'
    } finally {
        $M::FreeHGlobal($buf)
    }
}

function Test-Logon([string]$user, [string]$domain, [string]$password) {
    # 2 = LOGON32_LOGON_INTERACTIVE, 0 = LOGON32_PROVIDER_DEFAULT
    $tok = [IntPtr]::Zero
    $ok = [Lsa]::LogonUser($user, $domain, $password, 2, 0, [ref]$tok)
    if ($ok) {
        [Lsa]::CloseHandle($tok) | Out-Null
        Write-Host ('  LogonUser("{0}","{1}") -> SUCCEEDED (unexpected with a wrong password)' -f $user, $domain)
        return 0
    }
    $err = $M::GetLastWin32Error()
    $meaning = switch ($err) {
        1326 { 'ERROR_LOGON_FAILURE  <-- GOOD: LSA reached password validation' }
        1355 { 'ERROR_NO_SUCH_DOMAIN <-- BAD: primary domain still empty' }
        1327 { 'ERROR_ACCOUNT_RESTRICTION' }
        default { 'see winerror.h' }
    }
    Write-Host ('  LogonUser("{0}","{1}") -> {2} {3}' -f $user, $domain, $err, $meaning)
    return $err
}

Write-Host ('=== {0} : LSA policy BEFORE ===' -f $env:COMPUTERNAME)
$hRead = Open-LsaPolicy ([Lsa]::POLICY_VIEW_LOCAL_INFORMATION)
Get-DomainInfo $hRead 3  'PrimaryDomain(3)'   | Out-Null
Get-DomainInfo $hRead 5  'AccountDomain(5)'   | Out-Null
Get-DomainInfo $hRead 12 'DnsDomain(12)'      | Out-Null
[Lsa]::LsaClose($hRead) | Out-Null

Write-Host '=== LogonUser probe BEFORE (wrong password on purpose) ==='
$before = Test-Logon $TestUser '.' $TestPassword

if ($QueryOnly) { exit 0 }

Write-Host ('=== Setting PolicyPrimaryDomainInformation.Name = "{0}" ===' -f $DomainName)
$hWrite = Open-LsaPolicy ([Lsa]::POLICY_VIEW_LOCAL_INFORMATION -bor [Lsa]::POLICY_TRUST_ADMIN)
Set-PrimaryDomainName $hWrite $DomainName
[Lsa]::LsaClose($hWrite) | Out-Null
Write-Host '  OK'

Write-Host '=== LSA policy AFTER ==='
$hRead2 = Open-LsaPolicy ([Lsa]::POLICY_VIEW_LOCAL_INFORMATION)
Get-DomainInfo $hRead2 3 'PrimaryDomain(3)' | Out-Null
Get-DomainInfo $hRead2 5 'AccountDomain(5)' | Out-Null
[Lsa]::LsaClose($hRead2) | Out-Null

Write-Host '=== LogonUser probe AFTER (wrong password on purpose) ==='
$after = Test-Logon $TestUser '.' $TestPassword

Write-Host ''
Write-Host ('RESULT: LogonUser error {0} -> {1}' -f $before, $after)
if ($after -eq 1326) {
    Write-Host 'ROOT CAUSE CONFIRMED FIXED: local logon now reaches password validation.'
    exit 0
} elseif ($after -eq 1355) {
    Write-Host 'STILL 1355: primary domain write did not take effect (or is not the only blocker).'
    exit 1
} else {
    Write-Host 'Error code changed to something else - investigate.'
    exit 2
}
