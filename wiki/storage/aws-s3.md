---
title: AWS S3
tags: [s3, storage, object-storage, encryption, replication, lifecycle, access-control]
related: ["[[IAM/AWS IAM]]", "[[Concepts/Least Privilege]]", "[[Storage/AWS EFS]]", "[[Storage/AWS ECR]]"]
created: 2026-04-27
updated: 2026-04-29
---

## Overview

Amazon S3 is AWS's object storage service. Objects live in buckets identified by globally unique names. S3 provides 11 nines of durability through multi-AZ redundancy, strong read-after-write consistency, and an access control model that layers IAM policies, bucket policies, and Block Public Access.

## Key Concepts

- **Bucket**: a globally unique namespace container; exists in one region but accessible globally
- **Object**: data + metadata identified by a key (the full "path-like" name); max 5 TB per object
- **Key**: the full object name, e.g. `logs/2024/01/app.log`; `/` is a naming convention, not a real hierarchy
- **Strong consistency**: all PUTs and DELETEs are immediately visible across GET and LIST; no eventual consistency for objects
- **Bucket-level eventual consistency**: create/delete/versioning changes take ~15 minutes to propagate
- **Last-writer-wins**: concurrent writes to the same key have no locking; implement app-level coordination if needed
- Four bucket types: General Purpose, Directory (Express One Zone), Table (Iceberg), Vector (AI embeddings)

## Storage Classes

| Class | Access Pattern | Min Duration | Retrieval |
|---|---|---|---|
| Standard | Frequent | None | Immediate |
| Express One Zone | High-perf frequent, single-AZ | None | Single-digit ms |
| Intelligent-Tiering | Unknown/changing | None | Varies by tier |
| Standard-IA | Infrequent | 30 days | Immediate |
| One Zone-IA | Infrequent, non-critical | 30 days | Immediate |
| Glacier Instant Retrieval | Archive, quarterly | 90 days | Immediate |
| Glacier Flexible Retrieval | Archive, hours OK | 90 days | Minutes–hours |
| Glacier Deep Archive | Long-term compliance | 180 days | Up to 12 hours |

**Choosing:**
- Default to **Standard** for new workloads
- **Intelligent-Tiering** when access patterns are unknown — auto-moves objects, no retrieval fee
- **Standard-IA** for backups accessed monthly or less
- **Glacier Instant Retrieval** for quarterly-access archives needing instant response
- **Glacier Deep Archive** for compliance data held 7–10 years
- Avoid **One Zone-IA** unless data is reproducible (single-AZ; AZ loss = data loss)
- Objects under 128 KB are never transitioned by lifecycle rules (not cost-effective)
- Early deletion charges apply: deleting before the minimum duration bills the full period

## Access Control

S3 uses layered access control — IAM policies, bucket policies, Block Public Access, and Access Points are all evaluated together.

### Block Public Access

On by default for all buckets. Leave it on. Disable only for intentional public static websites.

```hcl
resource "aws_s3_bucket_public_access_block" "example" {
  bucket                  = aws_s3_bucket.example.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}
```

### Bucket Policies

Resource-based policy attached to the bucket. Use for cross-account access, HTTPS enforcement, and VPC endpoint restrictions.

```json
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"],
  "Condition": { "Bool": { "aws:SecureTransport": "false" } }
}
```

VPC-only restriction:
```json
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"],
  "Condition": { "StringNotEquals": { "aws:sourceVpce": "vpce-xxxxxxxx" } }
}
```

Limit: 20 KB max policy size. Use Access Points or S3 Access Grants when you exceed this.

### IAM Policies

`s3:ListBucket` targets the **bucket ARN**; `s3:GetObject`/`PutObject`/`DeleteObject` target `bucket/*`. This asymmetry is a common source of 403 errors.

```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:ListBucket"],
  "Resource": [
    "arn:aws:s3:::my-bucket",
    "arn:aws:s3:::my-bucket/*"
  ]
}
```

### Decision Matrix

| Scenario | Tool |
|---|---|
| Same-account access | IAM policy |
| Cross-account access | Bucket policy + IAM policy (both must allow) |
| Shared dataset, many consumers | S3 Access Points |
| VPC-only access | Bucket policy with `aws:sourceVpce` condition |
| Public static website | Bucket policy |
| Per-end-user audit trail | S3 Access Grants |
| S3 server access log delivery | Bucket ACL (only valid modern use) |

### ACLs

