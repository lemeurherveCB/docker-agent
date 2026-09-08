---
name: reference-ec2-build
description: EC2 Windows build infrastructure for docker-agent nanoserver builds
metadata: 
  node_type: memory
  type: reference
  originSessionId: 0b5d9042-b15a-470d-a677-574996815442
  modified: 2026-09-08T20:12:55.237Z
---

# EC2 Build Infrastructure

## Instance

- **Instance ID**: `i-0689a03f3a7f4bafc`
- **Key name**: `hlemeur-test`
- **Key file**: `/tmp/hlemeur-test.pem`  (NOT in ~/.ssh — lives in /tmp)
- **AWS profile**: `cloudbees-cloud-platform-clusters`  (has ec2:DescribeInstances permission)
- **Region**: `us-east-1`
- **EIC endpoint**: `eice-0969b788085e51fc4`
- **SSH user**: `Administrator`
- Instance is stopped between runs; the build scripts start/stop it automatically.

## Build Scripts

```bash
# Full build + test (nanoserver-ltsc2025, jdk21):
SSH_KEY_PATH=/tmp/hlemeur-test.pem \
  IMAGE_TYPES="nanoserver-ltsc2025" \
  JAVA_RELEASES="21" \
  AWS_PROFILE=cloudbees-cloud-platform-clusters \
  ./build-windows-on-ec2.sh i-0689a03f3a7f4bafc

# Minimal setpd runtime test only:
SSH_KEY_PATH=/tmp/hlemeur-test.pem \
  AWS_PROFILE=cloudbees-cloud-platform-clusters \
  ./run-setpd-test-on-ec2.sh i-0689a03f3a7f4bafc
```

## PRUNE_DOCKER

Set `PRUNE_DOCKER=1` to run `docker builder prune -a -f` before the build.
Needed after failed partial builds that corrupt the windowsfilter layer cache.

## Temp file cleanup

If a previous run left `/tmp/docker-agent-*.tar.gz`, mktemp will fail.
Run `rm -f /tmp/docker-agent-*.tar.gz` before retrying.

## Wrong profile symptom

Using the default AWS profile (`infra-bedrock-claude-user`) causes:
`UnauthorizedOperation: ec2:DescribeInstances`
Always use `AWS_PROFILE=cloudbees-cloud-platform-clusters`.

[[project-nano2025-poc]]
