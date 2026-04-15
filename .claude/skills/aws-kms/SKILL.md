---
name: aws-kms
description: Use when working with AWS KMS - choosing between customer managed keys, AWS managed keys, and AWS owned keys, writing key policies and grants, envelope encryption, data key generation, key rotation, multi-region keys, key aliases, cross-account key usage, CloudTrail auditing of key usage, or any KMS architecture and troubleshooting decisions
---

# AWS KMS Expert Skill

Comprehensive AWS Key Management Service guidance covering key types, key policies, envelope encryption, grants, rotation, multi-region keys, and production patterns. Based on the official AWS KMS Developer Guide.

## When to Use This Skill

**Activate this skill when:**
- Choosing between customer managed, AWS managed, or AWS owned keys
- Writing or debugging key policies
- Implementing envelope encryption in application code
- Generating data keys for client-side encryption
- Setting up automatic or on-demand key rotation
- Creating multi-region keys for cross-region encryption
- Granting cross-account access to a KMS key
- Using KMS aliases in application config
- Auditing key usage via CloudTrail
- Troubleshooting `AccessDenied` or `InvalidKeyUsage` errors

**Don't use this skill for:**
- AWS Secrets Manager (secret storage) — separate service that uses KMS under the hood
- IAM policy writing in general — use aws-iam skill
- Certificate management (ACM) — separate service

---

## Key Types

### Customer Managed Keys (CMKs)

Created, owned, and managed by you. Full control: key policies, rotation schedule, tags, aliases, deletion schedule.

- Visible in your account under "Customer managed keys"
- Costs: $1/month per key + $0.03 per 10,000 API calls
- Required when you need audit trail, cross-account sharing, or custom rotation
- `KeyManager` field: `CUSTOMER`

### AWS Managed Keys

Created by AWS on your behalf when you enable encryption in a service (e.g., `aws/s3`, `aws/ebs`, `aws/rds`).

- Visible in your account but you cannot modify policies, rotate manually, or delete
- Auto-rotate annually
- Cannot be used directly in `Encrypt`/`Decrypt` API calls by your code — only the owning service can use them
- Costs: No monthly fee; per-use charges apply (often absorbed by the service)
- `KeyManager` field: `AWS`

### AWS Owned Keys

Managed entirely by AWS, shared across multiple accounts. Not visible in your account. Free. Lowest control — no CloudTrail visibility.

**Decision guide:**

| Requirement | Key Type |
|-------------|---------|
| Audit trail for every decrypt operation | Customer managed |
| Cross-account key sharing | Customer managed |
| Custom rotation period | Customer managed |
| Key deletion with waiting period | Customer managed |
| Encryption-by-default in AWS service, no compliance requirement | AWS managed or AWS owned |
| Maximum simplicity, zero cost | AWS owned |

---

## Key Policies

Every KMS key has exactly one key policy (JSON, up to 32 KB). Unlike IAM, **a key policy is required** — if it doesn't grant access, no IAM policy can override it.

### Default Key Policy

When you create a key without specifying a policy, AWS adds a default statement:

```json
{
  "Sid": "Enable IAM User Permissions",
  "Effect": "Allow",
  "Principal": { "AWS": "arn:aws:iam::ACCOUNT-ID:root" },
  "Action": "kms:*",
  "Resource": "*"
}
```

This statement means **IAM policies can grant access** — without it, IAM policies are ignored and only explicit key policy statements grant access.

> Keep the root/IAM delegation statement unless you need to fully manage key access from the key policy alone.

### Key Policy for a Specific Role

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowIAMDelegation",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::123456789012:root" },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowEncryptionByAppRole",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::123456789012:role/my-app-role" },
      "Action": ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"],
      "Resource": "*"
    },
    {
      "Sid": "AllowS3ServiceToUseKey",
      "Effect": "Allow",
      "Principal": { "Service": "s3.amazonaws.com" },
      "Action": ["kms:GenerateDataKey", "kms:Decrypt"],
      "Resource": "*"
    }
  ]
}
```

### Cross-Account Key Access

1. Add the external account/role to the **key policy** (required):
```json
{
  "Sid": "AllowCrossAccountUse",
  "Effect": "Allow",
  "Principal": { "AWS": "arn:aws:iam::ACCOUNT-B:role/consumer-role" },
  "Action": ["kms:Decrypt", "kms:DescribeKey"],
  "Resource": "*"
}
```

2. The external role's **IAM policy** must also allow the KMS actions on the key ARN:
```json
{
  "Effect": "Allow",
  "Action": ["kms:Decrypt", "kms:DescribeKey"],
  "Resource": "arn:aws:kms:us-east-1:ACCOUNT-A:key/KEY-ID"
}
```

Both must allow — key policy + IAM policy.

---

## Key Identifiers

| Identifier | Format | Use Case |
|------------|--------|---------|
| **Key ID** | `1234abcd-12ab-34cd-56ef-1234567890ab` | Unique within account+region |
| **Key ARN** | `arn:aws:kms:us-east-1:123456789012:key/1234abcd-...` | Cross-account/region references |
| **Alias name** | `alias/my-app-key` | Human-readable; use in app config |
| **Alias ARN** | `arn:aws:kms:us-east-1:123456789012:alias/my-app-key` | Cross-account alias references |

**Always use aliases in application code** — never hardcode key IDs or ARNs. An alias can be updated to point to a new key without changing application configuration.

```bash
aws kms create-alias \
  --alias-name alias/my-app-encryption-key \
  --target-key-id 1234abcd-12ab-34cd-56ef-1234567890ab
