---
title: AWS EC2
tags: [ec2, compute, instances, ami, spot, reserved, purchasing]
related: ["[[Storage/AWS S3]]", "[[Compute/AWS ECS]]", "[[Compute/AWS EC2 Auto Scaling]]", "[[IAM/AWS IAM]]", "[[Observability/AWS CloudWatch]]", "[[Networking/AWS VPC]]"]
created: 2026-04-27
updated: 2026-04-29
---

## Overview

Amazon EC2 provides virtual servers (instances) in the AWS cloud. You have full lifecycle control — launch, stop, start, hibernate, reboot, and terminate. You choose from a wide range of instance types grouped by family, select an AMI as the boot image, and pay by the second. EC2 is the foundational compute layer for most AWS workloads and integrates tightly with Auto Scaling, ELB, EBS, IAM, VPC, and CloudWatch.

## Key Concepts

- **Instance**: A virtual server; billing starts when it enters `running` and stops when it enters `shutting-down` (terminate) or `stopped` (stop).
- **AMI (Amazon Machine Image)**: The image used to boot an instance — specifies OS, root volume, and block device mapping. AMIs are region-specific.
- **Instance type**: Determines CPU, memory, network, and storage capacity. Named as `<family><generation>[processor][capabilities].<size>` (e.g., `m7i.xlarge`).
- **EBS volume**: Persistent block storage attached to an instance. Root volumes default to `DeleteOnTermination=true`.
- **Instance store**: Ephemeral local NVMe storage. Data is lost on stop, hibernate, or terminate. Never rely on it for durable data.
- **Security group**: Stateful virtual firewall. Controls inbound and outbound traffic by protocol, port, and CIDR/SG source.
- **Key pair**: SSH access credential. AWS stores the public key; you store the private key.
- **Nitro hypervisor**: AWS-built KVM-based hypervisor used by all modern instance families. Provides near bare-metal performance and supports enhanced networking.

## Instance Type Families

| Family | Purpose | Current generations |
|--------|---------|---------------------|
| M (General purpose) | Balanced CPU/memory for most workloads | M7i, M7g, M8g, M8i |
| T (Burstable) | Low baseline CPU with burst credits; cost-efficient for variable workloads | T3, T3a, T4g |
| C (Compute optimized) | High CPU-to-memory ratio; batch, HPC, gaming | C7i, C7g, C8i, C8g |
| R (Memory optimized) | High memory for in-memory DBs, analytics | R7i, R7g, R8i, R8g |
| X (Memory optimized, large) | Very large memory (up to TBs); SAP HANA | X2idn, X8i |
| I (Storage optimized) | High-throughput NVMe instance store; OLTP, NoSQL | I7i, I8g |
| D (Storage optimized, dense) | Very large HDD instance store; MapReduce, HDFS | D3, D3en |
| G (GPU, graphics) | ML inference, video encoding | G5, G6, G7e |
| P (GPU, HPC) | ML training, deep learning | P4d, P5, P6 |
| Inf/Trn (AI accelerators) | Inferentia/Trainium for ML at low cost | Inf2, Trn1, Trn2 |
| Hpc (High-performance computing) | Tightly coupled MPI workloads | Hpc7g, Hpc8a |

**Graviton (Arm)** instances have a `g` suffix (e.g., `m7g`, `c8g`). They deliver up to 40% better price-performance than x86 for most workloads and run on AWS-designed Graviton processors.

## AMI Characteristics

Every AMI is specific to: region, OS, processor architecture, root volume type, and virtualization type.

**Root volume types:**
- **EBS-backed** (recommended): Root volume is an EBS snapshot. Instance can be stopped and restarted; root volume persists unless `DeleteOnTermination=true`. Boot time typically < 1 minute.
- **Instance store-backed** (legacy, EOL): Root volume is in S3. Instance cannot be stopped — only running or terminated. Data is lost on termination. Only supported on older instance families (C1, M1, M2, M3, etc.).

**Launch permissions:** `public` (all accounts), `explicit` (specific accounts/orgs/OUs), or `implicit` (owner only).

**Boot modes:** UEFI preferred for modern instances. BIOS is legacy. Set `boot_mode` on the AMI to enforce it.

## Purchasing Options

| Option | Commitment | Savings vs On-Demand | Best for |
|--------|-----------|---------------------|----------|
| On-Demand | None (60-second minimum) | Baseline | Unpredictable or short-lived workloads |
| Savings Plans | 1 or 3 yr, $/hr commitment | Up to ~66% | Flexible commitment across families/regions |
| Reserved Instances | 1 or 3 yr, specific instance config | Up to ~72% | Steady-state workloads with known instance type |
| Spot Instances | None | Up to ~90% | Fault-tolerant, interruptible workloads |
| Dedicated Hosts | Per-host billing | BYOL savings | Software licensing (per-socket/per-core) |
| Dedicated Instances | Per-instance, single-tenant | Compliance | Tenancy isolation without BYOL |
| Capacity Reservations | None (pay On-Demand rate) | None | Guaranteed capacity in a specific AZ |

