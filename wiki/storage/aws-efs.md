---
title: AWS EFS
tags: [efs, storage, nfs, networking, kubernetes, ecs, fargate]
related: ["[[Storage/AWS S3]]", "[[Compute/AWS EC2]]", "[[Compute/AWS ECS]]", "[[Networking/AWS VPC]]"]
created: 2026-04-28
updated: 2026-04-28
---

## Overview

Amazon Elastic File System (EFS) is a fully managed, serverless NFS file system for AWS. It scales automatically, supports concurrent access from thousands of EC2 instances, ECS tasks, EKS pods, and Lambda functions, and is the go-to choice when workloads need shared POSIX file storage across multiple compute nodes.

## Key Concepts

- **File system types:** Regional (multi-AZ replication, production default) vs One Zone (single AZ, lower cost for non-critical data). One Zone cannot auto-migrate; plan DR explicitly.
- **Performance modes:** General Purpose (low latency, default) vs Max IO (higher aggregate throughput, higher latency). Cannot downgrade from Max IO after creation.
- **Throughput modes:** Bursting (credit-based, tied to storage size), Provisioned (fixed, predictable), Elastic (auto-scales, best for unpredictable workloads).
- **Storage classes:** Standard → Infrequent Access (IA) → Archive. Lifecycle policies move files by age; files < 128 KB never leave Standard.
- **Mount targets:** One ENI per AZ; all instances in that VPC share the target. Security groups apply to mount targets, not the file system itself — NFS requires port 2049 (TCP).
- **Access points:** Enforce a POSIX user identity and a root directory path, independent of NFS permissions. Essential for container and multi-tenant workloads.

## Patterns

### Regional file system with lifecycle tiering
Deploy one mount target per AZ. Enable lifecycle management to move files to IA after 30 days (or Archive after 90+). Use Elastic throughput unless workload is steady and high-volume, in which case benchmark Provisioned.

**When to use:** Shared config, user home directories, CMS media, or any workload where multiple AZs mount the same data.
**Trade-off:** Inter-AZ mount target traffic incurs data transfer charges; co-locate compute and mount target in the same AZ where possible.

### Access points for container isolation
Create one access point per application or tenant. Set `PosixUser` and `RootDirectory` on the access point; the container never sees outside its root. Use with EFS CSI driver (EKS) or ECS volume mounts.

**When to use:** ECS/EKS/Lambda workloads with multiple tenants or services sharing one file system.
**Trade-off:** Up to 1000 access points per file system; beyond that, create a second file system.

### Cross-region replication + DataSync for DR
Enable EFS replication to create a copy in another region. Combine with DataSync to S3 for cold-storage backup. Manual cutover required — EFS replication does not update DNS automatically.

**When to use:** RPO < 15 min for shared file storage; compliance requirements for geo-redundancy.
**Trade-off:** Replication is eventually consistent; DNS/application failover logic must be built separately.

### Encryption everywhere
Enable encryption at rest (KMS, default) and in-transit (TLS via `amazon-efs-utils`). Customer-managed KMS keys require the key policy to explicitly grant EFS `kms:GenerateDataKey` and `kms:Decrypt`.

## Gotchas

- **Burst credit exhaustion:** Bursting throughput is `50 KB/s × GB stored`. New file systems start with 2.1 TB of credits — enough to mask problems early. Monitor `BurstCreditBalance` and set an alarm at ~10% remaining.
- **Throughput is per-file-system, not per-mount-target:** All clients share the same throughput budget; a single bursty job can starve all other mounts.
- **Performance mode is immutable:** Set General Purpose unless you have benchmarked evidence that Max IO is needed. You cannot switch back.
- **Files < 128 KB never tier:** Workloads with many small files won't see the cost savings expected from IA/Archive lifecycle policies.
- **Access point root directory must pre-exist:** EFS won't create the path automatically; provision it (e.g., via a one-time EC2 `mkdir + chown`) before attaching the access point.
- **Container root (UID 0) bypasses POSIX by default:** Use an access point with `PosixUser` to enforce a non-root identity; otherwise containers running as root get full file system access.
- **Security groups block silent failures:** A misconfigured security group on the mount target appears as a connection timeout, not an auth error. Verify port 2049 (TCP and UDP) is open from the compute SG.
- **TLS adds ~10-15% CPU overhead:** Acceptable for most workloads; disable only for high-throughput, non-sensitive paths where latency is critical.
- **OCSP checks can add latency:** If TLS mount latency is high, try `mount -o tls,ocsp=disable`.
- **DeleteFileSystem cascades immediately:** Deletes all mount targets with no recovery. Protect production file systems with deletion protection and IAM `Deny` on `elasticfilesystem:DeleteFileSystem`.

## Throughput Mode Decision Guide

| Workload pattern | Recommended mode |
|---|---|
| Small file system, variable load | Bursting (watch credits) |
| Consistent high throughput (> 1 GB/s) | Provisioned |
| Unpredictable spikes | Elastic |
| Steady, predictable, < burst baseline | Bursting |

## Mounting Reference

### EFS Mount Helper (recommended)
```bash
# Install
sudo yum install -y amazon-efs-utils  # Amazon Linux / RHEL
# Ubuntu: build from https://github.com/aws/efs-utils

# Mount with TLS
sudo mount -t efs -o tls fs-12345678 /mnt/efs

# Mount via access point
sudo mount -t efs -o tls,accesspoint=fsap-abc123 fs-12345678 /mnt/efs
```

### Native NFS client (no encryption in transit)
```bash
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 \
  fs-12345678.efs.us-east-1.amazonaws.com:/ /mnt/efs
```

### /etc/fstab entry
```
fs-12345678 /mnt/efs efs _netdev,tls,iam 0 0
```

## IAM and Security

EFS has two independent authorization layers — both must grant access:

1. **File system resource policy** — controls which IAM principals can call EFS API actions (mount, manage).
2. **POSIX permissions** — standard Unix file/directory permissions (owner, group, world bits).

Key IAM actions:
- `elasticfilesystem:ClientMount` — required to mount (unless anonymous access is enabled)
- `elasticfilesystem:ClientWrite` — required for write operations via IAM auth
- `elasticfilesystem:ClientRootAccess` — required to mount as UID 0

Enforce IAM auth by adding `iam` to the mount options: `mount -o tls,iam`.

## Pricing Model

| Component | Cost driver |
|---|---|
| Storage | Per GB-month per storage class (Standard > IA > Archive) |
| Provisioned throughput | Per Mbps-month above included amount |
| Elastic throughput | Per GB transferred (read + write) |
| Access points | Per access point per month |
| Replication | Data transfer + destination storage |

**Cost optimization:** Use lifecycle policies; monitor `StorageBytes` per class via CloudWatch; use One Zone for dev/test; avoid Provisioned throughput unless consistently needed.

## References

- [[Storage/AWS S3]]
- [[Compute/AWS EC2]]
- [[Compute/AWS ECS]]
