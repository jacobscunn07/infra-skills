---
name: aws-ec2
description: Use when working with Amazon EC2 - choosing instance types, purchasing options (On-Demand, Reserved, Spot, Savings Plans), configuring AMIs, EBS storage types, security groups, Auto Scaling, launch templates, instance lifecycle, Spot Fleet, Dedicated Hosts, or any EC2 architecture and troubleshooting decisions
---

# AWS EC2 Expert Skill

Comprehensive Amazon EC2 guidance covering instance types, purchasing options, storage, networking, AMIs, Auto Scaling, and production patterns. Based on the official AWS EC2 User Guide.

## When to Use This Skill

**Activate this skill when:**
- Choosing an instance type or processor family (Intel, AMD, Graviton)
- Selecting a purchasing option (On-Demand, Spot, Reserved, Savings Plans, Dedicated Hosts)
- Configuring EBS volumes (gp3, io2, st1, sc1) or instance store
- Creating or managing AMIs
- Writing launch templates or user data scripts
- Configuring security groups
- Designing or troubleshooting Auto Scaling Groups
- Working with Spot Instances or Spot Fleet
- Managing instance lifecycle (stop, start, hibernate, terminate)
- Troubleshooting connectivity, performance, or capacity issues

**Don't use this skill for:**
- ECS or EKS (container orchestration) — separate skills
- RDS (managed databases) — separate skill
- Lambda (serverless compute) — different paradigm
- General VPC/networking design — use aws-networking skill

---

## Core Concepts

EC2 provides resizable virtual compute (instances) in the cloud. Each instance is a combination of:

| Component | What You Configure |
|-----------|-------------------|
| **Instance type** | CPU, memory, network, storage |
| **AMI** | OS, pre-installed software, root volume snapshot |
| **Storage** | EBS volumes and/or instance store |
| **Networking** | VPC, subnet, security groups, Elastic IP |
| **IAM role** | Permissions for the instance to call AWS APIs |
| **User data** | Bootstrap script run on first launch |

---

## Instance Types

### Naming Convention

```
m  6  i  d  .  2xlarge
│  │  │  │      └── Size
│  │  │  └── Additional capability (d = local NVMe storage, n = network optimized, b = block storage optimized)
│  │  └── Processor (i = Intel, a = AMD, g = Graviton, no letter = varies)
│  └── Generation (higher = newer)
└── Family (m = general purpose, c = compute, r = memory, i = storage, g = GPU, p = ML training)
```

Example: `c7g.4xlarge` = Compute optimized, 7th gen, Graviton3, 4xlarge

### Instance Families

| Family | Examples | Optimized For | Choose When |
|--------|---------|---------------|-------------|
| **General Purpose** | m7i, m7g, t3 | Balanced CPU/memory | Web servers, app servers, small DBs |
| **Compute Optimized** | c7i, c7g, c6a | High CPU:memory ratio | Batch, HPC, gaming, video encoding |
| **Memory Optimized** | r7i, r7g, x2idn, u-* | High memory:CPU ratio | In-memory DBs, Redis, SAP HANA |
| **Storage Optimized** | i4i, i3en, d3 | High disk I/O | NoSQL DBs, data warehouses, Hadoop |
| **Accelerated Computing** | p5, g5, trn1, inf2 | GPU / custom silicon | ML training/inference, graphics |
| **HPC Optimized** | hpc7g, hpc6id | High-bandwidth networking | Tightly coupled HPC simulations |

### T-Series Burstable Instances

T3/T4g instances earn CPU credits when idle and spend them when busy. Good for workloads with low baseline CPU that occasionally spike (dev/test, small web servers). Use `unlimited` mode if bursting above baseline without interruption matters more than cost predictability.

### Graviton (AWS Custom ARM)

Graviton3/4 instances (`g` suffix: m7g, c7g, r7g) offer the best price-performance for most workloads — typically 20–40% better price-performance than x86 equivalents. Requires ARM-compatible software (most Linux workloads, modern runtimes compile for ARM). Not available for Windows workloads.

### Sizing Guidance

Start with sizing recommendations from **AWS Compute Optimizer** after running the workload. Don't over-provision upfront — it's easy to resize a stopped instance or change the Auto Scaling launch template.

---

## Purchasing Options

Combine options to optimize cost and availability. The typical production architecture uses all three tiers.

