# nanoserver-ltsc2025 SSH Debug Scripts

Debug and diagnostic scripts created during the investigation of Win32-OpenSSH SSH auth failure in `nanoserver:ltsc2025` containers. See also: [memory](../../memory/project_nanoserver_ltsc2025_ssh.md), [issue ref](../../memory/reference_windows_containers_issues.md).

---

## fix/ — Fix implementations

| Script | Purpose | Result |
|--------|---------|--------|
| `Set-LsaPrimaryDomain.ps1` | Early prototype of the LSA Primary Domain fix (P/Invoke via Add-Type). Sets `PolicyPrimaryDomainInformation = "WORKGROUP"`. | Prototype — production version at `windows/nanoserver/SetPrimaryDomain.ps1` |
| `lsa-primary-domain.ps1` | Extended prototype with more error handling and diagnostic output. Also tests `LogonUser` before/after to verify the fix. | Confirmed fix resolves `LogonUser ERROR_NO_SUCH_DOMAIN (1355)` |
| `install-sshd.ps1` | Attempts to install/configure Win32-OpenSSH inside a container (standalone approach). | Superseded by Dockerfile RUN steps |
| `fix-sshd-system.ps1` | Attempt to reconfigure the sshd service to run as SYSTEM with correct privileges. | Not needed — service already runs as LocalSystem |
| `orchestrate.ps1` | Multi-step orchestration script: builds image, starts container, runs SSH tests. | Used during early testing phases |

---

## test/ — Approach tests (tried in order)

| Script | Approach tested | Result |
|--------|----------------|--------|
| `test-ca-sshd.ps1` | sshd as ContainerAdministrator | FAIL: PATH 3 hit — `LookupAccountName("jenkins")` succeeds so user_sid≠NULL → "not running as system" |
| `test-jenkins-service-fix.ps1` | sshd service running as jenkins user account | FAIL: `logon failure 1069` — jenkins has no "Log on as service" right in nanoserver |
| `test-sshd-createprocess-jenkins.ps1` | `CreateProcessWithLogonW("jenkins", ".", password)` | FAIL: returns -1355 (ERROR_NO_SUCH_DOMAIN) — same LSA Primary Domain root cause |
| `test-network-service-sshd.ps1` | sshd running as NT AUTHORITY\NetworkService | FAIL: error 1297 (`ERROR_PRIVILEGE_NOT_HELD`) — NetworkService lacks `SeAssignPrimaryTokenPrivilege` in containers |
| `test-sshd-as-jenkins.ps1` | sshd process owned by jenkins user | FAIL: requires LogonUser to start, which was broken at the time |
| `test-logonuser-hostname.ps1` | `LogonUser` with machine hostname as domain name | FAIL: hostname not recognized as local domain |
| `test-logonuser-types.ps1` | All `LogonUser` LOGON32_LOGON_* types (2/3/4/5/9) | PARTIAL: type 9 (NEW_CREDENTIALS) succeeds but returns ContainerAdministrator token, not jenkins |
| `test-custom-lsa.ps1` | Custom LSA package registration | Not completed — superseded by Primary Domain fix |
| `test-lsa-pkg.ps1` | Setting `HKLM:\SOFTWARE\OpenSSH\LSAAuthenticationPackage = msv1_0` | Tested in combination with SYSTEM sshd — S4U still failed with 0xC00000DF before Primary Domain fix |
| `test-lsa-verbose.ps1` | Verbose LSA logon attempt with extended error info | Used to confirm 0xC00000DF = STATUS_NO_SUCH_DOMAIN |
| `test-service-lsa.ps1` | LSA policy queries from service context | Confirmed Primary Domain was empty (`""`) in nanoserver-ltsc2025 |
| `test-debug-service.ps1` | sshd with DEBUG3 log level as a service | Used to capture `generate_s4u_user_token: LsaLogonUser() failed Status: 0xC00000DF` |
| `test-sshd-debug-lsa.ps1` | sshd + verbose LSA logging simultaneously | Diagnostic only |
| `test-jenkins-with-password.ps1` | `LogonUser` with password set for jenkins | FAIL: same 1355 error (domain problem, not password problem) |
| `test-schtasks.ps1` | Run commands as SYSTEM via schtasks to test S4U path | Used to verify SYSTEM S4U also failed before Primary Domain fix |
| `test-rsa-auth.ps1` | RSA key auth test (vs ed25519) | No difference — auth method not the issue |
| `test-ssh-b64key.ps1` | Base64-encoded key injection test | Workaround attempt for key format issues — not needed |
| `test-ssh-container.ps1` | Full SSH round-trip test with fresh container | Used throughout for end-to-end validation |
| `test-ssh-inside.ps1` | SSH test running from inside the container | Used to isolate networking vs auth issues |
| `test-ssh-key.ps1` | Key generation and permission setup | Standard key setup for test containers |
| `run-nano-tests.ps1` | Pester test runner for `nanoserver-ltsc2025-jdk21` image | **Latest run (2026-09-07)**: 7/12 pass, 3 SSH tests FAIL (get_user_token blocker) |
| `ssh-container-test.ps1` | Standalone container + SSH test (no Pester) | Used for quick iteration |
| `ssh-test2.ps1`, `ssh-test3.ps1`, `ssh-test4.ps1` | Iterations of SSH test with different options | Progressive refinements |
| `sshd-debug-test.ps1` | sshd with -ddd + simultaneous SSH attempt | Captured `Accepted publickey` then immediate disconnect after Primary Domain fix |
| `start-debug-container.ps1` | Start container configured for debug (DEBUG3, extra logging) | Used to capture service sshd logs |

