#!/usr/bin/env bash
# Runs the minimal setpd-test Dockerfile on an EC2 Windows instance to determine
# whether USER jenkins works at container runtime when setpd.exe ran at build time.
#
# Usage:
#   SSH_KEY_PATH=~/.ssh/my-key.pem ./run-setpd-test-on-ec2.sh <instance-id>
#
# Expected output: "SETPD-TEST OUTPUT: user manager\jenkins"  → USER jenkins works ✅
# Or a crash / non-zero exit → volatile hive recreated at runtime ❌
#
# REQUIRED:
#   SSH_KEY_PATH        Local path to the private key file
#
# OPTIONAL:
#   AWS_PROFILE         AWS CLI profile (default: cloudbees-cloud-platform-clusters)
#   AWS_REGION          AWS region (default: us-east-1)
#   EIC_ENDPOINT_ID     Existing EC2 Instance Connect Endpoint to reuse

set -euo pipefail

SSH_KEY_PATH="${SSH_KEY_PATH:-}"
SSH_USER="${SSH_USER:-Administrator}"
AWS_PROFILE="${AWS_PROFILE:-cloudbees-cloud-platform-clusters}"
AWS_REGION="${AWS_REGION:-us-east-1}"
EIC_ENDPOINT_ID="${EIC_ENDPOINT_ID:-}"

[[ -n "${AWS_PROFILE}" ]] && export AWS_PROFILE

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_WORK_DIR='C:/docker-agent'

INSTANCE_ID=""
PUBLIC_IP=""
_EXIT_CODE=0

log() { echo "[$(date '+%H:%M:%S')] $*"; }

_ssh_proxy_args() {
    local -n _out=$1
    _out=()
    if [[ -n "${EIC_ENDPOINT_ID}" ]]; then
        local _cmd="aws ec2-instance-connect open-tunnel --instance-id ${INSTANCE_ID} --remote-port 22 --region ${AWS_REGION}"
        [[ -n "${AWS_PROFILE}" ]] && _cmd="${_cmd} --profile ${AWS_PROFILE}"
        _out=(-o "ProxyCommand=${_cmd}")
    fi
}

ssh_run() {
    local -a _proxy
    _ssh_proxy_args _proxy
    ssh -i "${SSH_KEY_PATH}" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=15 \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=10 \
        -p 22 \
        "${_proxy[@]}" \
        "${SSH_USER}@${PUBLIC_IP}" "$@"
}

scp_to() {
    local -a _proxy
    _ssh_proxy_args _proxy
    scp -i "${SSH_KEY_PATH}" \
        -o StrictHostKeyChecking=no \
        -P 22 \
        "${_proxy[@]}" \
        "$@"
}

cleanup() {
    if [[ -n "${INSTANCE_ID}" ]]; then
        log "Stopping instance ${INSTANCE_ID}..."
        aws ec2 stop-instances \
            --instance-ids "${INSTANCE_ID}" \
            --region "${AWS_REGION}" > /dev/null 2>&1 || \
            log "WARNING: could not stop ${INSTANCE_ID}."
    fi
    exit "${_EXIT_CODE}"
}
trap cleanup EXIT

RESUME_INSTANCE_ID=""
if [[ "${1:-}" =~ ^i-[0-9a-f]+$ ]]; then
    RESUME_INSTANCE_ID="${1}"
fi

: "${SSH_KEY_PATH:?SSH_KEY_PATH is required}"
[[ -n "${RESUME_INSTANCE_ID}" ]] || { echo "Usage: $0 <instance-id>" >&2; _EXIT_CODE=1; exit 1; }

LOG_FILE="/tmp/setpd-test-$(date +%s).log"
exec > >(tee "${LOG_FILE}") 2>&1
echo "Log: ${LOG_FILE}"

log "Resuming instance ${RESUME_INSTANCE_ID}..."
INSTANCE_ID="${RESUME_INSTANCE_ID}"

_istate=$(aws ec2 describe-instances \
    --region "${AWS_REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --query "Reservations[0].Instances[0].State.Name" \
    --output text)

case "${_istate}" in
    stopped)
        log "  Instance stopped — starting..."
        aws ec2 start-instances --instance-ids "${INSTANCE_ID}" --region "${AWS_REGION}" > /dev/null
        aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}" --region "${AWS_REGION}"
        aws ec2 wait instance-status-ok --instance-ids "${INSTANCE_ID}" --region "${AWS_REGION}"
        ;;
    running) log "  Already running." ;;
    *)
        log "ERROR: Instance is in state '${_istate}'"
        _EXIT_CODE=1; exit 1
        ;;
esac

PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "${INSTANCE_ID}" \
    --region "${AWS_REGION}" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)
log "Instance at ${PUBLIC_IP}"

