---
name: feedback-test-helpers-ps74
description: Cleanup/CleanupNetwork in test_helpers.psm1 need try/catch for PS7.4+ compatibility
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 0b5d9042-b15a-470d-a677-574996815442
  modified: 2026-09-08T20:13:04.929Z
---

PowerShell 7.4+ introduced `$PSNativeCommandUseErrorActionPreference = $true` as the default.
This means native commands (like `docker kill`, `docker rm`, `docker network rm`) that exit
with a non-zero code will throw when `$ErrorActionPreference = 'Stop'` is set — even with
`2>&1 | Out-Null` to suppress output.

Pester 6.x runs discovery in an isolated runspace that inherits the parent's error preference.
When `Cleanup($name)` or `CleanupNetwork($name)` is called at the top level of a test file
(pre-test cleanup of a nonexistent container/network), the non-zero exit throws a
`System.Management.Automation.RemoteException` during discovery — causing ALL tests to fail
with "Found 0 tests."

**Fix already applied** in `tests/test_helpers.psm1`:
```powershell
# Cleanup:
try { docker kill "$name" 2>&1 | Out-Null } catch {}
try { docker rm -fv "$name" 2>&1 | Out-Null } catch {}

# CleanupNetwork:
try { docker network rm $name 2>&1 | Out-Null } catch {}
```

**Why**: Cleanup/CleanupNetwork are best-effort pre/post test teardown. Errors mean the
resource didn't exist, which is fine.

**How to apply**: If Pester tests fail at "Discovery" phase with "No such container" or
"network not found" errors, this pattern is the fix. Check all native command calls in
test helper functions that run at the top level of test scripts.
