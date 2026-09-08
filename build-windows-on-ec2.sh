#!/usr/bin/env bash
# Builds and tests Windows Docker images (docker-agent) on an EC2 Windows instance.
# Adapted from docker-ssh-agent/build-windows-on-ec2.sh for docker-agent (uses make.ps1).
#
# LIFECYCLE
#   - On normal exit (success or failure): the EC2 instance is STOPPED (not terminated).
#   - Pass an existing instance ID as the first argument to resume a stopped instance.
#
# MODES
#   Build (reuse existing stopped instance):
#     SSH_KEY_PATH=~/.ssh/my-key.pem IMAGE_TYPES="nanoserver-ltsc2025" \
#     ./build-windows-on-ec2.sh i-0abcdef1234567890
#
# REQUIRED:
#   SSH_KEY_PATH        Local path to the private key file
#
# OPTIONAL:
#   IMAGE_TYPES         Space-separated list of Windows image types to build
#                       (default: "nanoserver-ltsc2025")
#   JAVA_RELEASES       Space-separated list of Java major versions to build
#                       (default: "21")
#   AWS_PROFILE         AWS CLI profile to use
#   AWS_REGION          AWS region (default: us-east-1)
#   EIC_ENDPOINT_ID     Existing EC2 Instance Connect Endpoint to reuse

set -euo pipefail

SSH_KEY_PATH="${SSH_KEY_PATH:-}"
IMAGE_TYPES="${IMAGE_TYPES:-nanoserver-ltsc2025}"
JAVA_RELEASES="${JAVA_RELEASES:-21}"
PRUNE_DOCKER="${PRUNE_DOCKER:-0}"
SSH_USER="${SSH_USER:-Administrator}"
AWS_PROFILE="${AWS_PROFILE:-}"
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
        log "Stopping instance ${INSTANCE_ID} (reuse with: $0 ${INSTANCE_ID})..."
        aws ec2 stop-instances \
            --instance-ids "${INSTANCE_ID}" \
            --region "${AWS_REGION}" > /dev/null 2>&1 || \
            log "WARNING: could not stop ${INSTANCE_ID}."
    fi
    exit "${_EXIT_CODE}"
}
trap cleanup EXIT

# ── Argument parsing ──────────────────────────────────────────────────────────
RESUME_INSTANCE_ID=""
if [[ "${1:-}" =~ ^i-[0-9a-f]+$ ]]; then
    RESUME_INSTANCE_ID="${1}"
fi

: "${SSH_KEY_PATH:?SSH_KEY_PATH is required}"
[[ -n "${RESUME_INSTANCE_ID}" ]] || { echo "Usage: $0 <instance-id>" >&2; _EXIT_CODE=1; exit 1; }

LOG_FILE="/tmp/build-docker-agent-$(date +%s).log"
exec > >(tee "${LOG_FILE}") 2>&1
echo "Log: ${LOG_FILE}"

# ── Resume instance ───────────────────────────────────────────────────────────
log "Resuming instance ${RESUME_INSTANCE_ID}..."
INSTANCE_ID="${RESUME_INSTANCE_ID}"

_istate=$(aws ec2 describe-instances \
    --region "${AWS_REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --query "Reservations[0].Instances[0].State.Name" \
    --output text)

case "${_istate}" in
    stopped)
        log "  Instance is stopped — starting..."
        aws ec2 start-instances --instance-ids "${INSTANCE_ID}" --region "${AWS_REGION}" > /dev/null
        log "  Waiting for 'running' state..."
        aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}" --region "${AWS_REGION}"
        aws ec2 wait instance-status-ok --instance-ids "${INSTANCE_ID}" --region "${AWS_REGION}"
        ;;
    running) log "  Instance already running." ;;
    *)
        log "ERROR: Instance ${INSTANCE_ID} is in state '${_istate}' — cannot resume."
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

# Look up existing EIC endpoint unless provided
if [[ -z "${EIC_ENDPOINT_ID}" ]]; then
    EIC_ENDPOINT_ID=$(aws ec2 describe-instance-connect-endpoints \
        --region "${AWS_REGION}" \
        --filters "Name=vpc-id,Values=${VPC_ID}" "Name=state,Values=create-complete" \
        --query "InstanceConnectEndpoints[0].InstanceConnectEndpointId" \
        --output text 2>/dev/null || true)
    [[ "${EIC_ENDPOINT_ID}" == "None" ]] && EIC_ENDPOINT_ID=""
fi
[[ -n "${EIC_ENDPOINT_ID}" ]] && log "EIC endpoint: ${EIC_ENDPOINT_ID}"

# ── Wait for SSH ──────────────────────────────────────────────────────────────
log "Waiting for SSH..."
SSH_READY=false
for attempt in $(seq 1 40); do
    if ssh_run "echo ready" > /dev/null 2>&1; then
        SSH_READY=true
        break
    fi
    log "  SSH attempt ${attempt}/40 — retrying in 20s..."
    sleep 20
