# docker-ssh-agent — Windows EC2 Build Script Session Notes

## Session: SSH connectivity to Windows EC2 via EIC — portproxy debugging

### Date
2026-09-06

### Context
Building and testing Windows Docker images on-demand using an EC2 Windows instance. The script `build-windows-on-ec2.sh` launches a Windows EC2 instance, SSHes into it, installs Docker, and runs the Jenkins-managed build.

### Initial State
- Script existed but SSH never connected to the Windows instance
- Port 22 is blocked from the internet in this AWS account
- EC2 Instance Connect Endpoint (EIC) is used as the SSH proxy

### Core Problem (UNRESOLVED at end of session)
**sshd is not listening on port 22** on the Windows instance, even though:
- EC2 Launch v2 reports `AgentCommandErrorCode=0` (user-data ran)
- portproxy on port 3389 IS running (accepts TCP, FINs immediately because port 22 is empty)

### Architecture Decisions Made

#### EIC + portproxy approach (current)
- EIC only supports remote ports **22 and 3389** (hard AWS constraint — WinRM/5985 rejected)
- TermService (RDP) is stopped in user-data to free port 3389
- `netsh interface portproxy` forwards port 3389 → 127.0.0.1:22
- Script connects via `ssh -p 3389` through EIC tunnel with `--remote-port 3389`
- sshd stays configured on port 22

#### Key resources (reuse these across attempts)
```
VPC:    vpc-0132f5ac146db9c2a
Subnet: subnet-0aa566db9f5d346bb
SG:     sg-0a49de1bcbec58e0d  (TCP 22, 3389, 5985 from 10.250.0.0/24)
EIC:    eice-0969b788085e51fc4
Key:    KEY_NAME=hlemeur-test  SSH_KEY_PATH=/tmp/hlemeur-test.pem
AMI:    ami-05b8af58f7410b671 (Windows_Server-2025-English-Core-Base)
Region: us-east-1
Profile: cloudbees-cloud-platform-clusters
```

### Issues Identified

#### 1. sshd not starting (UNRESOLVED)
**Problem**: portproxy accepts TCP on port 3389 and FINs immediately — meaning portproxy is running but port 22 (sshd) has nothing.  
**Probe evidence**:
- Port 22 via EIC: "Unable to connect to target" → Windows Firewall blocking or sshd not bound to port 22  
- Port 3389 via EIC: "0 bytes" → portproxy running, forwarding to 22 where nothing listens  
**Note**: SG allows both port 22 and 3389 from 10.250.0.0/24 — SG is NOT the problem.  
**Hypothesis**: sshd service is not starting; user-data may be interfering with EC2 Launch v2's own OpenSSH setup, or the Windows Server 2025 Core Base AMI requires explicit `Add-WindowsCapability` to install OpenSSH.  
**Status**: UNRESOLVED. Next attempt: see "Next Steps" below.

#### 2. SSH key format issue (UNRESOLVED)
**Problem**: `/tmp/hlemeur-test.pem` is PKCS#1 RSA format (`BEGIN RSA PRIVATE KEY`). OpenSSH 10.3 on macOS shows `type -1` and refuses to load it as an identity.  
**Evidence**: `ssh -v -i /tmp/hlemeur-test.pem` logs `no pubkey loaded from /tmp/hlemeur-test.pem type -1`  
**Note**: `ssh-keygen -y -f /tmp/hlemeur-test.pem` DOES read it successfully — it's readable but not usable as ssh identity.  
**Fix options**:
- `openssl pkcs8 -topk8 -nocrypt -in /tmp/hlemeur-test.pem -out /tmp/hlemeur-test-openssh.pem`
- OR generate a new ED25519 key, import it into AWS as `hlemeur-test`, and re-launch instances
- OR set `IdentityFile` via `~/.ssh/config` with `AddKeysToAgent yes`  
**Status**: UNRESOLVED. Must fix before SSH will work even if sshd starts.

#### 3. EIC blocks WinRM port 5985
**Problem**: EIC only supports remote ports 22 and 3389. WinRM (5985) is explicitly rejected.  
**Fix**: Use portproxy (port 3389 → 22) or configure sshd directly on port 3389.

### Current Script State (`build-windows-on-ec2.sh`)

**EIC proxy**: uses `--remote-port 3389`  
**ssh/scp**: connect to port 3389  
**SG rule**: port 3389 (for portproxy)  
**User-data**: complex script that:
1. Checks if sshd service exists; installs Win32-OpenSSH from GitHub if not
2. Creates `sshd_config` if missing (Port 22, ListenAddress 0.0.0.0)
3. Generates host keys with `ssh-keygen -A`
4. Sets ACLs on host keys with `icacls`
5. Writes `administrators_authorized_keys` from EC2 metadata
6. Sets PowerShell as default shell
7. Adds firewall rules for port 22
8. Stops TermService (frees port 3389)
9. Starts iphlpsvc service
10. Sets up portproxy: 3389 → 127.0.0.1:22
11. Adds firewall rule for port 3389

**Optional env vars now supported**:
```bash
EIC_ENDPOINT_ID=eice-0969b788085e51fc4  # skip EIC creation
SUBNET_ID=subnet-0aa566db9f5d346bb
VPC_ID=vpc-0132f5ac146db9c2a
SECURITY_GROUP_ID=sg-0a49de1bcbec58e0d
IAM_INSTANCE_PROFILE=...
SSH_KEY_PATH=/tmp/hlemeur-test.pem
KEY_NAME=hlemeur-test
```

### Next Steps (Priority Order)

