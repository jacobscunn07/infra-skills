---
title: AWS RDS
tags: [rds, database, aws, mysql, postgresql, aurora, multi-az, read-replicas, backup, encryption, proxy]
related: ["[[Security/AWS KMS]]", "[[IAM/AWS IAM]]", "[[Observability/AWS CloudWatch]]", "[[Networking/AWS VPC]]"]
created: 2026-04-28
updated: 2026-04-28
---

## Overview

Amazon RDS is a managed relational database service supporting MySQL, PostgreSQL, MariaDB, Microsoft SQL Server, Oracle, and IBM Db2. AWS handles infrastructure, OS patching, backups, and failover — you own query tuning, schema design, and application optimization. Aurora is a separate service covered in the Aurora User Guide.

## Key Concepts

### DB Instance Classes

- **`db.m*`** — general purpose; good default for most workloads
- **`db.r*` / `db.x*` / `db.z*`** — memory-optimized; use for in-memory databases, large working sets
- **`db.c*`** — compute-optimized; CPU-bound queries
- **`db.t*`** — burstable; dev/test only; credit exhaustion causes throttling under sustained load
- Graviton (`db.r6g`, `db.m7g`, etc.) offers better price/performance; check engine compatibility first
- Instance-level throughput caps can be a bottleneck even if storage IOPS are provisioned higher — always cross-check [EBS-optimized instance limits](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-optimized.html)

### Storage Types

| Type | Max IOPS | Max Throughput | Best For |
|------|----------|----------------|----------|
| **io2 Block Express** | 256,000 | 4,000 MB/s | Production OLTP, sub-ms latency |
| **io1** | 256,000 (64K SQL Server) | 4,000 MB/s | Production OLTP, cost-conscious |
| **gp3** | 64,000 | 4,000 MB/s | Dev/test, broad workloads |
| **gp2** | 64,000 | 1,000 MB/s | Legacy; prefer gp3 |
| **Magnetic** | 1,000 | Low | **Deprecated April 30, 2026** |

Key ratios:
- `io2`: 0.5–1,000 IOPS per GiB; `io1`: 0.5–50 IOPS per GiB; `gp3`: 12,000 IOPS baseline for 400+ GiB (striped)
- `gp3` for MySQL/MariaDB auto-increases throughput if IOPS > 32,000 — other engines don't do this
- Dedicated Log Volume (DLV) on io1/io2 separates transaction logs for better throughput consistency (fixed 1,024 GiB, 3,000 IOPS)

### Multi-AZ

Two deployment modes:

| | Multi-AZ Instance | Multi-AZ DB Cluster |
|---|---|---|
| Standbys | 1 | 2 |
| Standbys serve reads | No | Yes |
| AZs covered | 2 | 3 |
| Use case | Basic HA | HA + read scaling |

- Synchronous replication to standby(s); automatic failover
- Single-standby mode: standby is for failover only — no read offload

### Read Replicas

- **Asynchronous** replication; eventual consistency — not suitable for strong-consistency reads
- Supported on all engines (Db2, MariaDB, MySQL, Oracle, PostgreSQL, SQL Server)
- Cross-region replicas supported; data transfer charges apply
- No auto-scaling of replicas — add/remove manually
- Deleting the primary without first deleting same-region replicas promotes each replica to a standalone instance
- Can use a different storage type from the primary (e.g., primary on io2, replica on gp3)
- Replica chains (replica-of-a-replica) only supported on MariaDB, MySQL, and some PostgreSQL versions

### Automated Backups & PITR

- Full storage-volume snapshot during the configured backup window + transaction logs for PITR
- PITR to any second within the retention window (1–35 days)
- Backups only run when the instance is in `available` state; pauses during same-region snapshot copies
- Manual snapshots: on-demand, unlimited lifetime, not deleted when instance is deleted; 100 manual snapshots per Region limit
- First snapshot is a full copy; subsequent automated snapshots are incremental
- Cross-region snapshot copies increase destination Region's backup storage cost

### RDS Proxy

- Connection pooler sitting between application and database; reuses DB connections
- Reduces memory/CPU overhead from connection churn; critical for Lambda or ECS-heavy architectures
- Supports MySQL, MariaDB, PostgreSQL, SQL Server (not Oracle, not RDS Custom)
- Must be in same VPC; cannot be publicly accessible
- Supports IAM authentication and Secrets Manager credential storage
- Default endpoint spans only 2 AZs; create additional endpoints to cover all AZs
- Quota: 20 proxies per account
- `rdsproxyadmin` DB user is auto-created and must never be modified or deleted

### IAM Database Authentication