| Option | Discount vs On-Demand | Commitment | Interruption | Best For |
|--------|----------------------|------------|--------------|----------|
| **On-Demand** | 0% | None | Never | Dev/test, unpredictable workloads, baseline |
| **Compute Savings Plans** | Up to 66% | 1 or 3 yr | Never | Flexible steady-state compute (any family/region) |
| **EC2 Instance Savings Plans** | Up to 72% | 1 or 3 yr | Never | Steady-state, single instance family per region |
| **Reserved Instances** | Up to 72% | 1 or 3 yr | Never | Stable workloads with predictable configuration |
| **Spot Instances** | Up to 90% | None | Yes (2 min warning) | Fault-tolerant batch, stateless, flexible jobs |
| **Dedicated Hosts** | On-Demand or RI rates | Optional | Never | BYOL (license compliance), regulatory isolation |
| **Capacity Reservations** | On-Demand rates | None | Never | Guarantee capacity in a specific AZ |

### Savings Plans vs. Reserved Instances

Prefer **Compute Savings Plans** over Reserved Instances for new commitments — they apply across instance families, sizes, regions, and even Fargate/Lambda, making them easier to fully utilize.

Use **EC2 Instance Savings Plans** if you know you'll stay in one family and region — they offer slightly higher discounts.

### Spot Instance Strategy

Spot is interruptible but offers the largest discount. Design for it:

1. **Diversify** across multiple instance types and AZs — reduces correlated interruptions
2. **Use Spot Fleet or EC2 Auto Scaling with mixed policies** to manage a pool automatically
3. **Handle the 2-minute interruption notice** — listen for `EC2 Spot Instance interruption` EventBridge event or poll instance metadata (`/latest/meta-data/spot/termination-time`)
4. **Checkpoint work** frequently for batch jobs
5. **Use `capacity-optimized` allocation strategy** in Spot Fleet — picks the pool with the most available capacity, minimizing interruptions

```bash
# Check interruption notice from inside instance
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/spot/termination-time
# Returns 404 if not being interrupted; returns timestamp if interruption imminent
```

### Dedicated Hosts

Use for BYOL (bring your own license) software that is licensed per physical core or socket (Oracle, Windows Server, SQL Server). Dedicated Hosts give you visibility into physical socket and core counts. Can be reserved (On-Demand Dedicated Host pricing is expensive — almost always reserve if you need one long-term).

---

## AMIs (Amazon Machine Images)

An AMI is the blueprint for your instance: OS, pre-installed software, and the root volume snapshot.

### AMI Sources

| Source | Use When |
|--------|---------|
| **AWS Quick Start AMIs** | Default; well-maintained Amazon Linux, Ubuntu, Windows |
| **AWS Marketplace AMIs** | Pre-configured commercial software (NAT appliances, security tools) |
| **Community AMIs** | Third-party; evaluate carefully before use in production |
| **Your own custom AMI** | Standardize a golden image with your software baked in |

### Creating a Golden AMI

1. Launch a base AWS AMI
2. Install and configure software, agents, security settings
3. Run `aws ec2 create-image` to capture as AMI (instance can stay running with `--no-reboot` for EBS-backed instances, though a clean shutdown is more consistent)
4. Share the AMI ID via SSM Parameter Store so Auto Scaling Groups can reference the latest version

### AMI Regions

AMIs are region-specific. Use `aws ec2 copy-image` to replicate to other regions for multi-region deployments.

### Root Device Types

- **EBS-backed (recommended):** Root volume is an EBS snapshot. Instance can be stopped and restarted; root volume persists by default (configurable). Supports `StopInstance`.
- **Instance store-backed:** Root volume is on instance store. If the instance stops or fails, the root volume is lost. Can only terminate, not stop. Rare in modern workloads.

---

## EBS Storage

### Volume Types

| Type | Max IOPS | Max Throughput | Min Durability | Use Case |
|------|----------|----------------|---------------|----------|
| **gp3** | 16,000 (per volume) / 80,000 (multi-attach io2) | 1,000 MiB/s | 99.8%–99.9% | Default for almost everything |
| **gp2** | 16,000 | 250 MiB/s | 99.8%–99.9% | Legacy; migrate to gp3 |
| **io2 Block Express** | 256,000 | 4,000 MiB/s | 99.999% | High-performance DBs, <500μs latency |
| **io1** | 64,000 | 1,000 MiB/s | 99.8%–99.9% | I/O intensive DBs (prefer io2 for new volumes) |
| **st1** | 500 | 500 MiB/s | 99.8%–99.9% | Big data, log processing, streaming reads |
| **sc1** | 250 | 250 MiB/s | 99.8%–99.9% | Infrequently accessed cold data |

