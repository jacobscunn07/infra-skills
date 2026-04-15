---
name: aws-efs
description: Use when working with Amazon EFS - choosing between Regional and One Zone file systems, performance modes, throughput modes (Elastic/Provisioned/Bursting), storage tiers and lifecycle policies, mounting on EC2/ECS/EKS/Lambda, access points, IAM and POSIX permissions, security groups, replication, backups, or any EFS architecture and troubleshooting decisions
---

# AWS EFS Expert Skill

Comprehensive Amazon EFS guidance covering file system types, performance, storage tiers, mounting, access control, and production patterns. Based on the official AWS EFS User Guide.

## When to Use This Skill

**Activate this skill when:**
- Choosing between EFS and EBS or S3 for a storage use case
- Deciding between Regional vs One Zone file systems
- Selecting and tuning throughput mode (Elastic, Provisioned, Bursting)
- Configuring storage tiers and lifecycle policies (Standard, IA, Archive)
- Mounting EFS on EC2, ECS, EKS, or Lambda
- Setting up access points for multi-tenant or per-application isolation
- Configuring IAM policies and POSIX permissions
- Setting up cross-region replication or AWS Backup
- Troubleshooting mount failures, performance issues, or access denied errors

**Don't use this skill for:**
- EBS (block storage attached to a single instance)
- S3 (object storage, not POSIX-compatible)
- FSx for Windows (EFS does not support Windows)
- FSx for Lustre (HPC/ML high-performance parallel filesystem)

---

## When to Use EFS vs EBS vs S3

| Scenario | Storage Choice |
|----------|---------------|
| Shared filesystem accessed by multiple EC2/containers simultaneously | **EFS** |
| Single EC2 instance needs high-IOPS block storage | **EBS** |
| Object storage, static assets, data lake | **S3** |
| Container workloads needing persistent shared storage | **EFS** |
| Lambda needing persistent filesystem access | **EFS** |
| Database storage (RDS, self-managed) | **EBS** |
| Home directories, CMS, web serving | **EFS** |

EFS key constraint: **Linux only** — Windows EC2 instances cannot mount EFS.

---

## File System Types

### Regional (Recommended)

- Data is stored across **multiple Availability Zones**, with 6 copies across 3 AZs
- Survives full AZ outage with no data loss
- Create one **mount target per AZ** — each gets a static IP and DNS name
- All instances in an AZ share the same mount target
- Higher cost than One Zone, but the correct default for production

### One Zone

- Data stored within a **single Availability Zone**
- ~47% cheaper than Regional
- Only one mount target — cross-AZ access incurs EC2 data transfer charges
- Data is lost if the AZ is destroyed
- Use for: dev/test, reproducible data (build caches, scratch space), cost-sensitive non-critical workloads

---

## Performance Modes

### General Purpose (Always Use This)

- Default and recommended for all file systems
- Lowest per-operation latency (~1 ms reads, ~2.7 ms writes)
- Mandatory for One Zone file systems
- Supports all throughput modes

### Max I/O (Avoid)

- Previous generation — AWS explicitly recommends against it
- Higher per-operation latency than General Purpose
- Not supported for One Zone or Elastic throughput
- Only reason to consider: highly parallelized HPC workloads where aggregate throughput matters more than latency. Even then, prefer General Purpose + Elastic first.

---

## Throughput Modes

### Elastic (Default — Use This for Most Workloads)

Automatically scales throughput up and down with your workload. No burst credits, no manual provisioning.

| | Regional | One Zone |
|---|---|---|
| Max read throughput | 20–60 GiBps | 3 GiBps |
| Max write throughput | 1–5 GiBps | 1 GiBps |
| Max read IOPS | 900K–2.5M | 35,000 |
| Max write IOPS | 500K | 7,000 |
| Per-client throughput | 1,500 MiBps* | 500 MiBps |

*Requires `amazon-efs-utils` v2.0+ or `aws-efs-csi-driver`

**Choose Elastic when:** workload is unpredictable, spiky, or you want zero capacity management.

### Provisioned Throughput

Specify a fixed throughput level independent of file system size.

- Consistent, predictable throughput regardless of workload
- Billed for provisioned throughput above the baseline earned by storage size
- **24-hour cooldown:** after switching to Provisioned or changing the provisioned amount, you cannot switch back to Elastic/Bursting or decrease the amount for 24 hours

**Choose Provisioned when:** workload has steady, high throughput needs where average-to-peak ratio is ≥ 5% of the time, and the cost is lower than Elastic at that sustained level.

### Bursting Throughput

Throughput scales with storage size using a credit model.