Disabled by default (Bucket owner enforced). Keep them disabled. Bucket policies and IAM are more flexible and auditable. The one exception: granting S3 log delivery permission to write access logs.

## Encryption

All objects are encrypted by default since January 2023.

| Option | Key Control | Audit Trail | Use When |
|---|---|---|---|
| SSE-S3 | AWS | None | Default; no compliance requirement |
| SSE-KMS | AWS KMS (your key) | CloudTrail | Compliance, key rotation, cross-account |
| DSSE-KMS | AWS KMS, two layers | CloudTrail | Strict dual-layer compliance |
| SSE-C | You provide per-request | None | Full key custody |

**SSE-KMS gotcha:** every GET/PUT calls the KMS API. High-throughput workloads hit KMS request quotas. Enable **S3 Bucket Keys** to batch KMS calls and reduce KMS API costs by up to 99%.

**Re-encrypting existing objects:** changing bucket default encryption does not re-encrypt objects already stored. Use S3 Batch Operations (Copy action) to re-encrypt at scale.

## Versioning

Preserves every version of every object. Once enabled, it can only be suspended — never fully disabled.

- Protects against accidental overwrites and deletes
- Deleting a versioned object adds a delete marker; prior versions are retained
- Required for: Object Lock, Cross-Region Replication
- Storage costs accumulate across all versions — always pair with lifecycle rules

```hcl
resource "aws_s3_bucket_versioning" "example" {
  bucket = aws_s3_bucket.example.id
  versioning_configuration {
    status = "Enabled"
  }
}
```

Lifecycle rule to clean up old versions:
- Expire noncurrent versions after 90 days
- Keep at most 3 noncurrent versions
- Delete expired object delete markers

## Object Lock (WORM)

Prevents objects from being deleted or overwritten. Must be enabled at bucket creation — cannot be added to existing buckets.

| Mode | Who Can Override | Use Case |
|---|---|---|
| Compliance | Nobody (not even root) | Regulatory WORM (SEC 17a-4, FINRA) |
| Governance | Users with `s3:BypassGovernanceRetention` | Internal WORM with escape hatch |

**Legal hold**: separate from retention — prevents deletion regardless of retention period, lifted explicitly.

## Lifecycle Rules

Automate transitioning objects to cheaper classes or expiring them.

**Transition constraints:**
- Standard → Standard-IA or One Zone-IA: minimum 30 days in Standard
- Standard-IA → Glacier: minimum 30 days in Standard-IA

**Always include a rule to abort incomplete multipart uploads** — orphaned parts incur indefinite storage charges with no automatic cleanup.

Common patterns:

Log retention (90-day delete):
```
Prefix: logs/
Transition to Standard-IA: day 30
Expire objects: day 90
```

Data lake archiving:
```
Prefix: data/
Transition to Standard-IA: day 30
Transition to Glacier Flexible Retrieval: day 90
Transition to Glacier Deep Archive: day 365
```

Versioned bucket cleanup:
```
Expire noncurrent versions: 30 days, keep 3 max
Delete expired delete markers: true
Abort incomplete multipart uploads: 7 days
```

## Replication

Copies objects asynchronously to destination buckets. Live replication covers new objects only; use S3 Batch Replication for existing objects.

**Requirements:** versioning enabled on both source and destination; IAM role with read on source, write on destination.

| | CRR | SRR |
|---|---|---|
| Scope | Different regions | Same region |
| Use cases | DR, latency reduction, compliance geo | Log aggregation, prod→test sync |
| Cost | Data transfer + replication | Replication only (no transfer fee) |

**What replicates:** object data, metadata, version ID, tags, object lock settings, ACLs. Delete markers are optional (configure explicitly). Version-ID deletes are not replicated by default (protects against malicious deletes).

**S3 Replication Time Control (S3 RTC):** SLA-backed guarantee — 99.99% of objects replicated within 15 minutes. Adds cost. Use when downstream systems require predictable replication lag.

**Batch Replication:** for objects that predate the replication rule or to retry failures:
```bash
aws s3control create-job --operation '{"S3ReplicateObject":{}}' ...
```

## Performance

**Per-prefix rate limits:**
- 3,500 PUT/COPY/POST/DELETE requests/second
- 5,500 GET/HEAD requests/second

Distribute objects across multiple prefixes to scale beyond these limits. Avoid sequential date-based prefixes (e.g. `2024/01/`) — they concentrate load on one partition.

**Multipart upload:** required for objects over 5 GB; recommended over 100 MB. Benefits: parallel upload, resume on failure, start before final size is known. Min part size: 5 MB (except last part). Max 10,000 parts.

