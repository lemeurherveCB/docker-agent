---
name: feedback-build-patterns
description: "Build and git patterns for this project — what works, what to watch for"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 0b5d9042-b15a-470d-a677-574996815442
  modified: 2026-09-08T20:13:17.094Z
---

## SSH key location

The EC2 private key is at `/tmp/hlemeur-test.pem` (not in `~/.ssh`).
Always use `SSH_KEY_PATH=/tmp/hlemeur-test.pem`.

**Why**: User keeps keys in /tmp for this project. ~/.ssh contains no .pem files.

## Git commits

Always use `--no-gpg-sign` on commits (GPG signing fails in this environment).
See [[feedback-test-helpers-ps74]] for project conventions.

## Docker layer cache corruption

When a Docker build fails mid-COPY on Windows containers, the windowsfilter layer
cache can be left in an inconsistent state. Subsequent builds may fail with "Access is
denied" on the same COPY step even after fixing the underlying issue.

Fix: set `PRUNE_DOCKER=1` when running `build-windows-on-ec2.sh` to run
`docker builder prune -a -f` before the build. Only needed after a failed build;
normal rebuilds can reuse the cache.

## Extraction script quoting

The inline PowerShell for repo extraction in `build-windows-on-ec2.sh` produces a benign
`Continue=Stop` error on Windows. This does NOT stop the extraction — the tar command
succeeds and you see "Repository extracted." or "Extracted." The error is cosmetic and
comes from PowerShell parsing `$ErrorActionPreference='Stop'` when embedded in a bash
heredoc with double-quote escaping.

## /tmp cleanup between runs

If a background task fails mid-run, `/tmp/docker-agent-*.tar.gz` may be left behind.
`mktemp` will fail on the next run ("File exists"). Always run:
```bash
rm -f /tmp/docker-agent-*.tar.gz
```
before retrying a build script.