- Authenticate using a 15-minute temporary token (AWS Signature V4) instead of a password; no credentials in code
- Supported on MySQL, MariaDB, PostgreSQL only
- Token size can be >1 KB — some ODBC/JDBC drivers truncate it, causing auth failure
- Hard limit: **<200 new connections/second** — token generation overhead throttles higher rates; use RDS Proxy to work around
- PostgreSQL: `rds_iam` role takes precedence over password auth; cannot use IAM + Kerberos simultaneously
- Requires ~300–1,000 MiB extra instance memory; reduce buffer pool on burstable instances if needed

### Encryption at Rest

- AES-256; encrypts storage, logs, automated backups, replicas, and snapshots transparently
- Must be enabled at creation time — **cannot encrypt an existing unencrypted instance**
- Workaround: snapshot → copy snapshot with encryption → restore from encrypted snapshot
- KMS key cannot be changed after creation; workaround: snapshot → copy with different key → restore
- If the KMS key is disabled: 7-day recovery window before instance enters an unrecoverable state; always keep backups on encrypted instances
- Cannot share snapshots encrypted with AWS managed keys across accounts (use customer managed keys)
- Same-region read replicas must use the same KMS key as the primary; cross-region replicas use the destination region's key
- In-transit encryption: same-region traffic is auto-encrypted on supported Nitro instance types (M6i, M7g, R6i, R7g, etc.); cross-region replication always encrypted

## Patterns

### Multi-AZ with Read Replicas for Read Scaling + HA

Deploy a Multi-AZ instance for durability + automatic failover, then add one or more read replicas in the same region for read offload. Route read-heavy workloads (analytics, reporting) to replicas via a DNS-aware connection router or RDS Proxy.

**Tradeoff:** Replicas use asynchronous replication — stale reads are possible. Do not use replicas for reads that require the latest committed data.

### RDS Proxy for Serverless / High-Connection Workloads

Lambda functions create a new DB connection per invocation; at scale this exhausts DB connection limits. Place RDS Proxy between Lambda and RDS to multiplex connections.

**Tradeoff:** Proxy adds a small latency hop and has its own quota (20 per account). Session pinning (caused by large SQL statements or certain SET commands) can reduce pool efficiency.

### Encrypted Instance from an Unencrypted Source

1. `CreateDBSnapshot` on the unencrypted instance
2. `CopyDBSnapshot` with `--kms-key-id` to create an encrypted copy
3. `RestoreDBInstanceFromDBSnapshot` from the encrypted snapshot

**Tradeoff:** Incurs snapshot storage costs; the new instance has a new endpoint — update application configs.

### gp3 for Cost-Optimized General Workloads

Use gp3 for most non-latency-critical workloads. Baseline of 3,000 IOPS and 125 MB/s at no extra charge; provision additional IOPS/throughput only when you actually need them.

**Tradeoff:** Storage modification from gp2 <400 GiB → gp3 triggers a data migration (new volumes + transparent copy) that can saturate I/O for several hours.

### Storage Modification Impact Mitigation

Schedule storage type or size changes during low-traffic maintenance windows. Monitor `DiskQueueDepth` during the modification — sustained depth >100 indicates IOPS saturation. The instance stays available but performance degrades during migration.

## Gotchas

- **Magnetic storage end-of-life:** Forced migration to gp3 begins April 29, 2026; snapshot restores default to gp3 from June 1, 2026. Migrate before that date.
- **gp2 burst depletion:** Volumes <1,000 GiB rely on I/O credits; sustained high-throughput workloads deplete credits silently. Switch to gp3 with explicit IOPS provisioning.
- **Instance IOPS cap:** Always check instance-class EBS throughput limits — a `db.r6g.large` caps at ~40,000 IOPS regardless of provisioned storage IOPS.
- **No cross-engine PITR:** PITR restores to a new instance; it doesn't overwrite in place.
- **Free Tier limitations:** No Multi-AZ, no reserved instances, no snapshot migration, no query editor on free-tier instances.
- **RDS Proxy session pinning:** Statements >16 KB or certain session-state changes pin the session to a single backend connection, negating pool efficiency. Review the [avoiding pinning guide](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy-pinning.html) before deployment.
- **IAM auth + high concurrency:** >200 new connections/second hits AWS token generation limits; fall back to password auth or layer RDS Proxy.
- **Encryption is immutable:** You cannot change the KMS key or toggle encryption on a running instance. Plan encryption strategy before launch.
- **Manual snapshots don't auto-delete:** After deleting an instance, manual snapshots remain and accrue storage costs indefinitely until explicitly deleted.
- **Backup window + maintenance window overlap:** If both windows overlap, backups may be postponed. Stagger them by at least 30 minutes.
- **`rdsproxyadmin` user:** Never rename, drop, or modify this auto-created user — doing so renders the proxy non-functional.

## References

- [[Security/AWS KMS]]
- [[IAM/AWS IAM]]
- [[Observability/AWS CloudWatch]]
- [[Networking/AWS VPC]]
