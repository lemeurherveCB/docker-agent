# docker-ssh-agent — Windows EC2 Build Script Session Notes

## Session: sshd fix — direct port 3389, SSH key PKCS8 conversion

### Date
2026-09-06 (session 2)

### Context
Resuming from session 1 which ended with two unresolved blockers preventing SSH into the Windows EC2 instance:
1. SSH key format issue (PKCS#1 not loadable by OpenSSH 10.3 on macOS)
2. sshd not starting on the Windows instance (portproxy approach failed silently)

Goal: build and test `nanoserver-ltsc2022_jdk25`.

### Initial State (from session 1)
- `build-windows-on-ec2.sh`: portproxy user-data (sshd on port 22, portproxy 3389→22)
- `/tmp/hlemeur-test.pem`: PKCS#1 RSA format — OpenSSH 10.3 shows `type -1`, refuses to load
- 2 stopped instances from previous attempts (old user-data, not reusable for new SSH test)
- 2 active EIC endpoints (reusable)

### Issues Fixed

#### 1. SSH key format (PKCS#1 → PKCS8)
**Problem**: `/tmp/hlemeur-test.pem` is PKCS#1 RSA (`BEGIN RSA PRIVATE KEY`). OpenSSH 10.3 on macOS (from JumpCloud or Homebrew) refuses to load it as an identity — `no pubkey loaded … type -1`.  
**Fix**: `openssl pkcs8 -topk8 -nocrypt -in /tmp/hlemeur-test.pem -out /tmp/hlemeur-test-pkcs8.pem`  
**Result**: `/tmp/hlemeur-test-pkcs8.pem` verified — `ssh-keygen -y` extracts public key successfully. No new AWS key import needed.

#### 2. user-data: replaced portproxy approach with sshd directly on port 3389
**Problem**: The portproxy approach (sshd on port 22, portproxy 3389→22) failed on all 4 instances. sshd never started on port 22. Root cause: `Add-WindowsCapability` was absent — if the AMI's OpenSSH wasn't pre-installed, the GitHub fallback may have failed. The extra portproxy layer added another failure point.  
**Fix**: Rewrote user-data to:
1. Stop/disable TermService (RDP) first to free port 3389
2. `Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0` to install sshd reliably
3. Configure `sshd_config` with `Port 3389` directly — EIC reaches it, no portproxy
4. Generate host keys, restrict ACLs, inject EC2 key pair
5. Set PowerShell as default SSH shell, add firewall rule for 3389, start sshd
**Result**: Portproxy eliminated entirely. Simpler, fewer failure points.

#### 3. Backslash corruption in user-data (workflow agent bug, fixed inline)
**Problem**: The workflow agent that rewrote user-data stripped backslashes from Windows paths (e.g., `'C:ProgramDatassh'` instead of `'C:\ProgramData\ssh'`). Shellcheck passed (it can't parse PowerShell), so the automated verify step missed it.  
**Fix**: 8 Edit operations to restore correct paths:
- `$sshDir = 'C:\ProgramData\ssh'`
- `"$sshDir\sshd_config"`, `"$sshDir\ssh_host_ed25519_key"`, etc.
- `'C:\Windows\System32\OpenSSH\ssh-keygen.exe'`
- `'C:\Program Files\OpenSSH-Win64\ssh-keygen.exe'`
- `'HKLM:\SOFTWARE\OpenSSH'`
- `'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'`

### Final Script State

**user-data approach**: sshd on port 3389 directly, no portproxy  
**SSH key to use**: `/tmp/hlemeur-test-pkcs8.pem` (KEY_NAME=hlemeur-test)  
**Shellcheck**: PASS (0 warnings)

### Reusable AWS Resources
```
VPC:    vpc-0132f5ac146db9c2a
Subnet: subnet-0aa566db9f5d346bb
SG:     sg-0a49de1bcbec58e0d  (TCP 3389 from 10.250.0.0/24)
EIC:    eice-0969b788085e51fc4  (state: create-complete)
AMI:    ami-05b8af58f7410b671  (Windows_Server-2025-English-Core-Base)
Region: us-east-1
Profile: cloudbees-cloud-platform-clusters
```

**IMPORTANT**: Do NOT resume stopped instances `i-07b6158c6d6a54a7e` or `i-05e7a11caeafbe174` for the new SSH test — they have the old portproxy user-data already baked in (user-data only runs on first boot). Launch a new instance with the fixed user-data.

### Run Command

```bash
EIC_ENDPOINT_ID=eice-0969b788085e51fc4 \
SUBNET_ID=subnet-0aa566db9f5d346bb \
VPC_ID=vpc-0132f5ac146db9c2a \
SECURITY_GROUP_ID=sg-0a49de1bcbec58e0d \
SSH_KEY_PATH=/tmp/hlemeur-test-pkcs8.pem \
KEY_NAME=hlemeur-test \
AMI_ID=ami-05b8af58f7410b671 \
AWS_PROFILE=cloudbees-cloud-platform-clusters \
BAKE_TARGET=nanoserver-ltsc2022_jdk25 \
./build-windows-on-ec2.sh \
  2>&1 | tee /tmp/build-windows-v7.log
```

### Cleanup (stopped instances from session 1 — EBS still billing)
```bash
AWS_PROFILE=cloudbees-cloud-platform-clusters \
  ./build-windows-on-ec2.sh --delete i-07b6158c6d6a54a7e

AWS_PROFILE=cloudbees-cloud-platform-clusters \
  ./build-windows-on-ec2.sh --delete i-05e7a11caeafbe174
```

---

## Appendix: Session Interactions

### Interaction 1: Resume previous work
**User**: "look at the previous session .md file and resume the work. The goal is to be able to use the script to build and test a nanoserver-ltsc2022_jdk25 image."  
**Action**: Read session notes, memory, and script; launched ultracode workflow to audit + fix both blockers.  
**Result**: SSH key converted, user-data rewritten, backslash bug fixed manually, shellcheck clean.

### Interaction 2: Backslash question
**User**: "can those missing backslashes be the cause of the errors in the previous session?"  
**Action**: Explained — no, the missing backslashes are a NEW bug introduced by the workflow agent in this session (not present in session 1). Session 1 failures were architectural (portproxy + missing Add-WindowsCapability).