**Key rules:**
- HDD types (st1, sc1) cannot be root volumes
- gp3 is the default and right choice for most workloads — provision IOPS and throughput independently of size (unlike gp2)
- io2 Block Express requires Nitro instances; use for production databases that need consistent sub-millisecond latency
- Use **EBS-optimized instances** (default on current-gen) to ensure dedicated EBS bandwidth

### gp3 vs gp2

Always prefer gp3 for new volumes. gp3 decouples IOPS and throughput from volume size:

| | gp2 | gp3 |
|--|-----|-----|
| **Baseline IOPS** | 3 IOPS/GiB (min 100, max 16,000) | 3,000 (flat baseline) |
| **Throughput** | Up to 250 MiB/s | Up to 1,000 MiB/s |
| **IOPS provisioning** | Tied to size | Independent (up to 16,000) |
| **Cost** | Higher | ~20% cheaper |

### Instance Store

Physically attached NVMe SSDs. Highest possible I/O performance and lowest latency — but ephemeral. Data is lost when the instance stops, terminates, or fails hardware.

Use instance store for: temporary scratch space, caches, buffers, replicated data stores (Kafka, Cassandra, Redis replicas) where data loss on a single node is acceptable.

Instance types with local NVMe storage have a `d` in the name (e.g., `m6id`, `i4i`). The `i` family is optimized for local NVMe with huge capacities.

---

## Security Groups

Security groups are stateful virtual firewalls applied at the instance (ENI) level.

### Key Behaviors

- **Stateful:** Return traffic for allowed connections is automatically permitted — no need to add an inbound rule for responses to your outbound requests
- **Allow-only:** You can only add Allow rules; there is no explicit Deny in security groups. Use NACLs (stateless, at subnet level) for deny rules
- **Evaluated as union:** If multiple security groups are attached, AWS allows traffic if any one of them permits it
- **Changes are immediate:** Rules apply to all associated instances instantly

### Rule Structure

```
Type       Protocol   Port Range   Source/Destination
SSH        TCP        22           10.0.0.0/8
HTTPS      TCP        443          0.0.0.0/0
Custom TCP TCP        8080         sg-0abc123 (another SG ID)
```

Using a security group ID as source/destination (instead of CIDR) is preferred for internal traffic — it automatically tracks instances as they scale, no IP management needed.

### Common Security Group Patterns

```
Internet → ALB SG (allow 80, 443 from 0.0.0.0/0)
ALB SG   → App SG (allow 8080 from ALB SG ID)
App SG   → DB SG  (allow 5432 from App SG ID)
App SG   → 0.0.0.0/0 (allow 443 outbound for AWS API calls)
```

---

## Instance Lifecycle

```
pending → running → stopping → stopped → pending (restart)
                 ↘              ↓
                  shutting-down → terminated
```

| State | Billing | EBS Root Volume | Instance Store |
|-------|---------|-----------------|----------------|
| **pending** | Charged | Attached | Attached |
| **running** | Charged | Attached | Data persists |
| **stopping** | Not charged | Retained | Data preserved until stopped |
| **stopped** | EBS storage only | Retained | **Data lost** |
| **shutting-down** | Not charged | Being deleted (default) | Data lost |
| **terminated** | Not charged | Deleted (default) | Data lost |

**Hibernate:** A fourth option between stop and terminate — saves RAM contents to EBS root volume, then shuts down. On restart, RAM is restored and processes resume. Requires an encrypted root EBS volume with enough space for the RAM snapshot. Useful for long-running stateful processes.