- **Baseline:** 50 KiBps per GiB of stored data
- **Burst rate:** up to 100 MiBps per TiB (when credits available)
- Credits accumulate during inactivity, deplete during burst

| Storage Size | Burst Throughput | Baseline | Time at Full Burst |
|---|---|---|---|
| 100 GiB | 100 MiBps write | 5 MiBps | 72 min/day |
| 1 TiB | 100 MiBps write | 50 MiBps | 12 hrs/day |
| 10 TiB | 1 GiBps write | 500 MiBps | 12 hrs/day |

**Choose Bursting when:** workload is bursty AND you have large amounts of stored data (high baseline throughput), making Bursting cost-effective.

**Warning sign:** if `BurstCreditBalance` CloudWatch metric is consistently depleting, switch to Elastic or Provisioned.

### Throughput Mode Decision

```
Default → Elastic
  Only reconsider if:
    - Sustained constant throughput > Elastic cost → try Provisioned
    - Large file system (multi-TiB) with bursty, predictable workload → Bursting
```

---

## Storage Tiers & Lifecycle Management

EFS has three storage tiers. Lifecycle policies apply to the **entire file system** and automatically move files based on last-access time.

| Tier | Latency | Use Case | Cost |
|------|---------|----------|------|
| **Standard** | ~1 ms read / ~2.7 ms write | Frequently accessed, active files | Highest |
| **Infrequent Access (IA)** | Tens of milliseconds | Accessed a few times per quarter | ~92% less than Standard |
| **Archive** | Tens of milliseconds | Accessed a few times per year | Lowest |

### Lifecycle Transition Policies

Three policies configure how files move between tiers:

**Transition into IA:** after N days without access in Standard (default: 30 days)

**Transition into Archive:** after N days without access (default: 90 days)

**Transition back to Standard:** `None` (default) or `On first access`
- Set to `On first access` for performance-sensitive workloads that occasionally need archived files at full speed
- Leave as `None` when you want cost savings to persist between infrequent accesses

### Lifecycle Behavior Details

- **Metadata** (filenames, directory structure, permissions) always stays in Standard — no latency impact
- **Write operations** to IA/Archive files are written to Standard first, then eligible for re-transition after 24 hours
- **Directory listing (`ls`)** does not count as file access — won't trigger transition back
- Policies apply to the whole filesystem; you cannot set per-directory lifecycle rules
- Millions of small files take longer to transition than fewer large files of the same total size

### Recommended Lifecycle Configuration (Production Default)

```
Transition to IA:      30 days
Transition to Archive: 180 days
Transition to Standard: On first access
```

---

## Mount Targets

Each mount target provides an NFSv4 endpoint (IP address + DNS name) within a VPC subnet.

- One mount target per AZ per file system
- If multiple subnets exist in an AZ, pick one — all instances in that AZ use the same mount target
- Uses **port 2049** (NFS) — security group on the mount target must allow inbound TCP 2049 from your compute SG

```
VPC
├── AZ us-east-1a
│   ├── Mount Target (IP: 10.0.1.x) ← fs-abc123.efs.us-east-1.amazonaws.com resolves here
│   └── EC2 / ECS Tasks
├── AZ us-east-1b
│   ├── Mount Target (IP: 10.0.2.x)
│   └── EC2 / ECS Tasks
└── AZ us-east-1c
    ├── Mount Target (IP: 10.0.3.x)
    └── EC2 / ECS Tasks
```

**Always access EFS from the mount target in the same AZ** — cross-AZ access works but incurs data transfer charges and adds latency.

---

## Mounting EFS

### Prerequisites

Install `amazon-efs-utils` on the instance:
```bash
# Amazon Linux 2 / Amazon Linux 2023
sudo yum install -y amazon-efs-utils

# Ubuntu
sudo apt-get install -y amazon-efs-utils
```

### Mount Commands (EFS Mount Helper)

Basic mount (no encryption in transit):
```bash
sudo mount -t efs fs-abc123:/ /mnt/efs
```

With TLS encryption in transit (recommended):
```bash
sudo mount -t efs -o tls fs-abc123:/ /mnt/efs
```

With IAM authorization + TLS:
```bash
sudo mount -t efs -o tls,iam fs-abc123:/ /mnt/efs
```

With a specific access point:
```bash
sudo mount -t efs -o tls,iam,accesspoint=fsap-0123456789abcdef0 fs-abc123:/ /mnt/efs
```

### Persistent Mount via /etc/fstab

```
fs-abc123:/ /mnt/efs efs defaults,tls,iam,_netdev 0 0
```