---

## diag/ — Diagnostic scripts

| Script | What it checks | Key finding |
|--------|---------------|-------------|
| `check-netapi32.ps1` | netapi32.dll presence, size, version in nanoserver vs servercore | Both use a stub (117KB). NOT the auth failure cause. |
| `check-sec-dlls.ps1` | msv1_0.dll, lsasrv.dll, samsrv.dll, samlib.dll, secur32.dll sizes | All DLLs byte-identical between nanoserver and servercore ltsc2025. |
| `check-logonuser-sc.ps1` | `LogonUser` directly from `sc.exe` context | Confirmed 1355 error from service context |
| `check-openssh-strings.ps1` | `strings` on sshd.exe to find `get_user_token` code paths | Located exact log message strings, confirmed code paths |
| `check-sshd-token.ps1` | Full token inspection for sshd process (SYSTEM context) | Confirmed sshd service runs as S-1-5-18 (SYSTEM) |
| `check-secedit.ps1` | Export local security policy (privilege assignments) | Checked SeTcbPrivilege, SeAssignPrimaryTokenPrivilege assignments |
| `check-system-procs.ps1` | List all processes + tokens in the container | Identified sshd children and their session/token types |
| `audit.ps1`, `audit2.ps1`, `audit3.ps1` | EC2 host audit: DLL copy between servercore and nanoserver containers | DLLs confirmed byte-identical — not the cause |
| `diag-ssh.ps1` – `diag-ssh6.ps1` | SSH connection diagnostics with varying verbosity | `diag-ssh2.ps1` → captured `Accepted publickey` + instant reset after LSA fix |
| `diag1.ps1` – `diag3.ps1` | Container state diagnostics (users, services, registry) | Confirmed jenkins user exists, sshd service registered, DefaultShell set |
| `debug-ssh.ps1`, `debug-ssh-ipv4.ps1` | ssh -vvv capture with `-4` IPv4 forcing | `debug-ssh-ipv4.ps1` → confirmed auth success + `WSARecv 10054` pattern |
| `ssh-diag.ps1` | Combined SSH + container inspect | Used for quick state snapshots |

---

## Current Status (2026-09-08)

### Blocker 1 — FIXED
`LogonUser ERROR_NO_SUCH_DOMAIN (1355)` — resolved by `windows/nanoserver/SetPrimaryDomain.ps1`.
Public key auth now succeeds end-to-end.

### Blocker 2 — ROOT CAUSE CONFIRMED
**`HKLM\SECURITY` is a volatile hive in nanoserver-ltsc2025.** `LsaSetInformationPolicy` returns
NTSTATUS 0 (success) but the write is silently discarded — no backing store, reset on every
container start. Docker layer commits never capture it.

Evidence:
- Build RUN printed "LSA Primary Domain set to WORKGROUP" → appeared to succeed
- Runtime: `docker exec --user jenkins` fails with 0x54b → Primary Domain still empty at runtime
- SYSTEM has SeTcbPrivilege (confirmed) → not a privilege issue

### Fix (pending confirmation)
Move `LsaSetInformationPolicy` call to **`setup-sshd.ps1`** (container entrypoint), before
`Start-Service sshd`. Even though the SECURITY hive write won't persist to disk, the
**in-memory LSA state** will be correct for the duration of the container's lifetime, and sshd
will use it for S4U token creation.

Agent also testing: direct registry write to `HKLM\SECURITY\Policy\PolPriDn` (if it works,
would be an alternative persistent approach).

---

## Scripts added during Blocker 2 investigation (2026-09-08)

| Script | Purpose | Result |
|--------|---------|--------|
| `diag/verify-lsa-blobs.ps1` | Dump PolPrDmN / PolDnDDN / PolAcDmN raw bytes + decoded name. **Must run as SYSTEM.** | Key validation tool — use via __sysrun service bootstrap |
| `diag/diag-setprimarydomain.ps1` | Full E2E test on EC2: starts container, runs SetPrimaryDomain.ps1, dumps blobs before+after | Used to validate the rewritten SetPrimaryDomain.ps1 |

### Nanoserver binary availability (probe-confirmed 2026-09-08)

| Binary | Available |
|--------|-----------|
| `sc.exe` | ✅ `C:\Windows\System32\sc.exe` |
| `cmd.exe` | ✅ Yes |
| `powershell.exe` (WinPS 5.x) | ❌ Not present |
| `pwsh.exe` (PS 7) | ✅ Copied in by Dockerfile jdk-pwsh stage |
| `reg.exe` | ✅ Yes |

→ SetPrimaryDomain.ps1 uses `(Get-Process -Id $PID).Path` to find `pwsh.exe` dynamically.

### EC2 ad-hoc scripts (created on EC2, not synced back)
| Script | Notes |
|--------|-------|
| `s4utest.ps1` (EC2 C:\work) | S4U token creation test — confirmed SYSTEM has SeTcbPrivilege |
| `regpd.ps1` (EC2 C:\work) | First attempt at direct registry write — used to discover correct blob format |
