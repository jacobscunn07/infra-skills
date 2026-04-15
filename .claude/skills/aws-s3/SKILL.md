---
name: aws-s3
description: Use when working with Amazon S3 - designing bucket architecture, choosing storage classes, configuring access control (bucket policies, IAM, access points), encryption (SSE-S3, SSE-KMS), lifecycle rules, replication (CRR/SRR), versioning, object lock, event notifications, performance optimization, or any S3 architecture and troubleshooting decisions
---

# AWS S3 Expert Skill

Comprehensive Amazon S3 guidance covering storage architecture, access control, encryption, lifecycle management, replication, and production patterns. Based on the official AWS S3 User Guide.

## When to Use This Skill

**Activate this skill when:**
- Designing bucket architecture and naming strategy
- Choosing storage classes for cost optimization
- Configuring access control (bucket policies, IAM, ACLs, access points)
- Setting up encryption at rest (SSE-S3, SSE-KMS, DSSE-KMS)
- Creating lifecycle rules for tiering or expiration
- Setting up cross-region or same-region replication
- Enabling versioning or object lock (WORM)
- Configuring event notifications (Lambda, SQS, SNS)
- Optimizing S3 performance (prefix design, multipart upload, Transfer Acceleration)
- Troubleshooting 403 access denied errors or replication failures

**Don't use this skill for:**
- EFS or EBS (block/file storage, not object storage)
- S3-compatible storage outside of AWS
- Application-level file handling unrelated to S3 configuration

---

## Core Concepts

### Bucket Types

| Type | Use Case | Key Trait |
|------|----------|-----------|
| **General Purpose** | Most workloads | Multi-AZ, global namespace, all storage classes |
| **Directory** | Low-latency, high-throughput | Hierarchical structure, single-AZ, S3 Express One Zone |
| **Table** | Analytics / ML tabular data | Apache Iceberg format, queryable via Athena/Redshift |
| **Vector** | AI embeddings, similarity search | Vector indexes, integrates with Bedrock/OpenSearch |

General purpose buckets are the right choice for almost all workloads.

### Objects and Keys

- An **object** = data + metadata, identified by a **key** (the full path-like name)
- Key example: `logs/2024/01/app.log` in bucket `my-company-logs`
- No true directory hierarchy — the `/` in keys is a naming convention
- Max object size: **5 TB**; objects over 100 MB should use multipart upload

### Consistency Model

S3 provides **strong read-after-write consistency** for all operations:
- PUT a new object → immediately visible in GET and LIST
- Overwrite or DELETE an object → immediately reflects new state
- Applies to: objects, ACLs, tags, metadata, S3 Select

**Exception:** bucket-level operations (create, delete, versioning changes) are eventually consistent and may take ~15 minutes to propagate.

**Concurrent writes:** S3 uses last-writer-wins semantics — no locking for simultaneous writes to the same key. Implement application-level locking if needed.

---

## Storage Classes

Choose based on access frequency, retrieval tolerance, and retention duration.

| Storage Class | Access Pattern | Availability | Min Duration | Retrieval |
|---------------|---------------|--------------|--------------|-----------|
| **S3 Standard** | Frequent | 99.99% (multi-AZ) | None | Immediate |
| **S3 Express One Zone** | High-perf, frequent | High (single-AZ) | None | Single-digit ms |
| **S3 Intelligent-Tiering** | Unknown/changing | 99.9%–99.99% | None | Varies by tier |
| **S3 Standard-IA** | Infrequent | 99.9% (multi-AZ) | 30 days | Immediate |
| **S3 One Zone-IA** | Infrequent, non-critical | 99.5% (single-AZ) | 30 days | Immediate |
| **S3 Glacier Instant Retrieval** | Archive, quarterly access | 99.9% (multi-AZ) | 90 days | Immediate |
| **S3 Glacier Flexible Retrieval** | Archive, hours acceptable | 99.99% (multi-AZ) | 90 days | Minutes–hours |
| **S3 Glacier Deep Archive** | Long-term archive | 99.99% (multi-AZ) | 180 days | Up to 12 hours |

**Decision guide:**
- Default to **Standard** for new workloads
- Use **Intelligent-Tiering** when access patterns are unknown — it auto-moves objects across tiers with no retrieval fee
- Use **Standard-IA** for backups, disaster recovery data accessed monthly or less
- Use **Glacier Instant Retrieval** for archives accessed a few times per year with instant retrieval requirement
- Use **Glacier Deep Archive** for compliance data held for 7–10 years
- Avoid **One Zone-IA** for any data that can't be recreated if an AZ fails

