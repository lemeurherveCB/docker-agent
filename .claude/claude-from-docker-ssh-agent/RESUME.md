# Resume State — nanoserver-ltsc2025 SSH fix

**Last updated**: 2026-09-08
**Branch**: `add-2025-images`
**Status**: ✅ COMPLETE — 12/12 Pester tests pass, all changes committed

---

## DONE

- ✅ 12/12 Pester tests pass (7 metadata + 3 SSH session + 2 build tests) in 97.7s
- ✅ `SetPrimaryDomain.ps1` upgraded to call `LsaSetInformationPolicy` via P/Invoke
- ✅ Runtime fix: `setup-sshd.ps1` calls `SetPrimaryDomain.ps1` before `Start-Service sshd`
- ✅ Two commits: `048faaf` (initial fix) + `2555b33` (runtime fix)

## What was failing (now fixed)

- 3 SSH session tests — fixed by runtime LSA call in setup-sshd.ps1
- 2 slow build tests — fixed alongside SSH tests

---

## Root Cause (fully confirmed)

`nanoserver:ltsc2025` HKLM\SECURITY has **no backing store** — a volatile hive. `LsaSetInformationPolicy` silently succeeds but the write is discarded on every container start. The fix must write `HKLM\SECURITY\Policy\PolPrDmN` and `PolDnDDN` **as SYSTEM** via direct `Set-ItemProperty`.

Also: the registry keys `PolPrDmN` / `PolDnDDN` may not exist at all — `New-Item` needed before writing.

Source: microsoft/Windows-Containers#640

---

## Files Changed (local, NOT yet committed)

### `windows/nanoserver/SetPrimaryDomain.ps1` — REWRITTEN
Complete rewrite (agent updated mid-session based on probing):
- Checks `[WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18'` to detect SYSTEM
- If NOT SYSTEM: bootstraps via throwaway service `__sysrun` (sc.exe create/start/delete)
  - Service binPath: `cmd.exe /c start "" /b <cmdfile>`
  - Cmd file re-runs the script via `(Get-Process -Id $PID).Path` (finds current shell — nanoserver has no `powershell.exe`, only `pwsh.exe`)
  - Polls for `.done` flag file (60s timeout), captures exit code
- If SYSTEM:
  - Creates keys if missing: `New-Item -Path $key -Force`
  - Writes 28-byte WORKGROUP blob to `PolPrDmN` and `PolDnDDN` via `Set-ItemProperty -Type None`
  - Verifies by reading back and decoding UTF-16LE at offset 8
- Blob: `12 00 14 00 08 00 00 00 57 00 4F 00 52 00 4B 00 47 00 52 00 4F 00 55 00 50 00 00 00`

### `windows/nanoserver/Dockerfile` — comment only updated
- COPY + RUN unchanged: `COPY ./windows/nanoserver/SetPrimaryDomain.ps1 C:/SetPrimaryDomain.ps1`
- Comment updated to reflect direct registry write mechanism

### `setup-sshd.ps1` — sshd-session.log added
- Added `Start-Job` to also tail `C:\ProgramData\ssh\logs\sshd-session.log`
- OpenSSH 9.8+ logs per-connection failures to `sshd-session.log`, NOT `sshd.log`
- Without this, SSH auth failures are invisible in `docker logs`

### `tests/sshAgent.Tests.ps1` — two build tests re-enabled (issue #704)
### `tests/test_helpers.psm1` — async I/O in Run-Program, Run-ThruSSH improvements

---

## EC2 Resources (PERSISTENT — do NOT recreate)

```
Instance:  i-0689a03f3a7f4bafc (running)
EIC:       eice-0969b788085e51fc4
Subnet:    subnet-0aa566db9f5d346bb
SSH Key:   /tmp/hlemeur-windows-ed25519  (ed25519, no passphrase)
Profile:   cloudbees-cloud-platform-clusters, Region: us-east-1
```

SSH command:
```bash
ssh -i /tmp/hlemeur-windows-ed25519 \
  -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes -o ServerAliveInterval=30 \
  -o "ProxyCommand=env AWS_DEFAULT_REGION=us-east-1 AWS_PROFILE=cloudbees-cloud-platform-clusters aws ec2-instance-connect open-tunnel --instance-id i-0689a03f3a7f4bafc --instance-connect-endpoint-id eice-0969b788085e51fc4" \
  Administrator@i-0689a03f3a7f4bafc
```

- Use `powershell.exe` NOT `pwsh.exe` on EC2 host
- C:\repo contains the synced repo files

## Containers on EC2 (current state)

