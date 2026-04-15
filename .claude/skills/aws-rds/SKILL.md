---
name: aws-rds
description: Use when working with Amazon RDS or Aurora - choosing database engines, instance classes, storage types, Multi-AZ vs read replicas, Aurora vs RDS, Aurora Serverless v2, backups and point-in-time recovery, RDS Proxy, IAM authentication, subnet groups, encryption, parameter groups, or any RDS/Aurora architecture and troubleshooting decisions
---

# AWS RDS & Aurora Expert Skill

Comprehensive Amazon RDS and Aurora guidance covering engine selection, high availability, storage, networking, security, backups, and production patterns. Based on the official AWS RDS User Guide and Aurora User Guide.

## When to Use This Skill

**Activate this skill when:**
- Choosing between RDS engines (MySQL, PostgreSQL, Aurora, etc.)
- Deciding between Aurora Serverless v2 vs provisioned
- Designing high availability (Multi-AZ instances vs Multi-AZ clusters)
- Configuring read replicas (scaling, cross-region DR)
- Setting up networking (subnet groups, security groups, RDS Proxy)
- Configuring encryption at rest and in transit
- Planning backup and point-in-time recovery strategy
- Setting up IAM database authentication
- Sizing instance classes and storage (gp2 vs gp3 vs io1/io2)
- Troubleshooting connectivity, failover, or replication lag issues

**Don't use this skill for:**
- DynamoDB (NoSQL, different service)
- ElastiCache (in-memory caching)
- Self-managed databases on EC2
- Redshift (data warehouse)

---

## Engine Selection

### RDS Engines

| Engine | Best For |
|--------|----------|
| **PostgreSQL** | Complex queries, JSONB, PostGIS, open-source preference |
| **MySQL** | Web apps, broad ecosystem, Laravel/WordPress stacks |
| **MariaDB** | MySQL-compatible with additional features |
| **Oracle** | Enterprise workloads with Oracle licensing |
| **SQL Server** | .NET / Windows application stacks |
| **IBM Db2** | Mainframe migration workloads |

### Aurora vs Standard RDS

Aurora is AWS's cloud-native relational engine, compatible with MySQL and PostgreSQL but architecturally different:

| | Standard RDS | Aurora |
|---|---|---|
| **Storage** | EBS per instance | Distributed cluster volume, 6 copies across 3 AZs |
| **Read replicas** | Up to 5, async lag | Up to 15, near-zero lag (shared storage) |
| **Failover** | 1–2 min (Multi-AZ instance) | < 30 seconds to an existing replica |
| **Storage scaling** | Manual resize | Auto-grows in 10 GB increments to 128 TB |
| **Cross-region** | Read replica | Global Database (< 1s replication lag) |
| **Serverless** | Not available | Aurora Serverless v2 |
| **Cost** | Lower base cost | ~20% more per instance, but storage is often cheaper |

**Choose Aurora when:** You want managed HA, fast failover, high read throughput, or Aurora Serverless v2 scaling. Aurora is the default choice for new production MySQL/PostgreSQL workloads.

**Choose standard RDS when:** You need Oracle, SQL Server, Db2, or MariaDB; or you have strict cost constraints and a simple workload.

---

## Aurora Architecture

Aurora separates compute from storage:

```
Writer instance ──┐
                  ├── Cluster volume (6 copies across 3 AZs, auto-grows)
Reader 1 ─────────┤
Reader 2 ─────────┘
```

- **Writer instance:** handles all writes; also handles reads
- **Reader instances:** connect to the same storage volume — no replication lag for reads
- **Cluster endpoint:** always points to the writer
- **Reader endpoint:** load-balances across all readers
- **Instance endpoints:** point to a specific instance (for pinned connections)

Aurora only writes each piece of data once — readers don't replicate data, they share the same storage layer.

### Aurora Failover

When the writer fails, Aurora promotes an existing reader (lowest-numbered promotion tier wins). DNS flips to the new writer. With a reader in place, failover typically completes in < 30 seconds. Without any readers, a new writer must be created from the cluster volume — takes longer.