done
${SSH_READY} || { log "ERROR: SSH never became available."; _EXIT_CODE=1; exit 1; }
log "SSH is ready."

# ── Package and upload repository ─────────────────────────────────────────────
log "Packaging repository..."
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

log "Uploading to ${PUBLIC_IP}..."
scp_to "${TMPTAR}" "${SSH_USER}@${PUBLIC_IP}:C:/repo.tar.gz"
rm -f "${TMPTAR}"

log "Extracting on remote..."
ssh_run "powershell -NonInteractive -NoProfile -Command \"\
    \$ErrorActionPreference='Stop'; \
    if (Test-Path '${REMOTE_WORK_DIR}') { Remove-Item -Recurse -Force '${REMOTE_WORK_DIR}' }; \
    New-Item -ItemType Directory -Path '${REMOTE_WORK_DIR}' | Out-Null; \
    tar -xzf C:/repo.tar.gz -C '${REMOTE_WORK_DIR}'; \
    Remove-Item -Force C:/repo.tar.gz; \
    Write-Host 'Repository extracted.'\""

# ── Write orchestrator script ─────────────────────────────────────────────────
ORCHESTRATOR_PS1=$(mktemp /tmp/orchestrate-XXXXXX.ps1)

read -ra _image_types_arr  <<< "${IMAGE_TYPES}"
read -ra _java_releases_arr <<< "${JAVA_RELEASES}"
image_types_ps1=$(printf ", '%s'" "${_image_types_arr[@]}"  | cut -c3-)
java_releases_ps1=$(printf ", '%s'" "${_java_releases_arr[@]}" | cut -c3-)

cat > "${ORCHESTRATOR_PS1}" << PS1_EOF
\$ErrorActionPreference = 'Stop'
\$ProgressPreference  = 'SilentlyContinue'

\$imageTypes   = @(${image_types_ps1})
\$javaReleases = @(${java_releases_ps1})
\$workDir      = '${REMOTE_WORK_DIR}'
\$failed       = \$false

Set-Location \$workDir

if ('${PRUNE_DOCKER}' -eq '1') {
    Write-Host '=== Pruning Docker build cache before build ==='
    docker builder prune -a -f
    Write-Host '=== Done pruning ==='
}

foreach (\$imageType in \$imageTypes) {
    foreach (\$javaRelease in \$javaReleases) {
        Write-Host ''
        Write-Host ('=' * 60)
        Write-Host "BUILD  image_type=\$imageType  java_release=\$javaRelease"
        Write-Host ('=' * 60)

        \$env:IMAGE_TYPE            = \$imageType
        \$env:JAVA_RELEASE_OVERRIDE = \$javaRelease

        & "\$workDir\make.ps1" build
        if (\$LASTEXITCODE -ne 0) {
            Write-Host "ERROR: build failed for \$imageType jdk\$javaRelease"
            \$failed = \$true
            continue
        }

        Write-Host ''
        Write-Host ('=' * 60)
        Write-Host "TEST   image_type=\$imageType  java_release=\$javaRelease"
        Write-Host ('=' * 60)

        \$env:IMAGE_TYPE            = \$imageType
        \$env:JAVA_RELEASE_OVERRIDE = \$javaRelease

        & "\$workDir\make.ps1" test
        if (\$LASTEXITCODE -ne 0) {
            Write-Host "ERROR: tests failed for \$imageType jdk\$javaRelease"
            \$failed = \$true
        }
    }
}

if (\$failed) {
    Write-Error 'One or more build/test steps failed.'
    exit 1
}

Write-Host ''
Write-Host 'All builds and tests completed successfully.'
exit 0
PS1_EOF

scp_to "${ORCHESTRATOR_PS1}" "${SSH_USER}@${PUBLIC_IP}:C:/orchestrate.ps1"
rm -f "${ORCHESTRATOR_PS1}"

# ── Run builds and tests ──────────────────────────────────────────────────────
log "Starting build + test (IMAGE_TYPES='${IMAGE_TYPES}', JAVA_RELEASES='${JAVA_RELEASES}')..."
BUILD_EXIT=0
ssh_run "powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File C:/orchestrate.ps1" || BUILD_EXIT=$?
ssh_run "powershell -NonInteractive -NoProfile -Command \"Remove-Item -Force C:/orchestrate.ps1\"" || true

# ── Retrieve test results ─────────────────────────────────────────────────────
log "Retrieving test results..."
mkdir -p "${REPO_DIR}/target"
scp_to -r \
    "${SSH_USER}@${PUBLIC_IP}:${REMOTE_WORK_DIR}/target/." \
    "${REPO_DIR}/target/" 2>/dev/null \
    || log "WARNING: No test results to retrieve."

if [[ ${BUILD_EXIT} -ne 0 ]]; then
    log "ERROR: Build or tests failed (exit ${BUILD_EXIT}). See output above."
    _EXIT_CODE="${BUILD_EXIT}"; exit 1
fi

log "Done. Test results are in ${REPO_DIR}/target/"