**Minimum storage duration charges:** If you delete, overwrite, or transition an object before its minimum duration, you're charged for the full minimum period. Account for this in lifecycle rules.

---

## Access Control

S3 offers multiple overlapping access control mechanisms. Use the right tool for each situation.

### Block Public Access (Always On by Default)

All buckets created after April 2023 have Block Public Access enabled by default. **Leave it on** unless you are intentionally hosting a public static website.

Four independent settings — the safest configuration blocks all four:
```
BlockPublicAcls:       true
IgnorePublicAcls:      true
BlockPublicPolicy:     true
RestrictPublicBuckets: true
```

### Bucket Policies (Resource-Based)

JSON policy attached to the bucket. Best for:
- Cross-account access
- Enforcing encryption requirements
- Restricting access to specific VPC endpoints

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::123456789012:role/my-app-role" },
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::my-bucket/*"
    }
  ]
}
```

**Limits:** 20 KB max policy size. Use S3 Access Grants or Access Points if you exceed this.

**Common enforcement patterns:**

Deny non-HTTPS requests:
```json
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"],
  "Condition": { "Bool": { "aws:SecureTransport": "false" } }
}
```

Restrict to VPC endpoint only:
```json
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"],
  "Condition": { "StringNotEquals": { "aws:sourceVpce": "vpce-xxxxxxxx" } }
}
```

### IAM Policies (Identity-Based)

Attached to IAM users, roles, or groups. Best for:
- Same-account access management
- Managing permissions alongside other AWS services
- Cannot grant cross-account access on their own (needs bucket policy too for cross-account)

Minimum permissions for a service reading from S3:
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

Note: `s3:ListBucket` applies to the bucket ARN; `s3:GetObject`/`PutObject`/`DeleteObject` apply to `bucket/*`.

### S3 Access Points

Named endpoints with their own policies, useful for shared datasets accessed by many different teams or applications. Each access point can restrict to a specific VPC or prefix.

- Up to 10,000 access points per bucket
- Each has its own hostname: `my-ap-123456789012.s3-accesspoint.us-east-1.amazonaws.com`
- Access point policy + bucket policy both evaluated; both must allow

### ACLs

Disabled by default (Bucket owner enforced mode). **Keep them disabled** — bucket policies and IAM are more flexible and auditable.

The only legitimate modern use case: granting S3 log delivery service permissions to write access logs.

### Access Control Decision Matrix

| Scenario | Recommended Tool |
|----------|-----------------|
| Same-account access | IAM policy |
| Cross-account access | Bucket policy + IAM policy |
| Shared dataset, many consumers | S3 Access Points |
| VPC-only access | Bucket policy with `aws:sourceVpce` condition |
| Public static website | Bucket policy (not ACLs) |
| Granular audit trail per end-user | S3 Access Grants |
| S3 server access logs delivery | Bucket ACL (only valid modern use) |

---

## Encryption

All objects uploaded after January 2023 are encrypted by default at no cost. You control which encryption type is used.

| Option | Key Management | Audit Trail | Use When |
|--------|---------------|-------------|----------|
| **SSE-S3** | AWS manages entirely | None | Default; no compliance requirements |
| **SSE-KMS** | AWS KMS (you control keys) | CloudTrail | Compliance, key rotation control, cross-account |
| **DSSE-KMS** | AWS KMS, two layers | CloudTrail | Strict compliance requiring dual-layer encryption |
| **SSE-C** | You provide key per request | None | Full key control; you manage key storage |

**SSE-S3** is the default and sufficient for most workloads.

**SSE-KMS** is required when you need to:
- Audit who decrypted which object (CloudTrail records every KMS API call)
- Control key rotation and key policies
- Share encrypted objects across accounts
- Meet compliance frameworks that require customer-managed keys (CMK)

**SSE-KMS gotcha:** KMS API calls count against KMS request quotas. High-throughput workloads (thousands of requests/second) may hit KMS limits — request a quota increase proactively.

**Changing encryption on existing objects:** Changing the bucket's default encryption does not re-encrypt existing objects. Use S3 Batch Operations with a Copy action to re-encrypt at scale.

---

## Versioning

Versioning preserves every version of every object. Once enabled, it cannot be disabled — only suspended.

- Protects against accidental overwrites and deletes
- Delete markers: deleting a versioned object adds a delete marker; prior versions are retained
- Storage costs accumulate for all versions — pair with lifecycle rules to expire old versions
- Required prerequisite for: Object Lock, Cross-Region Replication

**Lifecycle rule to expire old versions:**
```
Expire noncurrent versions after: 90 days
Keep at most: 3 noncurrent versions
Delete expired object delete markers: true
```

---

## Object Lock (WORM)

Prevents objects from being deleted or overwritten for a fixed period or indefinitely.

- Must be enabled at bucket creation time (cannot enable on existing bucket)
- Requires versioning
- Two retention modes:

| Mode | Who Can Override | Use Case |
|------|-----------------|----------|
| **Compliance** | Nobody (not even root) | Regulatory WORM (SEC 17a-4, FINRA) |
| **Governance** | Users with `s3:BypassGovernanceRetention` | Internal WORM with escape hatch |

**Legal hold:** separate from retention period — prevents deletion regardless of retention, lifted explicitly.

---

## Lifecycle Rules

Lifecycle rules automate transitioning objects to cheaper storage classes or deleting them.

### Transition Constraints

Objects must spend a minimum time in a class before transitioning:
- **Standard → Standard-IA or One Zone-IA:** minimum 30 days in Standard
- **Standard-IA → Glacier:** minimum 30 days in Standard-IA
- Objects smaller than 128 KB are never transitioned (not cost-effective)

### Common Lifecycle Patterns

**Log retention (90 days, then delete):**
```
Prefix: logs/
Transition to Standard-IA: after 30 days
Expire objects: after 90 days
```

**Data lake archiving:**
```
Prefix: data/
Transition to Standard-IA: after 30 days
Transition to Glacier Flexible Retrieval: after 90 days
Transition to Glacier Deep Archive: after 365 days
```

**Versioned bucket cleanup:**
```
Expire noncurrent versions: after 30 days
Max noncurrent versions: 3
Delete expired delete markers: true
Abort incomplete multipart uploads: after 7 days
```

> Always add a rule to abort incomplete multipart uploads — orphaned parts incur storage charges indefinitely.

---

## Replication

Replication copies objects asynchronously to one or more destination buckets. Only new objects are replicated by live replication; use S3 Batch Replication for existing objects.

### CRR vs SRR

| | Cross-Region Replication (CRR) | Same-Region Replication (SRR) |
|---|---|---|
| **Scope** | Different AWS Regions | Same AWS Region |
| **Use cases** | DR, latency reduction, compliance | Log aggregation, prod→test sync, data sovereignty |
| **Latency** | Higher (cross-region) | Lower |
| **Cost** | Data transfer + replication charges | Replication charges, no transfer fee |

### Requirements
- Versioning must be enabled on both source and destination buckets
- IAM role with permissions to read source and write to destination
- Buckets can be in same or different AWS accounts

### Replication Time Control (S3 RTC)

Optional SLA-backed guarantee: 99.99% of objects replicated within 15 minutes. Adds cost. Use when downstream systems depend on predictable replication lag.

### What Gets Replicated
- Object data, metadata, version ID, ACLs, tags, object lock settings
- Delete markers (optional — configure explicitly)
- **Not replicated by default:** deletes by version ID (to protect against malicious deletes)

### Batch Replication

For objects that existed before replication was configured, or to retry failed replications:
```bash
aws s3control create-job \
  --operation '{"S3ReplicateObject":{}}' \
  --manifest-generator ...
```

---

## Performance

### Request Rate Limits

S3 scales automatically, but rate limits apply **per prefix**:
- **3,500 PUT/COPY/POST/DELETE requests/second** per prefix
- **5,500 GET/HEAD requests/second** per prefix

Scale by distributing objects across multiple prefixes:
```
# 10 prefixes → 55,000 GET/s aggregate throughput
images/a/...
images/b/...
images/c/...
```

> Avoid date-based prefixes (e.g., `2024/01/`) when high throughput is needed — sequential prefixes concentrate load on the same partition.

### Multipart Upload

Use for objects **over 100 MB**; required for objects over 5 GB.

Benefits: parallel uploads, resume on failure, begin upload before final size is known.

```bash
# AWS CLI handles multipart automatically
aws s3 cp large-file.zip s3://my-bucket/ --storage-class STANDARD_IA
```

Minimum part size: 5 MB (except last part). Max 10,000 parts.

### Byte-Range Fetches

Download specific byte ranges in parallel to reconstruct large objects faster:
```
GET /my-object HTTP/1.1
Range: bytes=0-1048575
```
Useful for: partial reads, parallel downloads, resuming interrupted downloads.

### S3 Transfer Acceleration

Routes uploads through CloudFront edge locations to the bucket's region over AWS's optimized backbone. Useful when uploading from geographically distant clients. Adds per-GB cost.

### S3 Express One Zone

Directory buckets with single-digit millisecond latency. Use for:
- Machine learning training data (high-throughput, low-latency reads)
- Real-time analytics
- High-frequency read/write workloads

---

## Event Notifications

Trigger downstream processing when objects are created, deleted, or restored.

**Destinations:**
- Amazon SNS topic
- Amazon SQS queue
- AWS Lambda function
- Amazon EventBridge (supports filtering, routing to 18+ targets)

**Supported event types:** `s3:ObjectCreated:*`, `s3:ObjectRemoved:*`, `s3:ObjectRestore:*`, `s3:Replication:*`, `s3:LifecycleTransition`, etc.

**EventBridge is preferred** — it supports advanced filtering, multiple destinations, and routing rules without adding separate notification configs per destination.

---

## Architecture Patterns

### Static Website / CDN Origin
```
Users → CloudFront → S3 (Origin Access Control)
                      Block Public Access: ON
                      Bucket policy: allow CloudFront OAC principal only
```
Never expose the bucket directly — always put CloudFront in front. Use Origin Access Control (OAC), not the legacy Origin Access Identity (OAI).

### Private Data Lake (VPC-Only Access)
```
EC2 / ECS (private subnet)
    │
    └── S3 Gateway Endpoint (free, in route table)
         └── S3 bucket (Block Public Access: ON)
              Bucket policy: deny unless aws:sourceVpce matches
```

### Cross-Account Data Sharing
```
Account A (producer):
  Bucket policy: allow Account B role to s3:GetObject

Account B (consumer):
  IAM role: allow s3:GetObject on Account A bucket ARN
```
Both the bucket policy and the IAM policy must allow the action.

### Versioned Bucket with Lifecycle Cleanup
```
Bucket: versioning enabled
Lifecycle rules:
  - Transition current versions → Standard-IA after 30d → Glacier after 90d
  - Expire noncurrent versions after 30d, keep 3 max
  - Abort incomplete multipart uploads after 7d
  - Delete expired delete markers
```

---

## Security Best Practices

1. **Block Public Access on by default** — never disable without explicit intent
2. **Enforce HTTPS** — deny `aws:SecureTransport: false` in bucket policy
3. **Use SSE-KMS for sensitive data** — gives CloudTrail audit trail on every decryption
4. **Prefer IAM + bucket policies over ACLs** — keep Object Ownership at "Bucket owner enforced"
5. **Enable versioning on critical buckets** — protects against accidental deletes
6. **Enable Object Lock for compliance data** — Compliance mode for regulatory WORM requirements
7. **Use VPC Gateway Endpoint for S3** — keeps S3 traffic off the internet, free to add
8. **Restrict cross-account access to specific roles** — never use `"Principal": "*"` in allow statements
9. **Enable S3 server access logging or CloudTrail data events** — for audit trails on object access
10. **Set lifecycle rules to abort incomplete multipart uploads** — prevents unbounded storage charges

---

## Common Troubleshooting

| Symptom | Likely Cause |
|---------|-------------|
| `403 Access Denied` | IAM policy missing `s3:ListBucket` (bucket ARN) or `s3:GetObject` (object ARN); or bucket policy denies the principal; or Block Public Access blocking a public policy |
| `403` on cross-account access | Both IAM policy (on consumer role) and bucket policy (on producer bucket) must allow — one alone is not sufficient |
| Object appears deleted but versions exist | Delete marker added; list with `--include-all-versions` to see versions |
| Replication not working | Versioning not enabled on both buckets; IAM replication role missing permissions; check replication rule scope/filter |
| Lifecycle rules not triggering | Rules run once daily; new rules can take 24–48 hours; objects smaller than 128 KB never transition |
| High KMS costs with SSE-KMS | Every GET/PUT calls KMS; use S3 Bucket Keys to reduce KMS API calls by up to 99% |
| Slow upload of large files | Use multipart upload; enable Transfer Acceleration for distant clients |
| `503 Slow Down` errors | Hot prefix — distribute objects across multiple prefixes |