**Best practice:** Always keep at least one reader in a different AZ from the writer.

---

## Aurora Serverless v2

On-demand autoscaling for Aurora. Capacity scales in **Aurora Capacity Unit (ACU)** increments — 1 ACU ≈ 2 GB memory + proportional CPU and networking.

### How It Scales

- Scales in **0.5 ACU increments** without pausing connections or transactions
- Scales up within seconds in response to demand spikes
- Scales down gradually during low activity
- Billed per second for ACUs consumed

### Configuration

```
Minimum capacity: 0.5 ACU  (scale to near-zero when idle)
Maximum capacity: 128 ACU  (128 ACU ≈ 256 GB RAM)
```

Set minimum capacity based on the fastest acceptable cold-start latency. Setting minimum to 0 ACU (scale to zero) is only available for development/test — production should use ≥ 0.5 ACU.

### When to Use Serverless v2

| Scenario | Use Serverless v2? |
|----------|--------------------|
| Unpredictable or spiky traffic | Yes |
| Multi-tenant SaaS (one cluster per tenant) | Yes |
| Dev/test environments | Yes — scale to near-zero when idle |
| New application (unknown load) | Yes — observe and tune |
| Steady, predictable high load | Provisioned may be cheaper |

### Mixing Serverless v2 and Provisioned

You can have a provisioned writer with Serverless v2 readers — useful for absorbing read spikes without over-provisioning the writer.

---

## High Availability

### Multi-AZ Instance (Standard RDS)

- Synchronous standby in a different AZ — writes must be confirmed on both before committing
- Standby is **not readable** — it exists purely for failover
- Failover time: **1–2 minutes** (DNS TTL propagation)
- Automatic failover triggered by: instance failure, AZ failure, OS patching, storage failure

```
Primary (AZ-1, read/write)
    │ synchronous replication
Standby (AZ-2, not accessible)
```

### Multi-AZ Cluster (Standard RDS)

- Primary + 2 readable standby instances across 3 AZs
- Failover time: **< 35 seconds**
- Standby instances can serve read traffic
- Higher cost than Multi-AZ instance

### Aurora HA

Aurora's storage layer is inherently multi-AZ (6 copies across 3 AZs). Add reader instances across AZs for fast compute failover:

```
Writer (AZ-1)
Reader (AZ-2)   ← failover target, priority tier 1
Reader (AZ-3)   ← failover target, priority tier 2
     └── all share the same cluster volume
```

**Failover priority tiers:** Assign lower tier numbers to readers you prefer to promote first.

### High Availability Comparison

| | RDS Multi-AZ Instance | RDS Multi-AZ Cluster | Aurora |
|---|---|---|---|
| Failover time | 1–2 min | < 35 sec | < 30 sec (with reader) |
| Standby readable | No | Yes | Yes (readers) |
| Max readers | 5 (replicas) | 2 standbys | 15 replicas |
| Storage redundancy | AZ-level | AZ-level | 6-way, 3 AZs |

---

## Read Replicas

Read replicas offload read traffic from the primary and can serve as a DR target.

### Standard RDS Read Replicas

- Asynchronous replication — **replication lag exists**
- Up to 5 replicas per source instance
- Can create replicas of replicas (MySQL, MariaDB, PostgreSQL only)
- Can be promoted to standalone instance (breaks replication)
- Cross-region replicas: data transfer costs apply

**When replication lag matters:** Avoid routing reads that require up-to-date data to replicas. Use read replicas for analytics, reporting, and eventually-consistent reads only.

### Aurora Read Replicas

- Share the same storage as the writer — **near-zero replication lag**
- Up to 15 replicas
- Act as HA failover targets, not just read scaling
- Cross-region Aurora replicas are separate from Global Database

### Cross-Region Read Replicas (DR Pattern)