VPC_ID=$(aws ec2 describe-instances \
    --instance-ids "${INSTANCE_ID}" \
    --region "${AWS_REGION}" \
    --query "Reservations[0].Instances[0].VpcId" \
    --output text)

if [[ -z "${EIC_ENDPOINT_ID}" ]]; then
    EIC_ENDPOINT_ID=$(aws ec2 describe-instance-connect-endpoints \
        --region "${AWS_REGION}" \
        --filters "Name=vpc-id,Values=${VPC_ID}" "Name=state,Values=create-complete" \
        --query "InstanceConnectEndpoints[0].InstanceConnectEndpointId" \
        --output text 2>/dev/null || true)
    [[ "${EIC_ENDPOINT_ID}" == "None" ]] && EIC_ENDPOINT_ID=""
fi
[[ -n "${EIC_ENDPOINT_ID}" ]] && log "EIC endpoint: ${EIC_ENDPOINT_ID}"

log "Waiting for SSH..."
SSH_READY=false
for attempt in $(seq 1 40); do
    if ssh_run "echo ready" > /dev/null 2>&1; then
        SSH_READY=true
        break
    fi
    log "  attempt ${attempt}/40 — retrying in 20s..."
    sleep 20
done
${SSH_READY} || { log "ERROR: SSH never became available."; _EXIT_CODE=1; exit 1; }
log "SSH ready."

# Upload only the files needed for the minimal test
log "Uploading repo..."
TMPTAR=$(mktemp /tmp/docker-agent-XXXXXX.tar.gz)
tar \
    --exclude='.git' \
    --exclude='target' \
    --exclude='bats' \
    --exclude='claude-from-docker-ssh-agent' \
    --exclude='*.tar.gz' \
    -czf "${TMPTAR}" \
    -C "${REPO_DIR}" .
log "Packaged: $(du -sh "${TMPTAR}" | cut -f1)"
scp_to "${TMPTAR}" "${SSH_USER}@${PUBLIC_IP}:C:/repo.tar.gz"
rm -f "${TMPTAR}"

ssh_run "powershell -NonInteractive -NoProfile -Command \"\
    \$ErrorActionPreference='Stop'; \
    if (Test-Path '${REMOTE_WORK_DIR}') { Remove-Item -Recurse -Force '${REMOTE_WORK_DIR}' }; \
    New-Item -ItemType Directory -Path '${REMOTE_WORK_DIR}' | Out-Null; \
    tar -xzf C:/repo.tar.gz -C '${REMOTE_WORK_DIR}'; \
    Remove-Item -Force C:/repo.tar.gz; \
    Write-Host 'Extracted.'\""

# Write the test script
TESTPS1=$(mktemp /tmp/setpd-test-XXXXXX.ps1)
cat > "${TESTPS1}" << 'PS1'
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
Set-Location C:\docker-agent

Write-Host ''
Write-Host ('=' * 60)
Write-Host 'Building setpd-test:latest  (nanoserver-ltsc2025)'
Write-Host ('=' * 60)
docker build `
    --build-arg WINDOWS_VERSION_TAG=ltsc2025 `
    -t setpd-test:latest `
    -f windows/nanoserver/Dockerfile.setpd-test `
    . 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "RESULT: BUILD FAILED (exit $LASTEXITCODE)"
    exit $LASTEXITCODE
}

Write-Host ''
Write-Host ('=' * 60)
Write-Host 'Running setpd-test'
Write-Host 'CMD: cmd.exe /c whoami'
Write-Host 'Expected output if USER jenkins works: user manager\jenkins'
Write-Host ('=' * 60)
$out = docker run --rm setpd-test:latest 2>&1
$rc  = $LASTEXITCODE
Write-Host "SETPD-TEST OUTPUT : $out"
Write-Host "SETPD-TEST EXIT   : $rc"

docker rmi setpd-test:latest 2>&1 | Out-Null

if ($rc -eq 0) {
    Write-Host ''
    Write-Host 'RESULT: USER jenkins WORKS at runtime ✔'
} else {
    Write-Host ''
    Write-Host 'RESULT: USER jenkins FAILS at runtime ✘  (volatile hive recreated on each container start)'
}
exit $rc
PS1

scp_to "${TESTPS1}" "${SSH_USER}@${PUBLIC_IP}:C:/setpd-test.ps1"
rm -f "${TESTPS1}"

log "Running minimal test..."
TEST_EXIT=0
ssh_run "powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File C:/setpd-test.ps1" || TEST_EXIT=$?
ssh_run "powershell -NonInteractive -NoProfile -Command \"Remove-Item -Force C:/setpd-test.ps1\"" || true

log "Minimal test exit: ${TEST_EXIT}"
_EXIT_CODE="${TEST_EXIT}"