**Savings Plans vs Reserved Instances:** Savings Plans commit to a $/hr spend (flexible across families and regions); RIs commit to a specific instance type in a specific region. Savings Plans are simpler to manage for most workloads.

**Reserved Instance types:**
- **Standard RIs**: Fixed instance family/size/region; highest discount.
- **Convertible RIs**: Can exchange for different instance type/family; ~45% discount.
- **Regional vs Zonal**: Regional RIs apply discount across all AZs in a region but don't reserve capacity. Zonal RIs reserve capacity in a specific AZ.
- RI discounts are shared across all accounts in a consolidated billing payer.

## Spot Instances

Spot uses spare EC2 capacity at up to 90% discount. Key properties:

- **Spot price**: Set by Amazon EC2, adjusts gradually based on long-term supply/demand.
- **Spot capacity pool**: Unused capacity of the same instance type + AZ.
- **Interruption notice**: 2-minute warning before Amazon EC2 reclaims the instance (terminates, stops, or hibernates depending on configuration).
- **Rebalance recommendation**: Signal emitted when interruption risk is elevated — earlier than the 2-minute notice. Use EC2 Auto Scaling or Spot Fleet with rebalance to respond proactively.
- **Interruption behavior**: Configure as terminate (default), stop (EBS-backed only), or hibernate.
- **Spot Instances are NOT covered by Savings Plans.** Spend on Spot does not count toward Compute Savings Plan commitments.

Best for: batch processing, data analytics, background jobs, CI build workers, ML training (with checkpointing), and stateless web tier overflow.

## Patterns

**Graviton first**: Default to Graviton (`g`-suffix) instance types. Better price-performance for most workloads; requires arm64-compatible AMIs and container images.

**Multi-AZ placement**: Always spread instances across at least 2 AZs. Use Auto Scaling group with `AvailabilityZones` or placement group (spread type) for HA.

**Spot + On-Demand mix**: Use a Spot Fleet or Auto Scaling group with mixed instance policies — baseline capacity on On-Demand, scale-out on Spot. Configure multiple Spot pools (different families/sizes) to increase availability.

**EBS-only root, instance store for scratch**: Use EBS for root and persistent data. Use instance store (NVMe, `d`/`i` families) only for temp scratch/cache where data loss is acceptable.

**Launch templates over launch configurations**: Launch templates are versioned, support Spot and mixed instances, and are required for many newer features. Launch configurations are legacy and should not be used for new work.

**Savings Plans before Reserved Instances**: Start with Compute Savings Plans for flexibility. Add Standard RIs only for long-running, stable instance types with high confidence.

## Gotchas

- **Instance store data is ephemeral**: Stopped or terminated instances lose all instance store data. Use EBS for anything that needs to survive a stop.
- **EBS root volume DeleteOnTermination default**: Root volumes are deleted on termination by default. Set `delete_on_termination = false` in the launch template if you need the root volume to persist.
- **Regional RI does not reserve capacity**: A regional Reserved Instance applies a billing discount but does not guarantee instance availability. For capacity reservations, use zonal RIs or On-Demand Capacity Reservations.
- **Spot Instances require interruption handling**: Applications must handle SIGTERM gracefully within 2 minutes. Stateless apps or apps with checkpointing work best.
- **T-series CPU credits**: Burstable instances accumulate CPU credits when below baseline and spend them during bursts. `unlimited` mode allows sustained bursting at extra cost. Watch for `CPUCreditBalance` in CloudWatch.
- **ENI limit per instance type**: The number of network interfaces (and therefore secondary IPs/security groups) is bounded by instance type. Check limits before dense networking designs.
- **Nitro vs Xen**: Only older instance generations use Xen. Nitro is required for features like ENA networking, NVMe, and EBS encryption performance. Default to Nitro-based types.
- **Mac instances on Dedicated Hosts only**: Mac instances (`mac1`, `mac2`) require a Dedicated Host with a minimum 24-hour allocation period. They are On-Demand only — no Spot or Reserved Instances (Savings Plans apply).
- **AMD SEV-SNP surcharge**: Enabling AMD SEV-SNP adds 10% of the On-Demand hourly rate as a separate charge. RIs and Savings Plans do not offset this fee.

## References

- [[Compute/AWS ECS]]
- [[Compute/AWS EC2 Auto Scaling]]
- [[Storage/AWS S3]]
- [[IAM/AWS IAM]]
- [[Observability/AWS CloudWatch]]
- [EC2 Image Builder](https://docs.aws.amazon.com/imagebuilder/latest/userguide/what-is-image-builder.html) — automates AMI creation, testing, and distribution pipelines
- [AWS Systems Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/what-is-systems-manager.html) — fleet management, patch management, Session Manager (SSH alternative), and run command