```
Primary Region: us-east-1
    └── Source DB instance
         └── async replication
              └── Cross-region replica: us-west-2
                   (can be promoted to standalone if primary region fails)
```

Promote the cross-region replica manually during a regional DR event.

---

## Instance Classes

| Class | Use Case |
|-------|----------|
| **db.t4g / db.t3** | Dev/test, variable low-traffic workloads (burstable CPU) |
| **db.m7g / db.m6g / db.m5** | General purpose production workloads |
| **db.r7g / db.r6g / db.r5** | Memory-intensive workloads (large working sets, caches) |
| **db.x2g / db.x2iedn** | Extreme memory (SAP HANA, large Oracle DBs) |
| **db.c6gn** | Compute-intensive workloads |

**Graviton-based classes** (db.t4g, db.m7g, db.r7g) offer ~20% better price-performance — prefer them for new deployments.

**Avoid db.t* in production** unless workload is genuinely low and bursty. Sustained CPU usage on burstable instances exhausts CPU credits and causes severe throttling.

---

## Storage

### Storage Types (Standard RDS)

| Type | IOPS | Use Case |
|------|------|----------|
| **gp3 (General Purpose SSD)** | 3,000–16,000 provisioned | Default for most workloads; IOPS independent of size |
| **gp2 (General Purpose SSD)** | 3 IOPS/GB, burst to 3,000 | Legacy; prefer gp3 for new deployments |
| **io1 / io2 (Provisioned IOPS)** | Up to 256,000 IOPS | I/O-intensive production (high-throughput OLTP) |
| **Magnetic** | Low | Legacy only — do not use |

**gp3 vs gp2:** gp3 lets you provision IOPS and throughput independently of storage size, making it almost always cheaper than gp2. Migrate existing gp2 instances to gp3.

**Storage autoscaling:** Enable it — RDS automatically increases storage when free space falls below a threshold. Prevents storage-full outages. Set a maximum storage threshold to control costs.

### Aurora Storage

Aurora manages storage automatically:
- Auto-grows in 10 GB increments up to 128 TB
- You do not provision storage size or IOPS
- Billed for consumed storage, not allocated storage
- No storage autoscaling configuration needed

---

## Networking

### DB Subnet Groups

A DB subnet group is a collection of subnets (in different AZs) where RDS can place instances.

**Requirements:**
- Minimum 2 subnets in 2 different AZs
- Use private subnets — databases should never be publicly accessible
- Reserve adequate IP space (at least one spare IP per subnet for maintenance operations)

**Best practice:** Include subnets from all AZs in your region even for Single-AZ deployments — makes future Multi-AZ conversion seamless.

### Security Groups

Apply security groups at the DB instance level to control inbound access:

```
App SG  → DB SG: allow TCP 5432 (PostgreSQL) or 3306 (MySQL)
         Never allow 0.0.0.0/0 to database ports
```

Use **SG-to-SG references**, not CIDR blocks — more maintainable and automatically tracks instance IP changes.

### Public Accessibility

Keep `PubliclyAccessible = false` for all production databases. For dev/test access from outside the VPC, use:
1. A bastion host or SSM Session Manager port forwarding
2. AWS Client VPN
3. Direct Connect

### Always connect via DNS endpoint, never IP

RDS reassigns IPs during failover, maintenance, and restores. The DNS endpoint stays stable.

---

## RDS Proxy

A fully managed connection pooler that sits between your application and the database.

```
App (Lambda / ECS tasks)
    │
RDS Proxy  ← maintains persistent pool of DB connections
    │
RDS / Aurora instance
```

### Why Use It

- **Lambda / serverless workloads:** Each invocation opens a new DB connection — thousands of functions overwhelm the DB connection limit. Proxy multiplexes many app connections into a small number of DB connections.
- **Connection storms:** Proxy queues excess connections rather than letting them crash the DB.
- **Faster failover:** Proxy automatically reconnects to the new primary after failover, preserving application connections (reduces failover impact from 1–2 min to seconds).
- **Centralized IAM auth and Secrets Manager integration.**