`_netdev` prevents the instance from hanging at boot if the network isn't ready.

### Recommended Mount Options

| Option | Purpose |
|--------|---------|
| `tls` | Encrypts data in transit using TLS |
| `iam` | Uses IAM identity for authorization |
| `noresvport` | Allows reconnection on new TCP port after network disruption (improves resiliency) |
| `_netdev` | Marks as network device; delays mount until network available |
| `accesspoint=fsap-xxx` | Mounts through a specific access point |

### Mounting in ECS (Fargate / EC2)

In task definition:
```json
"volumes": [
  {
    "name": "efs-vol",
    "efsVolumeConfiguration": {
      "fileSystemId": "fs-abc123",
      "rootDirectory": "/",
      "transitEncryption": "ENABLED",
      "authorizationConfig": {
        "accessPointId": "fsap-0123456789abcdef0",
        "iam": "ENABLED"
      }
    }
  }
],
"mountPoints": [
  {
    "sourceVolume": "efs-vol",
    "containerPath": "/mnt/efs",
    "readOnly": false
  }
]
```

### Mounting in EKS (via EFS CSI Driver)

Install the EFS CSI driver, then create a `StorageClass` and `PersistentVolumeClaim`:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap   # creates a per-PVC access point automatically
  fileSystemId: fs-abc123
  directoryPerms: "700"
```

### Mounting in Lambda

Lambda can mount EFS via an access point. Configure in the Lambda function:
- VPC: must be same VPC as the EFS mount targets
- Access point ARN: required
- Local mount path: e.g., `/mnt/efs`

Lambda functions share the filesystem across concurrent invocations — useful for shared state, model weights, or caches.

---

## Access Control

EFS uses two independent layers of access control that both must allow access.

### Layer 1: Network (Security Groups)

Mount target security group must allow **inbound TCP port 2049** from the compute security group:

```
ECS Task SG / EC2 SG → EFS Mount Target SG: TCP 2049 inbound
```

### Layer 2: IAM (File System Policy)

An EFS file system policy is a resource-based IAM policy controlling NFS client access. Key preconfigured options:

```json
{
  "Statement": [
    {
      "Effect": "Deny",
      "Principal": { "AWS": "*" },
      "Action": "*",
      "Condition": {
        "Bool": { "aws:SecureTransport": "false" }
      }
    }
  ]
}
```
This denies all unencrypted (non-TLS) mounts — recommended for production.

Common IAM EFS actions:
- `elasticfilesystem:ClientMount` — allows mounting (read-only)
- `elasticfilesystem:ClientWrite` — allows write operations
- `elasticfilesystem:ClientRootAccess` — allows root (UID 0) access

### Layer 3: POSIX Permissions

Once mounted, standard Linux file permissions apply (user/group/other, chmod, chown). EFS enforces POSIX semantics including file locking.

### Access Points

Access points are application-specific entry points into an EFS file system that enforce:

1. **POSIX identity** — override the UID/GID of all requests made through the access point, regardless of what the NFS client sends
2. **Root directory** — clients see only a subdirectory of the full filesystem, not the root

**Why access points matter:**
- Multi-tenant isolation: give each application or team its own access point rooted to `/app-name/`, preventing cross-application access
- Serverless/container workloads: Lambda and Fargate may run as root — access points enforce a non-root POSIX identity
- EKS dynamic provisioning: EFS CSI driver creates one access point per PVC automatically

```bash
# Example: create an access point rooted at /app1 with POSIX UID/GID 1000
aws efs create-access-point \
  --file-system-id fs-abc123 \
  --posix-user "Uid=1000,Gid=1000" \
  --root-directory "Path=/app1,CreationInfo={OwnerUid=1000,OwnerGid=1000,Permissions=750}"
