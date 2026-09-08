---
name: project-nano2025-poc
description: nanoserver-ltsc2025 USER jenkins fix via setpd.exe — current state and key findings
metadata: 
  node_type: memory
  type: project
  originSessionId: 0b5d9042-b15a-470d-a677-574996815442
  modified: 2026-09-08T20:12:44.720Z
---

# nano2025-poc: nanoserver-ltsc2025 USER jenkins fix

**Branch**: `nano2025-poc`  
**Last commit**: `00bf24f` — "feat: fix nanoserver-ltsc2025 USER jenkins via setpd.exe build stage"  
**Status**: All tests passing (agent 20/20, inbound-agent 8/8 on ltsc2025). Ready to PR.

## The Problem

nanoserver-ltsc2025 ships with a volatile (no backing store) `HKLM\SECURITY` hive.
`CreateProcessAsUser("jenkins")` fails with `ERROR_NO_SUCH_DOMAIN` (0x54b / 1355),
so `USER jenkins` does not work in either Dockerfile RUN steps or at container runtime.

## The Solution

New `setpd-builder` intermediate stage in `windows/nanoserver/Dockerfile`:
1. Uses `w64devkit` (skeeto's MinGW-w64, v1.23.0) on Windows Server Core to compile `setpd.c`
2. `setpd.exe` calls `LsaSetInformationPolicy(PolicyPrimaryDomainInformation)` to write "WORKGROUP"
3. Docker's windowsfilter driver captures the registry change when committing the layer
4. The fix persists across container starts — **USER jenkins works at runtime too**

Source: https://github.com/microsoft/Windows-Containers/issues/640

## Key Empirical Finding (corrects prior RESUME.md claim)

RESUME.md claimed "the write is discarded on every container start" — **this is WRONG**.
Proven by minimal test (`Dockerfile.setpd-test`): `docker run --rm setpd-test cmd.exe /c echo %USERNAME%`
outputs `USERNAME=jenkins` — the fix persists from build time to runtime via Docker layer snapshots.

## Files Changed

- `windows/nanoserver/setpd.c` — new C source (LsaSetInformationPolicy call)
- `windows/nanoserver/Dockerfile` — setpd-builder stage + netapi32.dll staging fix + ENV USERNAME
- `windows/nanoserver/Dockerfile.setpd-test` — minimal runtime test Dockerfile
- `tests/test_helpers.psm1` — try/catch fix for Cleanup/CleanupNetwork (PS7.4+ compat)
- `build-windows-on-ec2.sh` — EC2 build script (PRUNE_DOCKER support)
- `run-setpd-test-on-ec2.sh` — dedicated minimal test runner

## netapi32.dll Quirk

ltsc2019/ltsc2022: DLL absent → `COPY ... netapi32.dll C:\netapi32.dll` then `Move-Item`
ltsc2025: DLL present as protected stub → cannot overwrite with COPY → `Remove-Item` the staged copy
Pattern in Dockerfile: stage to `C:/netapi32.dll`, then conditional `if (!(Test-Path ...)) { Move } else { Remove }`

**Why**: Docker COPY can't overwrite Windows protected system DLLs (Access is denied).

## w64devkit PATH note

Must set `$env:PATH = 'C:\w64\w64devkit\bin;' + $env:PATH` before calling `gcc.exe`
so it can find `as.exe` (assembler) in the same directory.

## Next Steps

- Open PR from `nano2025-poc` → `master`
- Consider adding ltsc2025 to the regular CI matrix

[[reference-ec2-build]]