### Limitations

- Must be in the same VPC as the database — not publicly accessible
- Long-running transactions cause **session pinning** (breaks multiplexing — one app connection ties up one DB connection for the transaction duration)
- 200 secrets maximum per proxy (limits distinct DB users)
- Only connects to writer — can't proxy to read replicas directly (use separate proxy per reader endpoint)

### When Not to Use It

- Applications with long transactions as the dominant workload
- Low-connection workloads (traditional always-on services with a fixed small pool)
- SQL Server 2022 / SQL Server 2014

---

## Backups

### Automated Backups

- Runs daily during the **backup window** you configure
- **Retention period:** 1–35 days (0 disables automated backups)
- Stored in S3 — no direct access, managed by RDS
- First backup is a full snapshot; subsequent are incremental
- Enables **point-in-time recovery (PITR)** to any second within the retention window
- Instance must be in `available` state for backups to run

**Recommendation:** Set retention to at least 7 days in production. 35 days for regulated workloads.

### Point-in-Time Recovery

Restore to any second within the retention period:

```bash
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier mydb \
  --target-db-instance-identifier mydb-restored \
  --restore-time 2024-03-15T08:00:00Z
```

PITR always restores to a **new DB instance** — it does not overwrite the source.

### Manual Snapshots

- Not deleted when the instance is deleted (unlike automated backups)
- Can be copied across regions and shared with other AWS accounts
- Up to 100 manual snapshots per region per account
- Use for: pre-migration checkpoints, long-term retention beyond 35 days, cross-account sharing

### Aurora Backups

- Continuous incremental backups to S3 — no performance impact
- PITR available within the retention window
- Backtrack (Aurora MySQL): rewind the cluster in-place without restoring — available up to 72 hours back

---

## Encryption

### Encryption at Rest

- Enable at instance creation — cannot be added to an existing unencrypted instance
- Uses AWS KMS (AES-256)
- Encrypts: storage, automated backups, snapshots, read replicas, logs
- To encrypt an existing unencrypted instance:
  1. Take a snapshot
  2. Copy the snapshot with encryption enabled
  3. Restore to new instance from the encrypted snapshot

### Encryption in Transit

- All RDS engines support SSL/TLS connections
- Enforce TLS using a parameter group setting:
  - PostgreSQL: `rds.force_ssl = 1`
  - MySQL/MariaDB: `require_secure_transport = ON`
- Download RDS CA bundle from AWS to verify the server certificate

### IAM Database Authentication

Authenticate with a short-lived token (15 minutes) instead of a password.

**Supported engines:** MySQL, MariaDB, PostgreSQL

**How it works:**
1. App calls `generate-db-auth-token` via AWS SDK/CLI
2. Uses the token as the password when connecting
3. Token is validated by RDS against IAM policy

```python
import boto3, pymysql

client = boto3.client('rds')
token = client.generate_db_auth_token(
    DBHostname=endpoint,
    Port=3306,
    DBUsername='iam_user',
    Region='us-east-1'
)
conn = pymysql.connect(host=endpoint, user='iam_user', password=token, ssl={'ca': 'rds-ca.pem'})
```

**Benefits:** No passwords in code or environment variables; IAM centrally manages access; connections require active IAM credentials.

**Limitations:** Max ~200 new connections/second (token validation overhead); requires ~300–1000 MiB additional instance memory; not compatible with Kerberos.

---

## Parameter Groups

Parameter groups are the mechanism to configure database engine settings.

- **DB parameter group:** configures a single DB instance
- **DB cluster parameter group (Aurora):** configures all instances in a cluster

Changes to static parameters require a reboot; dynamic parameters apply immediately.

**Common production parameter changes:**

PostgreSQL:
```
shared_buffers         = 25% of instance RAM
work_mem               = tune per query complexity
max_connections        = tune based on expected connections (use Proxy to reduce this)
log_min_duration_statement = 1000  (log queries > 1s)
rds.force_ssl          = 1
```