```

---

## Encryption

### Encryption at Rest

- Must be enabled at file system creation — cannot be added after
- Uses AWS KMS (AES-256)
- Encrypts all data and metadata
- To enable on an existing unencrypted filesystem: create a new encrypted filesystem, then copy data using AWS DataSync

### Encryption in Transit

- Enabled at mount time using the `tls` mount option
- Handled by the EFS mount helper via a TLS tunnel
- Enforce it for all clients via file system policy (`aws:SecureTransport: false` deny)

---

## Replication

EFS replication asynchronously copies data to a destination file system in another region.

- **RPO: ~15 minutes** for most file systems (higher if >100M files or >100 GB files with frequent changes)
- Destination is read-only while replication is active
- Monitor with `TimeSinceLastSync` CloudWatch metric
- Cross-account replication requires a custom IAM role (service-linked role not permitted)
- Failover: delete the replication configuration, which makes the destination writable
- Failback: reverse the replication — triggers a full initial sync

**Use cases:** disaster recovery, compliance (geographically separated copy), data migration.

---

## Backups

EFS integrates natively with AWS Backup.

- **Incremental:** first backup is a full copy; subsequent backups only copy changed/added/removed files
- **Default plan** (when enabled via console): daily backup, 35-day retention
- **Performance:** backups run at up to 2,000 files/second or 400 MBps — does not consume burst credits
- **Consistency:** if files are written during backup, the backup may be inconsistent — pause writes or schedule backups during low-activity windows
- All restored files return to **Standard storage class** regardless of the source tier

Enable automatic backups at creation time or via AWS Backup console. For One Zone file systems, automatic backups are enabled by default when using CLI/API.

---

## Architecture Patterns

### Shared Content for Web Fleet

```
ALB
 ├── EC2 (AZ-1) → mounts EFS via AZ-1 mount target
 ├── EC2 (AZ-2) → mounts EFS via AZ-2 mount target
 └── EC2 (AZ-3) → mounts EFS via AZ-3 mount target
          │
     EFS Regional filesystem
       - Throughput: Elastic
       - Storage: Standard + IA lifecycle (30d)
       - Encryption: at-rest + in-transit
```

### Multi-Tenant ECS with Access Points

```
ECS Service A (Fargate) → Access Point /tenant-a (UID 1001, GID 1001)
ECS Service B (Fargate) → Access Point /tenant-b (UID 1002, GID 1002)
ECS Service C (Fargate) → Access Point /tenant-c (UID 1003, GID 1003)
          │
     EFS Regional filesystem (single shared FS, isolated per access point)
```

### Lambda Shared Cache / Model Weights

```
Lambda function (VPC-attached)
  → Access point /models (read-only for Lambda)
  → EFS: pre-loaded ML model weights or shared cache

Loader function (write access point)
  → Refreshes content in /models periodically
```

### EKS Dynamic PVC Provisioning

```
EFS CSI Driver (DaemonSet)
  → Creates one EFS access point per PVC automatically
  → Each pod gets isolated directory in the same EFS filesystem
  → No manual access point management
```

---

## Security Best Practices

1. **Always use private subnets for mount targets** — EFS should never be internet-accessible
2. **SG-to-SG rules on port 2049** — never open NFS to 0.0.0.0/0
3. **Enable encryption at rest at creation** — cannot add later
4. **Enforce TLS via file system policy** — deny `aws:SecureTransport: false`
5. **Use access points for all containerized/serverless workloads** — prevents UID 0 escalation from Lambda or Fargate
6. **Enable AWS Backup** — EFS has no built-in snapshotting; Backup is the only managed recovery option
7. **One access point per application** — prevents cross-application filesystem access even on shared EFS
8. **Monitor `BurstCreditBalance`** — set CloudWatch alarm; if balance reaches zero on Bursting mode, throughput collapses to baseline
9. **Monitor `TimeSinceLastSync` for replication** — alert if lag exceeds your RPO tolerance
10. **Access same-AZ mount target** — routing through another AZ's mount target adds latency and data transfer costs

---

## Common Troubleshooting

| Symptom | Likely Cause |
|---------|-------------|
| `Connection refused` / mount hangs | Security group on mount target not allowing TCP 2049 from instance SG |
| `Permission denied` at mount | IAM policy missing `elasticfilesystem:ClientMount`; or file system policy denying the IAM principal |
| `Permission denied` after mount | POSIX permissions on the directory (check UID/GID); access point POSIX enforcement overriding client identity |
| Mount works but writes fail | IAM policy missing `elasticfilesystem:ClientWrite`; or read-only mount option; or access point has write-restricted policy |
| High latency on file reads | Files transitioned to IA/Archive storage class — first access takes tens of ms; set "Transition to Standard: On first access" if latency matters |
| Throughput collapses periodically | `BurstCreditBalance` exhausted on Bursting mode — switch to Elastic throughput |
| `nfs: server not responding` after network event | Add `noresvport` mount option — allows NFS client to reconnect on a new TCP port |
| Lambda cannot reach EFS | Lambda not in the same VPC as mount targets; or Lambda SG not whitelisted on mount target SG |
| ECS task fails to start with EFS volume | Task execution role missing `elasticfilesystem:ClientMount`; access point ARN incorrect; EFS in different VPC |
| Cross-AZ data transfer charges appearing | Instances or tasks accessing mount target in a different AZ — ensure each AZ has its own mount target and instances use the local one |