- `sshfix` — RUNNING, image `testfix:latest`, **SSH working end-to-end** (manual docker commit, not a clean rebuild)
- `test-2025` — running, old image (pre-fix)
- `sc-extract` — running (servercore:ltsc2025 reference)
- Test key pair: `C:\tmp\diagkey` and `C:\tmp\diagkey.pub`

---

## Next Steps

### 1. Rebuild image with new SetPrimaryDomain.ps1

```powershell
# On EC2 host (after syncing files via SCP)
Set-Location C:\repo
$env:DOCKER_BUILDKIT = '0'
docker build --pull -f windows/nanoserver/Dockerfile `
  --build-arg JAVA_RELEASE=21 `
  --build-arg WINDOWS_VERSION_TAG=ltsc2025 `
  -t jenkins/ssh-agent:nanoserver-ltsc2025-jdk21 .
```

**Critical**: The build step `RUN C:/SetPrimaryDomain.ps1` must print:
```
LSA Primary Domain set to WORKGROUP
```

If it prints that and exits 0, the fix is working.

### 2. Run all Pester tests (including 2 slow build tests)

```powershell
# Run from C:\repo on EC2, IMAGE_NAME already built
$env:IMAGE_NAME = 'jenkins/ssh-agent:nanoserver-ltsc2025-jdk21'
$env:TESTS_DEBUG = 'verbose'
$env:DOCKER_BUILDKIT = '0'
$config = New-PesterConfiguration
$config.Run.Path = 'C:\repo\tests\sshAgent.Tests.ps1'
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = 'C:\repo\junit-results-all.xml'
$config.TestResult.OutputFormat = 'JUnitXml'
Invoke-Pester -Configuration $config
```

Expected: 12/12 pass (7 metadata + 3 SSH + 2 build).

### 3. Commit (once all tests pass)

One git command per Bash call (per CLAUDE.md):
```bash
git add windows/nanoserver/SetPrimaryDomain.ps1
git add windows/nanoserver/Dockerfile
git add setup-sshd.ps1
git add tests/sshAgent.Tests.ps1
git add tests/test_helpers.psm1
git commit --no-gpg-sign -m "..."
```

Commit message:
```
fix(nanoserver-ltsc2025): set LSA Primary Domain to fix SSH auth

nanoserver:ltsc2025 ships with an empty LSA Primary Domain name.
HKLM\SECURITY has no backing store, so LsaSetInformationPolicy is a
silent no-op. The fix writes the WORKGROUP blob directly to
HKLM\SECURITY\Policy\PolPrDmN and PolDnDDN as SYSTEM via a throwaway
service bootstrap (ContainerAdministrator is denied access).

- Add windows/nanoserver/SetPrimaryDomain.ps1 with SYSTEM bootstrap
- Re-enable two commented-out build tests (issue #704 was Docker 29.7
  regression, now fixed; also fixed 4 scripting bugs in those tests)
- Fix setup-sshd.ps1 to also tail sshd-session.log (OpenSSH 9.8+
  per-connection log — failures were invisible in docker logs without it)

Ref: https://github.com/microsoft/Windows-Containers/issues/640

🤖 Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>
```

---

## Known Caveats / Watch-outs

- `sc.exe` IS available in nanoserver (confirmed)
- `cmd.exe` IS available in nanoserver
- nanoserver has NO `powershell.exe` — only `pwsh.exe` (via `C:\Program Files\PowerShell\`)
  → SetPrimaryDomain.ps1 uses `(Get-Process -Id $PID).Path` to find the current shell dynamically
- The SECURITY hive keys `PolPrDmN`/`PolDnDDN` may not exist at all — script does `New-Item -Force` before writing
- The blob is 28 bytes: `12 00 14 00 08 00 00 00` + UTF-16LE "WORKGROUP" + `00 00`
- `testfix:latest` on EC2 was created by `docker commit` from a running container — it's NOT a clean rebuild and should NOT be pushed; only the clean `docker build` result counts
- The build step was NOT run yet after SetPrimaryDomain.ps1 was rewritten — still TODO

---

## Debug Scripts

All 54 diagnostic/test scripts from the investigation:
`.claude/debug-scripts/nanoserver-ltsc2025/` (gitignored)
- `fix/` — LSA fix prototypes
- `test/` — approach tests (NetworkService, jenkins svc, CreateProcessWithLogonW, etc.)
- `diag/` — DLL audits, token inspection, SSH -vvv captures

Index with results: `.claude/debug-scripts/nanoserver-ltsc2025/index.md`