```

---

## Envelope Encryption

KMS keys encrypt **data keys**, which encrypt your data. Your data never passes through KMS — only short data keys do.

```
Generate data key:
  KMS → returns {PlaintextDataKey, EncryptedDataKey}

Encrypt data locally:
  PlaintextDataKey + your data → EncryptedData
  Discard PlaintextDataKey from memory immediately

Store:
  EncryptedData + EncryptedDataKey (store together, e.g., in S3 or DB)

Decrypt:
  EncryptedDataKey → KMS → PlaintextDataKey
  PlaintextDataKey + EncryptedData → PlainData
```

### Generate Data Key

```python
import boto3
import os
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

kms = boto3.client('kms')

# Generate a 256-bit data key
response = kms.generate_data_key(
    KeyId='alias/my-app-encryption-key',
    KeySpec='AES_256'
)

plaintext_key = response['Plaintext']       # Use for encryption, then discard
encrypted_key = response['CiphertextBlob']  # Store alongside ciphertext

# Encrypt data
nonce = os.urandom(12)
aesgcm = AESGCM(plaintext_key)
ciphertext = aesgcm.encrypt(nonce, data, None)

# Wipe plaintext key from memory
plaintext_key = None

# Store: ciphertext + nonce + encrypted_key
```

### Decrypt Data Key

```python
response = kms.decrypt(CiphertextBlob=encrypted_key)
plaintext_key = response['Plaintext']
# Decrypt data using plaintext_key, then discard
```

### Data Key Caching

For high-throughput encryption, cache plaintext data keys in memory (with an expiry) rather than calling `GenerateDataKey` for every operation. AWS Encryption SDK provides built-in data key caching.

---

## Grants

Grants are a lightweight alternative to key policies for delegating temporary, narrowly-scoped access.

```bash
aws kms create-grant \
  --key-id alias/my-app-key \
  --grantee-principal arn:aws:iam::123456789012:role/lambda-function-role \
  --operations Decrypt GenerateDataKey \
  --name "lambda-data-access-grant"
```

Grants are useful when:
- Granting access that expires or can be revoked independently
- AWS services (like EBS or SSM) need to use your key on your behalf
- Delegating access without modifying the key policy

Revoke a grant:
```bash
aws kms revoke-grant --key-id KEY-ID --grant-id GRANT-ID
```

---

## Key Rotation

### Automatic Rotation (Recommended)

Rotates the underlying cryptographic material annually. Old backing keys are preserved to decrypt data encrypted with them — rotation is transparent.

```bash
aws kms enable-key-rotation --key-id alias/my-app-key

# Check status
aws kms get-key-rotation-status --key-id alias/my-app-key
```

- Customer managed keys: optional (enable it)
- AWS managed keys: automatic, cannot be disabled
- AWS owned keys: varies by service
- Rotation does NOT change the key ID, ARN, or alias — no application changes required

### On-Demand Rotation

```bash
aws kms rotate-key-on-demand --key-id alias/my-app-key
```

Useful to rotate after a suspected key material exposure without waiting for the annual schedule.

### Key Material Import

If you need to supply your own key material (BYOK — compliance or HSM requirements):
1. Create a key with no key material (`Origin: EXTERNAL`)
2. Download a public key from KMS
3. Encrypt your key material with the public key
4. Import encrypted key material with an expiry date

Imported key material does **not** support automatic rotation — you must re-import new material manually.

---

## Multi-Region Keys

Multi-region keys are a set of related keys in different AWS regions with the same key material. Encrypt in one region, decrypt in another — without re-encrypting.

```bash
# Create primary key in us-east-1
aws kms create-key --multi-region --region us-east-1

# Replicate to eu-west-1
aws kms replicate-key \
  --key-id arn:aws:kms:us-east-1:123456789012:key/mrk-... \
  --replica-region eu-west-1
```

Key IDs start with `mrk-`. Primary and replicas have different ARNs but the same key material.

**Use cases:**
- Encrypt data in us-east-1, replicate to eu-west-1, decrypt in eu-west-1 (DR scenario)
- Global databases or cross-region S3 replication with SSE-KMS
- Multi-region active-active applications with a single encryption key

**Rotation:** Rotating the primary rotates all replicas simultaneously.

---

## KMS and AWS Services

Most AWS services support SSE-KMS encryption using your customer managed key:

```bash
# S3 bucket with SSE-KMS
aws s3api create-bucket --bucket my-bucket
aws s3api put-bucket-encryption --bucket my-bucket \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {
      "SSEAlgorithm": "aws:kms",
      "KMSMasterKeyID": "alias/my-s3-key"
    }, "BucketKeyEnabled": true}]
  }'
