# docker-ssh-agent — Fix Report: Issue #704

## Session: Re-enable Windows build tests; fix Docker 29.7.0 NUL regression fallout

### Date
2026-09-08

### Branch
`restore-commented-out-tests`

### Commit
`f444bb9` — `fix(tests/windows): re-enable build tests; fix scripting bugs and Run-Program reliability`

---

## Context

[jenkinsci/docker-ssh-agent#704](https://github.com/jenkinsci/docker-ssh-agent/issues/704) was opened after Windows CI builds started throwing:

```
Error response from daemon: invalid entry name "NUL"
```

during `docker build` on EC2 Windows agents running **Docker 29.7.0** (released 2026-07-30). Two Pester `Describe` blocks in `tests/sshAgent.Tests.ps1` — `"image can be built"` and `"image can be built with custom build args"` — were commented out in commit `d93a89e` to restore CI green. The comment read:

> Due to flakiness (can't reproduce outside ci.jenkins.io EC2 VM agents) on these 2 tests, and given our test framework is not really practical to understand what failed, let's comment these tests out temporarily to resume CI success.

Investigation on the `nano2025poc` branch identified **two separate root causes**: the Docker Engine regression (external, fixed by upgrading Docker) and five pre-existing test scripting bugs (internal, fixed here).

---

## Root Cause 1 — Docker 29.7.0 Regression (external)

### What broke

Docker 29.7.0 introduced two simultaneous library changes that combined to produce `invalid entry name "NUL"` during `docker build` on Windows containers:

#### Change A — Security fix in `moby/go-archive` (v0.2.0 → v0.3.0)

- **CVE**: [GHSA-hfg8-hc9c-6c3h](https://github.com/moby/go-archive/security/advisories/GHSA-hfg8-hc9c-6c3h) — tar path-traversal vulnerability
- **PR**: [moby/go-archive#45](https://github.com/moby/go-archive/pull/45) — "archive: harden tar extraction against path traversal"
- **Vendored into moby via**: [moby/moby#53247](https://github.com/moby/moby/pull/53247)

The fix added this guard in `archive.go` (~line 1035):

```go
name := path.Clean(strings.TrimLeft(hdr.Name, "/"))
if !filepath.IsLocal(name) {
    return breakoutError(fmt.Errorf("invalid entry name %q", hdr.Name))
}
```

On Windows, `filepath.IsLocal` returns `false` for **any Windows reserved device name**: `NUL`, `CON`, `PRN`, `AUX`, `COM1`–`COM9`, `LPT1`–`LPT9`. So any tar entry containing a path component named `NUL` causes the daemon to abort with `invalid entry name "NUL"`.

#### Change B — BuildKit bumped to v0.32.0

BuildKit v0.32.0 updated its vendored `go-archive` to v0.2.1, which added POSIX path normalization for Windows container layer exports:

- [moby/go-archive#40](https://github.com/moby/go-archive/pull/40) — "tarAppender.addTarFile: normalize archivePath to POSIX"
- [moby/go-archive#41](https://github.com/moby/go-archive/pull/41) — "ExportChanges: use POSIX / Unix conventions for Tar operations"

Windows container filesystems can legally contain a `NUL` reparse point entry (the null device). After POSIX normalization, this appeared as a literal `NUL` entry in the exported tar stream.

#### Combined effect

BuildKit v0.32.0 **emitted** `NUL`-named entries → the moby daemon's new `filepath.IsLocal` guard **rejected** them → `docker build` failed every time a new layer containing a NUL reparse point was created.

`docker run` was unaffected because pre-extracted cached layers did not go through the `UnpackLayer` path again. `docker build` triggered full snapshot export + apply on every run, hitting the issue deterministically.

#### Why "only on EC2" and not local machines

CI EC2 agents ran with cold Docker environments (no pre-warmed layer caches), forcing full layer re-extraction on every build. Developer Windows 11 machines had cached layers from previous builds and never hit the re-extraction path.

### Fix (Docker-side, not this repo)

**Docker 29.7.2** (released 2026-08-06) — [moby/moby tag docker-v29.7.2](https://github.com/moby/moby/releases/tag/docker-v29.7.2)

Two fixes landed:

1. **moby daemon** — [moby/moby#53305](https://github.com/moby/moby/pull/53305): bumped go-archive to v0.3.3 (device node + hardlink fixes)
2. **BuildKit v0.32.2**: reverted the go-archive v0.2.1 POSIX normalization change, so `NUL` entries are never emitted in Windows layer tars in the first place

The daemon's `filepath.IsLocal` guard remains; BuildKit just stopped triggering it.

**No code change was needed in this repository for this root cause.** Upgrading Docker Engine to ≥ 29.7.2 on CI agents resolves it.

---

## Root Cause 2 — Pre-existing Test Scripting Bugs (internal, fixed here)

The Docker regression exposed five independent bugs in the test code that existed before 29.7.0 and would cause the build tests to fail or behave unreliably even on a fixed Docker version.

### Bug 1 — Missing `Push-Location` in `"image can be built"`

**File**: `tests/sshAgent.Tests.ps1`

**Problem**: The `"image can be built"` Describe block called `docker build ... --file ./windows/${WINDOWSFLAVOR}/Dockerfile .` but had no `BeforeAll` to set the working directory. When Pester runs the test, `Get-Location` is the `tests/` subdirectory, so the build context (`.`) pointed at `tests/` instead of the repo root. Docker could not resolve `./windows/${WINDOWSFLAVOR}/Dockerfile` from there.

**Fix**: Added `BeforeAll { Push-Location -StackName 'build-test' -Path "$PSScriptRoot/.." }` and a matching `AfterAll { Pop-Location -StackName 'build-test' }`.

```diff
+Describe "[$global:IMAGE_TAG] image can be built" {
+    BeforeAll {
+        Push-Location -StackName 'build-test' -Path "$PSScriptRoot/.."
+    }
     It 'builds image' {
         ...
     }
+    AfterAll {
+        ...
+        Pop-Location -StackName 'build-test'
+    }
+}
```

---

### Bug 2 — PowerShell variable scoping bug in `custom-${IMAGE_NAME}`

**File**: `tests/sshAgent.Tests.ps1`

**Problem**: The second test set the custom image name as:

```powershell
$CUSTOM_IMAGE_NAME = "custom-${IMAGE_NAME}"
```

In PowerShell, `${IMAGE_NAME}` inside a double-quoted string expands the **local** variable `$IMAGE_NAME` (not the global `$global:IMAGE_NAME`). `$IMAGE_NAME` is unset in the test's local scope, so `$CUSTOM_IMAGE_NAME` expanded to just `"custom-"` — an invalid image name that made the subsequent `docker build --tag=custom- ...` fail.

**Fix**: Changed to `"custom-$($global:IMAGE_NAME)"` which explicitly dereferences the global.

```diff
-$CUSTOM_IMAGE_NAME = "custom-${IMAGE_NAME}"
+$CUSTOM_IMAGE_NAME = "custom-$($global:IMAGE_NAME)"
```

The same fix was applied in the `AfterAll` cleanup line:
```diff
-# (no cleanup)
+Run-Program 'docker' "rmi -f custom-$($global:IMAGE_NAME)" 60000 | Out-Null
```

**Reference**: PowerShell documentation on [variable scoping](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scopes) and [expandable strings](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_quoting_rules).

---

### Bug 3 — No `AfterAll` image cleanup for built images

**File**: `tests/sshAgent.Tests.ps1`

**Problem**: Neither build test Describe block removed the Docker images it built. On re-run or when multiple test flavors ran on the same host, `docker build --tag=<IMAGE_TAG>` would find an existing image with that tag and fail (or silently use a stale layer cache). The custom image tag `custom-<IMAGE_NAME>` was never cleaned up at all.

**Fix**: Added `AfterAll` blocks with `docker rmi -f` calls:

```powershell
# In "image can be built"
AfterAll {
    Run-Program 'docker' "rmi -f $($global:IMAGE_TAG)" 60000 | Out-Null
    Pop-Location -StackName 'build-test'
}

# In "image can be built with custom build args"
AfterAll {
    Cleanup($global:CONTAINERNAME)
    Run-Program 'docker' "rmi -f custom-$($global:IMAGE_NAME)" 60000 | Out-Null
    Pop-Location -StackName 'agent'
}
```

---

### Bug 4 — `Run-Program` pipe deadlock (synchronous `ReadToEnd`)

**File**: `tests/test_helpers.psm1`

**Problem**: The original implementation read stdout and stderr synchronously and sequentially:

```powershell
$stdout = $proc.StandardOutput.ReadToEnd()
$stderr = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()
```

This is a classic OS pipe deadlock: `ReadToEnd()` on stdout blocks until the process closes its stdout handle. If the process is also waiting to write to stderr (because the stderr pipe buffer is full), both sides block indefinitely. This scenario is likely during a Windows container `docker build`, which produces substantial output on both streams simultaneously.

**Reference**: [Microsoft docs — Process.StandardOutput](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.standardoutput#remarks):

> "To avoid deadlocks, use an asynchronous read operation on at least one of the streams."

**Fix**: Switched to async reads with `ReadToEndAsync()`, awaited after `WaitForExit`:

```powershell
function Run-Program($cmd, $params, [int]$timeoutMs = 120000) {
    ...
    [void]$proc.Start()
    # Async reads avoid stdout/stderr pipe deadlock when both streams produce output
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit($timeoutMs)) {
        Write-Host -ForegroundColor DarkYellow "[timeout] $cmd $params (killed after ${timeoutMs}ms)"
        $proc.Kill()
        $proc.WaitForExit()
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    ...
}
```

---

### Bug 5 — No timeout on `docker build` calls

**File**: `tests/sshAgent.Tests.ps1` and `tests/test_helpers.psm1`

**Problem**: `Run-Program` had no timeout. A `docker build` for a Windows container image (downloading JDK, git, git-lfs, pwsh — all from the internet) can take 20–30 minutes in a clean environment. If the build hung (network issue, Docker daemon stall), the test process would block indefinitely with no diagnostic output.

**Fix**: Added an optional `$timeoutMs` parameter to `Run-Program` (default 120 s for most calls). Build test calls explicitly pass 1800000 ms (30 minutes):

```powershell
# test_helpers.psm1
function Run-Program($cmd, $params, [int]$timeoutMs = 120000) { ... }

# sshAgent.Tests.ps1
$exitCode, $stdout, $stderr = Run-Program 'docker' "build ... ." 1800000
```

The cleanup `docker rmi` calls pass 60000 ms (1 minute).

---

## Additional Improvements

### `Run-ThruSSH` hardening

**File**: `tests/test_helpers.psm1`

Several SSH reliability fixes applied alongside the main fixes:

| Change | Reason |
|--------|--------|
| `icacls /inheritance:r /grant:r` on temp key file | Win32-OpenSSH refuses private keys with overly permissive ACLs (`bad permissions`) |
| `-4` (force IPv4) | Docker's `--publish-all` on Windows binds to `0.0.0.0` (IPv4); `localhost` can resolve to `::1` (IPv6) on dual-stack hosts, causing connection refused |
| `-o ConnectTimeout=30` | Prevents `ssh` from hanging indefinitely if sshd is slow to start |
| `-o BatchMode=yes` | Disables password prompts; fails fast instead of hanging on auth errors |
| `-o ServerAliveInterval=10 -o ServerAliveCountMax=3` | Detects silent connection drops within 30 s |
| `127.0.0.1` instead of `localhost` | Explicit IPv4 avoids DNS resolution ambiguity |
| Explicit `120000` ms timeout on `Run-Program` call | SSH test calls now have the same timeout enforcement as build calls |

### Test key: RSA PKCS#1 → ed25519 (OpenSSH format)

**File**: `tests/sshAgent.Tests.ps1`

The test keypair was a 2048-bit RSA key in legacy PKCS#1 PEM format (`-----BEGIN RSA PRIVATE KEY-----`). Win32-OpenSSH ≥ 9.x (shipped with Windows Server 2025 images) defaults to preferring `PubkeyAcceptedAlgorithms` that include `ssh-ed25519` and `rsa-sha2-*`. The legacy `ssh-rsa` (SHA-1) algorithm is disabled by default in OpenSSH ≥ 8.8.

Replaced with an ed25519 keypair in OpenSSH native format (`-----BEGIN OPENSSH PRIVATE KEY-----`), which works across all supported Windows flavors and OpenSSH versions.

**Reference**: [OpenSSH 8.8 release notes](https://www.openssh.com/txt/release-8.8) — deprecation of `ssh-rsa` SHA-1 signatures.

### `Cleanup` robustness

**File**: `tests/test_helpers.psm1`

`docker kill` and `docker rm` raise non-terminating errors when the container doesn't exist (e.g., on first run or after a crash). Wrapped both in `try/catch` so pre-test cleanup never aborts the test setup:

```diff
-docker kill "$name" 2>&1 | Out-Null
-docker rm -fv "$name" 2>&1 | Out-Null
+try { docker kill "$name" 2>&1 | Out-Null } catch {}
+try { docker rm -fv "$name" 2>&1 | Out-Null } catch {}
```

---

## Files Changed

| File | Nature of change |
|------|-----------------|
| `tests/sshAgent.Tests.ps1` | Re-enable 2 Describe blocks; fix Push-Location, variable scoping, image cleanup; replace RSA keys with ed25519 |
| `tests/test_helpers.psm1` | Run-Program: async I/O + timeout; Run-ThruSSH: ACLs, IPv4, SSH options; Cleanup: try/catch |

## References

| Reference | URL |
|-----------|-----|
| jenkinsci/docker-ssh-agent#704 | https://github.com/jenkinsci/docker-ssh-agent/issues/704 |
| GHSA-hfg8-hc9c-6c3h (CVE tar path-traversal) | https://github.com/moby/go-archive/security/advisories/GHSA-hfg8-hc9c-6c3h |
| moby/go-archive#45 (hardening PR) | https://github.com/moby/go-archive/pull/45 |
| moby/moby#53247 (vendor go-archive v0.3.0) | https://github.com/moby/moby/pull/53247 |
| moby/go-archive#40 (POSIX normalization) | https://github.com/moby/go-archive/pull/40 |
| moby/go-archive#41 (POSIX normalization) | https://github.com/moby/go-archive/pull/41 |
| moby/moby#53305 (vendor go-archive v0.3.3) | https://github.com/moby/moby/pull/53305 |
| moby/moby release docker-v29.7.2 | https://github.com/moby/moby/releases/tag/docker-v29.7.2 |
| .NET Process.StandardOutput deadlock warning | https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.standardoutput#remarks |
| PowerShell variable scoping | https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scopes |
| OpenSSH 8.8 release notes (ssh-rsa deprecation) | https://www.openssh.com/txt/release-8.8 |
