# Dump LSA policy blobs from HKLM\SECURITY\Policy for PolPrDmN (Primary Domain),
# PolDnDDN (DNS Domain), PolAcDmN (Account Domain).
# Must run as SYSTEM to read HKLM\SECURITY — use schtasks or service bootstrap.
# Usage: run inside a container via docker exec, or via the __sysrun service trick.

$ErrorActionPreference = 'Continue'
foreach ($k in 'HKLM:\SECURITY\Policy\PolPrDmN', 'HKLM:\SECURITY\Policy\PolDnDDN', 'HKLM:\SECURITY\Policy\PolAcDmN') {
    try {
        $raw = (Get-ItemProperty -Path $k -ErrorAction Stop).'(Default)'
        if ($null -eq $raw) { Write-Host ("{0} => NULL" -f $k); continue }
        $hex = ($raw | ForEach-Object { $_.ToString('X2') }) -join ' '
        $len = [BitConverter]::ToUInt16($raw, 0)
        $txt = if ($len -gt 0 -and $len -le ($raw.Length - 8)) {
            [Text.Encoding]::Unicode.GetString($raw, 8, $len)
        } else { '<len_oob>' }
        Write-Host ("{0}`n    bytes={1}`n    len={2} text='{3}'" -f $k, $hex, $len, $txt)
    } catch {
        Write-Host ("{0} => ERR {1}" -f $k, $_.Exception.Message)
    }
}