**Reboot vs. stop+start:** Reboot keeps the instance on the same physical host; stop+start may move it to a different host (which can resolve hardware issues and will assign a new public IP if you're not using an Elastic IP).

---

## Launch Templates

Launch templates are the modern, versioned replacement for launch configurations. Always use launch templates — they support more features and are required for mixed instance types in Auto Scaling.

### Minimal Launch Template

```json
{
  "LaunchTemplateName": "my-app-lt",
  "LaunchTemplateData": {
    "ImageId": "ami-0abcdef1234567890",
    "InstanceType": "m7g.large",
    "IamInstanceProfile": { "Name": "my-app-instance-profile" },
    "SecurityGroupIds": ["sg-0abc123"],
    "UserData": "IyEvYmluL2Jhc2g...",
    "MetadataOptions": {
      "HttpTokens": "required",
      "HttpPutResponseHopLimit": 1
    },
    "BlockDeviceMappings": [{
      "DeviceName": "/dev/xvda",
      "Ebs": {
        "VolumeSize": 30,
        "VolumeType": "gp3",
        "Encrypted": true,
        "DeleteOnTermination": true
      }
    }]
  }
}
```

**Always set `HttpTokens: required`** — this enforces IMDSv2 (token-based metadata service), which prevents SSRF attacks from reaching the instance metadata endpoint.

### User Data

Runs as root on first boot. Use for bootstrapping:

```bash
#!/bin/bash
yum update -y
yum install -y amazon-cloudwatch-agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c ssm:/my-app/cloudwatch-config
```

For complex bootstrapping, prefer AWS Systems Manager State Manager or pulling a config script from S3 rather than embedding everything in user data.

---

## Auto Scaling

EC2 Auto Scaling maintains a desired number of instances and replaces unhealthy ones automatically.

### Key Components

| Component | Purpose |
|-----------|---------|
| **Auto Scaling Group (ASG)** | Defines min/desired/max capacity and where to run |
| **Launch Template** | Defines what to run (AMI, instance type, etc.) |
| **Scaling Policy** | Rules for when to add or remove capacity |
| **Health Checks** | Determines when an instance is unhealthy and must be replaced |

### Scaling Policy Types

| Type | How It Works | Best For |
|------|-------------|----------|
| **Target Tracking** | Maintain a CloudWatch metric at a target value | Default choice — simplest to configure |
| **Step Scaling** | Add/remove N instances at defined alarm thresholds | Faster reaction to burst traffic |
| **Scheduled** | Scale at specific times | Predictable traffic patterns (business hours, batch windows) |
| **Predictive** | ML forecast of future load | Daily/weekly cycles |

**Target Tracking example (recommended):**
```json
{
  "TargetValue": 70.0,
  "PredefinedMetricSpecification": {
    "PredefinedMetricType": "ASGAverageCPUUtilization"
  },
  "ScaleOutCooldown": 60,
  "ScaleInCooldown": 300
}
```

Keep scale-in cooldown longer (300s) than scale-out (60s) to avoid thrashing.

### Mixed Instance Types (Spot + On-Demand)

```json
"MixedInstancesPolicy": {
  "InstancesDistribution": {
    "OnDemandBaseCapacity": 2,
    "OnDemandPercentageAboveBaseCapacity": 20,
    "SpotAllocationStrategy": "capacity-optimized"
  },
  "LaunchTemplate": {
    "LaunchTemplateSpecification": { "LaunchTemplateName": "my-app-lt" },
    "Overrides": [
      { "InstanceType": "m7g.large" },
      { "InstanceType": "m6g.large" },
      { "InstanceType": "m7i.large" },
      { "InstanceType": "m6i.large" }
    ]
  }
}
```

This keeps 2 On-Demand instances as a baseline, puts 20% of additional capacity on On-Demand, and fills the rest with Spot using `capacity-optimized` to minimize interruptions.

### Health Checks

- **EC2 health checks** (default): Replace instances that fail EC2 status checks (hardware/hypervisor issues)
- **ELB health checks**: Replace instances that fail the load balancer's health check (app-level issues) — enable this for any ASG fronted by a load balancer
- **Custom health checks**: Your code marks an instance unhealthy via the `set-instance-health` API

### Lifecycle Hooks

Pause an instance during launch or termination to run custom logic (drain connections, download config, send a notification):

```
Launch: pending:wait → (your hook runs) → pending:proceed → running
Terminate: terminating:wait → (your hook runs) → terminating:proceed → terminated
```

Default timeout is 1 hour. Your code must call `complete-lifecycle-action` with `CONTINUE` or `ABANDON`, or the hook times out and proceeds.

---

## Architecture Patterns

### Standard Auto-Scaled Web Tier

```
Internet
    │
    ALB (public subnets, multi-AZ)
    │   Listener: 443 → target group
    │
ASG (private subnets, min=2, desired=4, max=20)
    Instance type: m7g.large
    Scaling: Target tracking on ALBRequestCountPerTarget
    Health check: ELB
    Mixed policy: 2 On-Demand base + rest Spot (capacity-optimized)
```

### Spot Batch Processing

```
S3 event → SQS queue → ASG (Spot only)
    Min=0, Max=100
    Scaling: Target tracking on SQS ApproximateNumberOfMessagesVisible
    Mixed: c7g.xlarge, c6g.xlarge, c7i.xlarge (diversified)
    User data: Poll SQS, process, delete message, drain on SIGTERM
```

Scale to zero between jobs; Spot gives ~70% cost reduction.

### Golden AMI Pipeline

```
EC2 Image Builder pipeline (weekly)
    Base: Amazon Linux 2023
    Components: CloudWatch agent, SSM agent, security hardening
    Test: Launch instance, run integration tests
    Output: New AMI version → SSM Parameter /my-org/golden-ami/latest

ASG launch templates reference SSM parameter (not hardcoded AMI ID)
Instance refresh on new parameter value → rolling replacement
```

---

## Security Best Practices

1. **Enforce IMDSv2** — set `HttpTokens: required` in all launch templates; prevents SSRF attacks from reading credentials via the metadata service
2. **Use IAM instance profiles, not access keys** — SDK credential chain picks up instance profile automatically; never put access keys on an instance
3. **Private subnets for app/DB tiers** — only load balancers and bastion/SSM endpoints in public subnets
4. **No SSH from the internet** — use AWS Systems Manager Session Manager instead of SSH (no key management, full audit log in CloudTrail)
5. **Encrypt EBS volumes** — enable account-level EBS encryption by default (`aws ec2 enable-ebs-encryption-by-default`)
6. **Least-privilege security groups** — reference security group IDs rather than CIDRs for internal traffic; never use `0.0.0.0/0` for inbound except on public-facing load balancers
7. **Keep AMIs patched** — use EC2 Image Builder to rebuild golden AMIs regularly; use instance refresh to roll out updated AMIs to ASGs
8. **Enable detailed monitoring** — 1-minute CloudWatch metrics for ASG and instances (`--monitoring Enabled=true`)
9. **Tag everything** — `Name`, `Env`, `Team`, `CostCenter` on instances, volumes, and AMIs for cost allocation and automation
10. **Use Nitro-based instances** — current generation; stronger isolation, better performance, required for some features (io2 Block Express, ENA Express, NitroTPM)

---

## Common Troubleshooting

### Instance Won't Launch

| Symptom | Likely Cause |
|---------|-------------|
| `InsufficientInstanceCapacity` | No On-Demand capacity in the AZ — try a different AZ or instance type |
| `InstanceLimitExceeded` | Reached vCPU quota — request a limit increase via Service Quotas |
| Instance stuck in `pending` | Check system log (`get-console-output`) for OS boot errors |
| `InvalidAMIID.NotFound` | AMI doesn't exist in this region — copy the AMI first |
| Instance launched but unreachable | Check security group inbound rules, subnet route table, NACL |

### Can't Connect to Instance

| Symptom | Likely Cause |
|---------|-------------|
| SSH timeout | Security group doesn't allow port 22 from your IP; or instance in private subnet with no bastion/VPN |
| `Permission denied (publickey)` | Wrong key pair or wrong user (`ec2-user` for Amazon Linux, `ubuntu` for Ubuntu) |
| `Host key verification failed` | Instance replaced but known_hosts has old key — remove old entry |
| No response via SSM Session Manager | SSM agent not running; instance IAM role missing `AmazonSSMManagedInstanceCore` policy; or no SSM endpoint/NAT |

### Auto Scaling Issues

| Symptom | Likely Cause |
|---------|-------------|
| ASG not scaling out | Scaling policy cooldown active; or instance launch failing and causing `Failed` activity |
| Instances launched but immediately terminated | ELB health check failing — check app health endpoint, security group allows health check port from ALB |
| Desired count keeps oscillating | Scale-in cooldown too short; or CloudWatch metric is noisy — add a buffer to the target value |
| Instance refresh stuck | Minimum healthy percentage too high to replace all instances — reduce or wait |

### EBS Performance Issues

| Symptom | Likely Cause |
|---------|-------------|
| High disk latency on gp2 | Volume out of burst credits — migrate to gp3 with explicit IOPS provisioned |
| IOPS lower than provisioned on io2 | Instance not EBS-optimized, or not on Nitro hypervisor |
| Throughput bottleneck | Per-instance EBS bandwidth limit reached — check `EBSBytesPerSecond` CloudWatch metric |
| `No space left on device` | Volume full — expand EBS volume online (`modify-volume`) then extend filesystem |