**Byte-range fetches:** download specific byte ranges in parallel to reconstruct large objects faster. Useful for partial reads, parallel downloads, and resuming interrupted downloads.

**S3 Transfer Acceleration:** routes uploads through CloudFront edge locations over AWS backbone. Useful for geographically distant clients. Adds per-GB cost.

**S3 Express One Zone:** directory buckets with single-digit millisecond latency for ML training data, real-time analytics, and high-frequency read/write.

## Data Processing & Automation

### S3 Object Lambda

Add custom code to S3 GET, HEAD, and LIST requests to modify/process data in-flight — without storing derived copies.

Common uses: filter rows, resize images, redact PII, translate formats. Requires an Object Lambda Access Point and a Lambda function.

### Event Notifications

Trigger downstream workflows on S3 resource changes (object created, deleted, restored, replicated).

| Destination | Use Case |
|---|---|
| SNS | Fan-out to multiple consumers |
| SQS | Decouple processing pipelines |
| Lambda | Inline processing (thumbnail generation, ETL) |
| EventBridge | Advanced routing and filtering rules |

## Monitoring & Observability

| Tool | What It Provides |
|---|---|
| **CloudWatch Metrics** | Request rates, error rates, latency, storage volume |
| **CloudTrail** | API-level audit log (bucket + object operations); enable for compliance |
| **Server Access Logging** | Per-request logs written to a separate bucket; useful for security audits and cost attribution |
| **S3 Storage Lens** | 60+ metrics across the organization with interactive dashboards; identifies unused buckets, non-versioned data, unencrypted objects |
| **Storage Class Analysis** | Identifies objects that are candidates for transition to cheaper classes; feeds Lifecycle rule design |
| **S3 Inventory** | Daily/weekly CSV or Parquet reports of all objects with metadata (encryption status, replication status, size, last modified); use as input to Batch Operations |

## Patterns

### CDN Origin (Static Website)
```
Users → CloudFront → S3 (Origin Access Control)
                      Block Public Access: ON
                      Bucket policy: allow CloudFront OAC principal only
```
Never expose the bucket directly. Use **OAC** (Origin Access Control), not the legacy OAI.

### Private Data Lake (VPC-Only)
```
EC2 / ECS (private subnet)
    └── S3 Gateway Endpoint (free, added to route table)
         └── S3 bucket
              Bucket policy: deny unless aws:sourceVpce matches
```

### Cross-Account Data Sharing
Both policies must allow — one alone is insufficient:
- Producer bucket policy: allow consumer account role to `s3:GetObject`
- Consumer IAM policy: allow `s3:GetObject` on producer bucket ARN

### Versioned Bucket with Lifecycle Cleanup
```
Versioning: enabled
Lifecycle:
  Current → Standard-IA: day 30 → Glacier: day 90
  Noncurrent: expire after 30d, keep 3 max
  Incomplete multipart: abort after 7d
  Delete markers: expire when object versions gone
```

## Gotchas

- **Bucket names are global** — name squatting is real; use account-ID or org prefixes
- **ListBucket vs GetObject ARN scope** — `ListBucket` needs the bucket ARN, not `bucket/*`; forgetting this is the #1 source of 403 errors
- **Versioning cannot be fully disabled** — suspended is the minimum; plan for this when versioning is enabled
- **Lifecycle rules run daily** — new rules can take 24–48 hours to take effect; objects < 128 KB never transition
- **Early deletion charges** — Standard-IA (30d), One Zone-IA (30d), Glacier Instant (90d), Glacier Flexible (90d), Deep Archive (180d)
- **SSE-KMS + high throughput** — KMS request quota is per-region; enable S3 Bucket Keys or request quota increase proactively
- **Default encryption only covers new objects** — changing the default does not re-encrypt existing objects
- **Object Lock requires creation-time flag** — cannot be enabled on an existing bucket
- **CRR/SRR only covers new objects** — run S3 Batch Replication to cover objects created before the replication rule
- **Delete marker replication is opt-in** — must be explicitly configured; by default deletes don't replicate
- **Directory buckets: no object-level access** — bucket-level policies only; cannot grant per-object permissions
- **S3 Inventory/Storage Lens lag** — Inventory reports are daily/weekly; Storage Lens metrics have a 48h delay

## References

- [[Storage/AWS EFS]]
- [[IAM/IAM Policies]]
- [[Concepts/Least Privilege]]