MySQL/Aurora MySQL:
```
innodb_buffer_pool_size = 75% of instance RAM (set automatically on Aurora)
slow_query_log          = 1
long_query_time         = 1
require_secure_transport = ON
```

---

## Aurora Global Database

Spans multiple AWS Regions with < 1 second replication lag:

```
Primary Region (us-east-1):  writer + readers
Secondary Region (eu-west-1): read-only cluster (< 1s lag)
Secondary Region (ap-southeast-1): read-only cluster
```

**Use cases:**
- Globally distributed read traffic (route regional users to the nearest region)
- Regional disaster recovery with < 1 minute RPO and ~1 minute RTO (manual failover)
- Data sovereignty (replicate to a secondary region with a local reader)

**Managed planned failover:** promotes a secondary region to primary with near-zero data loss (RPO ≈ 0).

---

## Architecture Patterns

### Standard Production (Aurora PostgreSQL)

```
App tier (ECS/EKS, private subnets)
    │
    └── RDS Proxy (same VPC)
         │
         ├── Aurora Writer (AZ-1)  ← cluster endpoint
         └── Aurora Reader (AZ-2)  ← reader endpoint
              └── shared cluster volume (6 copies, 3 AZs)
```

### Serverless API with Aurora Serverless v2

```
API Gateway → Lambda (no persistent server)
                  │
             RDS Proxy  (connection pooling essential for Lambda)
                  │
             Aurora Serverless v2
               min: 0.5 ACU
               max: 32 ACU
```

### Multi-Region Disaster Recovery

```
Primary: us-east-1
  Aurora Global Database (writer)
        │ < 1s replication
Secondary: us-west-2
  Aurora Global Database (read-only)
  (promote to writer during regional DR event)
```

### Dev/Test Cost Optimization

```
Aurora Serverless v2
  min: 0 ACU  (scale to near-zero overnight/weekends)
  max: 8 ACU
Automated backups: 1 day retention
No Multi-AZ required
```

---

## Security Best Practices

1. **Always use private subnets** — databases must not be publicly accessible
2. **SG-to-SG rules only** — never allow 0.0.0.0/0 to database ports
3. **Encrypt at rest** — enable KMS encryption at creation time
4. **Enforce TLS** — set `rds.force_ssl` or `require_secure_transport` in parameter group
5. **Use IAM auth or Secrets Manager** — no hardcoded passwords in application code
6. **Enable automated backups** — minimum 7 days retention in production
7. **Enable deletion protection** — prevents accidental instance deletion
8. **Use RDS Proxy for Lambda** — prevents connection pool exhaustion
9. **Enable Enhanced Monitoring and Performance Insights** — default to 7-day retention on Performance Insights (free tier)
10. **Separate parameter groups per environment** — never share parameter groups between prod and non-prod

---

## Common Troubleshooting

| Symptom | Likely Cause |
|---------|-------------|
| `could not connect to server` / `Connection refused` | Security group not allowing inbound on DB port from app SG; wrong port; DB not in `available` state |
| `FATAL: password authentication failed` | Wrong credentials; IAM auth token expired (15-min TTL); DB user doesn't exist |
| `Too many connections` | Connection limit hit — add RDS Proxy, reduce `max_connections`, or scale instance |
| High replication lag on read replica | Heavy write load on primary; read replica undersized; network issues (cross-region) |
| Failover took longer than expected | No pre-warmed reader instance; DNS TTL caching in application (use short TTL, always connect via DNS) |
| Storage full / instance in `storage-full` state | Enable storage autoscaling; automated backups stop when storage is full |
| Slow queries after restore or failover | Buffer pool is cold — warm-up period needed; check Performance Insights for top wait events |
| Snapshot copy fails cross-region | KMS key is regional — must specify a KMS key in the destination region |
| `FATAL: remaining connection slots are reserved` (PostgreSQL) | All connections consumed; reserve slots via `superuser_reserved_connections`; add Proxy |