#### Step 1: Fix the SSH key
```bash
# Option A: convert to PKCS8 (may work with OpenSSH 10.3)
openssl pkcs8 -topk8 -nocrypt -in /tmp/hlemeur-test.pem -out /tmp/hlemeur-test-pkcs8.pem
chmod 600 /tmp/hlemeur-test-pkcs8.pem
ssh-add /tmp/hlemeur-test-pkcs8.pem

# Option B: generate new ED25519 key and import to AWS
ssh-keygen -t ed25519 -f /tmp/hlemeur-test-ed25519 -N ""
aws ec2 import-key-pair --key-name hlemeur-test-ed25519 \
  --public-key-material fileb:///tmp/hlemeur-test-ed25519.pub \
  --region us-east-1 --profile cloudbees-cloud-platform-clusters
# Then use KEY_NAME=hlemeur-test-ed25519 SSH_KEY_PATH=/tmp/hlemeur-test-ed25519
```

#### Step 2: Simplify user-data — configure sshd directly on port 3389
Instead of portproxy, configure sshd itself to listen on port 3389:
```powershell
<powershell>
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# Free port 3389 (RDP)
Stop-Service -Name TermService -Force -ErrorAction SilentlyContinue
Set-Service  -Name TermService -StartupType Disabled -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

$sshDir = 'C:\ProgramData\ssh'
if (-not (Test-Path $sshDir)) { New-Item -Path $sshDir -ItemType Directory -Force | Out-Null }

# sshd on port 3389 — no portproxy needed
@(
    'Port 3389',
    'ListenAddress 0.0.0.0',
    'AuthorizedKeysFile .ssh/authorized_keys',
    'Match Group administrators',
    '       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys',
    'Subsystem sftp sftp-server.exe'
) | Set-Content "$sshDir\sshd_config" -Encoding UTF8 -Force

# Install OpenSSH if not present
$svc = Get-Service sshd -ErrorAction SilentlyContinue
if (-not $svc) {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue
    $svc = Get-Service sshd -ErrorAction SilentlyContinue
}

if ($svc) {
    # Generate host keys
    if (-not (Test-Path "$sshDir\ssh_host_ed25519_key")) {
        & 'C:\Windows\System32\OpenSSH\ssh-keygen.exe' -A 2>&1
    }
    foreach ($f in (Get-ChildItem "$sshDir\ssh_host_*_key" -ErrorAction SilentlyContinue)) {
        icacls $f.FullName /inheritance:r /grant 'SYSTEM:(F)' /grant 'Administrators:(F)'
    }
    # Inject EC2 key pair
    try {
        $pubKey = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 15 `
            'http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key').Content.Trim()
        if ($pubKey -match '^ssh-') {
            $f = "$sshDir\administrators_authorized_keys"
            Set-Content -Path $f -Value $pubKey -Encoding UTF8 -Force
            icacls $f /inheritance:r /grant 'SYSTEM:(F)' /grant 'Administrators:(F)'
        }
    } catch { Write-Host "key fetch failed: $_" }

    # Firewall: allow port 3389 for sshd (existing RDP rule may cover this)
    Remove-NetFirewallRule -Name 'sshd-3389' -ErrorAction SilentlyContinue
    New-NetFirewallRule -Name 'sshd-3389' -DisplayName 'SSH on 3389' `
        -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow -Enabled True

    Set-Service  -Name sshd -StartupType Automatic
    Restart-Service sshd -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Write-Host "sshd: $((Get-Service sshd).Status)"
}
</powershell>
```

This eliminates portproxy entirely — sshd listens directly on 3389 which EIC can reach.

#### Step 3: Reuse existing resources
```bash
EIC_ENDPOINT_ID=eice-0969b788085e51fc4 \
SUBNET_ID=subnet-0aa566db9f5d346bb \
VPC_ID=vpc-0132f5ac146db9c2a \
SECURITY_GROUP_ID=sg-0a49de1bcbec58e0d \
SSH_KEY_PATH=/tmp/hlemeur-test-pkcs8.pem \
KEY_NAME=hlemeur-test \
./build-windows-on-ec2.sh nanoserver-ltsc2022_jdk25 \
    > /tmp/build-windows-v6.log 2>&1
```

### Last Known Instance State
- Instance `i-07b6158c6d6a54a7e` — STOPPING (cleanup triggered when SSH timed out)
- Probe: port 3389 = portproxy running; port 22 = nothing; sshd not started
- Console output: `AgentCommandErrorCode=0`, `Windows is Ready to use` — EC2 Launch ran user-data but PowerShell logs go to EC2 Launch log file (not readable without SSH)

---

## Appendix: Session Interactions

### Interaction 1: RDP inquiry
**User**: "can the script use RDP?"
**Action**: Investigated RDP+EIC feasibility
**Result**: EIC supports port 3389 but RDP is a different protocol from SSH; pywinrm via WinRM blocked by EIC (port 5985 rejected)

### Interaction 2: nc not available
**User**: "again, you can't use `nc` from my machine"
**Action**: Switched to curl-based TCP probing via EIC tunnel
**Result**: Confirmed portproxy on 3389 = "0 bytes", port 22 = "Unable to connect"

### Interaction 3: SSH key location
**User**: "hum... you created this key earlier, find it yourself" / "you might have used /tmp/ in the past"
**Action**: Found key at `/tmp/hlemeur-test.pem` from session transcript
**Result**: Key found but has PKCS#1 format issue (OpenSSH 10.3 type -1)

### Interaction 4: JumpCloud
**User**: "I have a jumpcloud agent running on my machine, that might be the cause of the tunnel closing"
**Action**: Documented; advised testing with direct tool calls rather than background tunnel
**Result**: Not confirmed as root cause

### Interaction 5: Fresh session
**User**: "I'll restart a fresh session. Write down everything needed to continue later"
**Action**: Writing this document + updating memory