```

**S3 Bucket Keys:** Enable `BucketKeyEnabled: true` to reduce KMS API calls by up to 99%. Instead of calling KMS for every object, S3 gets a bucket-level data key and uses it locally. Significant cost savings for high-object-count buckets.

```bash
# EBS encryption
aws ec2 create-volume \
  --encrypted \
  --kms-key-id alias/my-ebs-key \
  --availability-zone us-east-1a \
  --size 100

# RDS encryption (at creation, cannot be changed after)
aws rds create-db-instance \
  --db-instance-identifier my-db \
  --storage-encrypted \
  --kms-key-id alias/my-rds-key \
  ...
```

Key policies for service integrations must include the service principal or grant conditions for the service to use the key.

---

## CloudTrail Auditing

Every KMS API call is logged in CloudTrail. This is the primary audit mechanism for key usage.

Key events to monitor:
- `Decrypt` — who decrypted data and when
- `GenerateDataKey` — who generated data keys (indicates data encryption activity)
- `DisableKey` / `ScheduleKeyDeletion` — potentially destructive operations
- `CreateGrant` / `RevokeGrant` — access delegation changes
- `PutKeyPolicy` — key policy changes

Set up CloudWatch alarms on CloudTrail for sensitive events:
```
Metric filter: eventSource = kms.amazonaws.com AND eventName = ScheduleKeyDeletion
Alarm: count > 0 → SNS → immediate alert
```

---

## Architecture Patterns

### Per-Service Key Isolation

```
One CMK per service per environment:
  alias/myapp-api-prod-key     → API service encryption
  alias/myapp-db-prod-key      → RDS/Aurora encryption
  alias/myapp-s3-prod-key      → S3 bucket encryption
  alias/myapp-secrets-prod-key → Secrets Manager encryption

Benefits:
  - Blast radius limited (compromised key affects one service)
  - Separate CloudTrail audit trail per service
  - Independent rotation schedules
```

### Application-Level Encryption (Envelope)

```
DynamoDB table: stores encrypted PII fields
  Application:
    1. generate_data_key(alias/myapp-prod-key) → {plaintext, encrypted}
    2. Encrypt PII fields with AES-256-GCM using plaintext key
    3. Store: { encrypted_fields, encrypted_data_key, nonce } in DynamoDB
    4. Wipe plaintext key

  Decrypt:
    1. Read { encrypted_fields, encrypted_data_key, nonce } from DynamoDB
    2. decrypt(encrypted_data_key) → plaintext key
    3. AES-256-GCM decrypt → PII fields
```

### Cross-Account Secrets Sharing

```
Account A (secrets owner):
  KMS key policy: allow Account B role to Decrypt + DescribeKey
  Secrets Manager secret: encrypted with Account A CMK

Account B (consumer):
  IAM role: allow kms:Decrypt on Account A key ARN
           allow secretsmanager:GetSecretValue on Account A secret ARN
  
  # Works because KMS supports cross-account via key policy
```

---

## Security Best Practices

1. **One key per service per environment** — limits blast radius; simplifies audit trail; enables independent rotation
2. **Always enable automatic rotation** — no reason not to for customer managed keys; protects against long-term key exposure
3. **Require KMS condition in bucket/EBS policies** — prevent unencrypted uploads:
   ```json
   "Condition": { "StringNotEquals": { "s3:x-amz-server-side-encryption": "aws:kms" } }
   ```
4. **Enable S3 Bucket Keys** — reduces KMS costs by ~99% for high-volume S3 buckets
5. **Never use key IDs in application code** — use aliases; decouples key rotation from deployments
6. **Set deletion waiting period to 30 days** — default 30-day waiting period before a scheduled key deletion takes effect; gives time to cancel if accidental
7. **Monitor `ScheduleKeyDeletion` in CloudTrail** — alert immediately; key deletion is irreversible after waiting period
8. **Use grants for temporary access** — grants are easier to revoke than key policy changes; ideal for batch jobs or cross-service access

---

## Common Troubleshooting

| Symptom | Likely Cause |
|---------|-------------|
| `AccessDeniedException` on Encrypt/Decrypt | Key policy doesn't allow the principal; or key policy allows but IAM policy doesn't (both required for cross-account); or key is disabled/pending deletion |
| `DisabledException` | Key is disabled — run `enable-key` to re-enable; or scheduled for deletion |
| `InvalidKeyUsageException` | Wrong key spec for the operation (e.g., using a sign/verify key for encrypt/decrypt) |
| `KMSInvalidStateException` | Key is pending import, pending deletion, or is a replica that hasn't synchronized |
| High KMS costs on S3 | S3 Bucket Keys not enabled — enable `BucketKeyEnabled: true` in bucket encryption config |
| Cross-account `AccessDenied` | Key policy allows the cross-account principal but the consuming account's IAM policy doesn't grant `kms:Decrypt` on the key ARN — both sides required |
| `NotFoundException` on alias | Alias doesn't exist in the region; or typo (`alias/` prefix required) |
| Encrypted EBS volume inaccessible after account move | Key is region and account specific; data is inaccessible if the key is deleted or account access is revoked |
