---
title: AWS KMS
tags: [kms, encryption, security, key-management, iam, envelope-encryption, multi-region]
related: ["[[IAM/AWS IAM]]", "[[Storage/AWS S3]]", "[[Storage/AWS EFS]]", "[[Compute/AWS EC2]]", "[[Observability/AWS CloudWatch]]", "[[Database/AWS RDS]]"]
created: 2026-04-28
updated: 2026-04-28
---

## Overview

AWS Key Management Service (KMS) is a managed service for creating and controlling cryptographic keys used to protect data. KMS keys are backed by FIPS 140-3 Security Level 3 validated HSMs and are **never exported in plaintext outside the service**. All key creation, management, and cryptographic operations occur within KMS — your data keys are returned over TLS and never stored by KMS.

---

## Key Concepts

### Key Ownership and Management

| Key Type | Created By | Control | Visibility | Monthly Fee | Per-Use Fee | Quota |
|---|---|---|---|---|---|---|
| **Customer Managed** | Customer | Full | Full | Yes | Yes | Yes |
| **AWS Managed** | AWS service (on your behalf) | None | View policy only | No | Sometimes | No (but counts for request quota) |
| **AWS Owned** | AWS (in AWS account) | None | Not visible | No | No | No |

- AWS managed keys use the `aws/<service>` alias format (e.g., `aws/ebs`, `aws/s3`).
- AWS managed keys rotate automatically every ~365 days; this changed from a 3-year period in May 2022.
- AWS owned key usage is **not visible in CloudTrail** — choose customer managed keys when you need auditability.
- New AWS services no longer create AWS managed keys (deprecated after 2021); prefer customer managed.

### Key Identifiers

```
# Single-region Key ARN
arn:aws:kms:us-east-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab

# Multi-region Key ARN (mrk- prefix)
arn:aws:kms:us-east-1:111122223333:key/mrk-1234abcd12ab34cd56ef1234567890ab

# Alias ARN
arn:aws:kms:us-east-1:111122223333:alias/my-app-key

# Alias name (usable in most API calls)
alias/my-app-key
```

Aliases can be updated to point to a different key — useful for key rotation without updating application config.

### Key Material and Internal Hierarchy

- **HSM Backing Key (HBK)** — 256-bit symmetric or RSA/EC private key; lives on HSM, never exported plaintext. Multiple HBK versions exist after rotation; only the current version encrypts new data, older versions remain available for decryption.
- **Domain Key** — 256-bit AES-GCM key in HSM memory; wraps HBKs; rotated daily.
- **Derived Encryption Key** — 256-bit AES-GCM key; derived per-operation from the HBK; ephemeral.
- **Customer Data Key (CDK)** — generated on request; returned encrypted (ciphertext) and/or plaintext over TLS; never stored in KMS.

### Key Specs (Cryptographic Type)

| Key Spec | Usage | Common Services |
|---|---|---|
| `SYMMETRIC_DEFAULT` (AES-256-GCM) | Symmetric encryption/decryption | S3, EBS, RDS, most services |
| `RSA_2048 / RSA_3072 / RSA_4096` | Asymmetric encrypt/decrypt or sign/verify | TLS, document signing |
| `ECC_NIST_P256 / P384 / P521` | Sign/verify only | Code signing, JWTs |
| `HMAC_224 / 256 / 384 / 512` | MAC generation and verification | API signing, integrity checks |

---

## Envelope Encryption

Envelope encryption is the standard pattern for protecting data at scale using KMS:

```
1. Call GenerateDataKey(KeyId=kms-key-id)
   → Returns: { Plaintext: <data-key>, CiphertextBlob: <encrypted-data-key> }

2. Encrypt your data locally with the plaintext data key (AES-256-GCM)

3. Store: { encrypted_data, CiphertextBlob (encrypted data key) }
   Discard the plaintext data key from memory

4. To decrypt:
   Call Decrypt(CiphertextBlob=<encrypted-data-key>)
   → Returns plaintext data key
   Decrypt data locally
```

`GenerateDataKeyWithoutPlaintext` is used when you want to generate and store an encrypted data key *now* but decrypt later — the plaintext key never enters your application memory.

**Why envelope encryption?**
- KMS can only encrypt objects ≤ 4 KB directly; data is always larger than that.
- Reduces KMS API calls — one call generates a data key that encrypts gigabytes locally.
- Ciphertext is portable; you can move encrypted data anywhere; decryption still requires KMS access.

---

## Key Policies

Key policies are **resource-based policies** attached directly to a KMS key. Unlike IAM, a KMS key with no key policy statement allowing IAM delegation cannot be managed via IAM policies alone.

### Default Key Policy Pattern

```json
{
  "Id": "key-consolepolicy",
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnableIAMUserPermissions",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::111122223333:root" },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowKeyAdministrators",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::111122223333:role/KeyAdminRole" },
      "Action": ["kms:Create*", "kms:Describe*", "kms:Enable*", "kms:Disable*",
                 "kms:Delete*", "kms:PutKeyPolicy", "kms:UpdateAlias"],
      "Resource": "*"
    },
    {
      "Sid": "AllowKeyUse",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::111122223333:role/AppRole" },
      "Action": ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"],
      "Resource": "*"
    }
  ]
}
```

The `arn:aws:iam::ACCOUNT:root` statement does **not** grant the AWS root user access — it enables the account to use IAM policies to delegate KMS permissions. Without it, you cannot manage the key via IAM.

### Policy Constraints

- Max size: 32 KB (32,768 bytes)
- `Resource` must always be `"*"` (means "this key")
- IAM user groups are not valid principals; use IAM roles
- Explicit `Deny` overrides all allows

### Key Condition Keys

| Condition Key | Purpose |
|---|---|
| `kms:CallerAccount` | Restrict by AWS account ID |
| `kms:ViaService` | Only allow use when called by a specific AWS service (e.g., `s3.amazonaws.com`) |
| `kms:EncryptionContext:key` | Restrict by encryption context value |
| `kms:KeySpec` | Restrict by key spec |
| `kms:GrantIsForAWSResource` | Restrict grants to AWS resource operations only |

### Cross-Account Access (Two-Policy Requirement)

Cross-account KMS usage requires both policies:

1. **Key policy** (key owner account) — grants the external principal the desired actions.
2. **IAM policy** (external account) — grants the role/user access to the specific key ARN.

Missing either policy = access denied.

### Grants

Grants are fine-grained, programmatic access controls that can be created and revoked without modifying the key policy. Commonly used by AWS services operating on your behalf (e.g., EBS encrypting volumes).

```json
{
  "Sid": "AllowGrantCreation",
  "Effect": "Allow",
  "Principal": { "AWS": "arn:aws:iam::111122223333:role/AppRole" },
  "Action": ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"],
  "Resource": "*",
  "Condition": {
    "Bool": { "kms:GrantIsForAWSResource": "true" }
  }
}
```

---

## Key Rotation

### Automatic Rotation

- Supported for **symmetric customer managed keys** with `AWS_KMS` origin only.
- Default period: 365 days; customizable via `RotationPeriodInDays`.
- **What changes:** The HBK (key material). **What doesn't change:** Key ID, ARN, aliases, policies.
- Old key material is retained — existing ciphertexts decrypt transparently without application changes.
- Rotation billing: monthly fee charged for first and second rotation only; subsequent rotations are free.

### On-Demand Rotation

- Triggers immediate rotation outside the scheduled cycle.
- Does not affect the automatic rotation schedule.
- Also supported for symmetric keys with `EXTERNAL` origin (imported material).

### Manual Rotation (Required For)

- Asymmetric keys
- HMAC keys
- Custom key store keys

Manual rotation means creating a new key and updating aliases/application config to point to the new key.

### Not Supported

- Asymmetric keys
- HMAC keys
- Keys in custom key stores
- Keys with imported material (for automatic rotation; on-demand is supported)

---

## Multi-Region Keys

Multi-region keys share the same key material and key ID across AWS Regions, enabling encrypt-in-one-region / decrypt-in-another without cross-region API calls.

### Primary vs Replica

- **Primary key**: The original; can be replicated. Only one per key set per region.
- **Replica key**: Created in another region; same key ID and material. Fully independent key resource.

### Properties: Synced vs Independent

| Synced (automatic) | Independent (manage per region) |
|---|---|
| Key ID, key material, key spec | Key policy |
| Key usage, algorithms | Grants |
| Automatic rotation settings | Aliases, tags |
| On-demand rotation status | Description, enabled/disabled status |

### Key ARN Format

Multi-region keys use `mrk-` prefix:
```
arn:aws:kms:us-east-1:111122223333:key/mrk-1234abcd12ab34cd56ef1234567890ab
```

### Limitations

- Cannot convert a single-region key to multi-region or vice versa — migration requires creating new keys and re-encrypting data.
- Primary key cannot be deleted until **all replica keys are deleted first**.
- Cannot replicate across AWS partitions (commercial ↔ China ↔ GovCloud).
- Most AWS services (e.g., S3 cross-region replication) treat multi-region keys as single-region — they decrypt and re-encrypt rather than using the related replica. Check service-specific docs.
- AWS managed keys are always single-region.

### Use Cases

- Disaster recovery — decrypt backups in a failover region without cross-region KMS calls.
- Active-active multi-region applications.
- Distributed signing — consistent signatures across regions.

---

## Key Deletion

Deletion is **irreversible** and makes all data encrypted under the key permanently unrecoverable.

### Waiting Period

- Range: 7–30 days (default 30 days); may be up to 24 hours longer than the scheduled date.
- During the waiting period the key is in `Pending deletion` status and **cannot be used for any cryptographic operation**.
- Deletion can be canceled anytime before the period expires.

### Deletion vs Disable

Prefer **disabling** a key over deleting it when uncertain. A disabled key can be re-enabled; a deleted key cannot be recovered.

### Gotchas

- **Asymmetric keys**: Public keys downloaded before deletion remain usable outside KMS — users can continue to encrypt with the public key, but resulting ciphertexts **cannot be decrypted** once the private key is deleted.
- **Multi-region keys**: Delete all replica keys first; primary key's waiting period starts when the last replica is deleted.
- **CloudHSM / External Key Store keys**: KMS makes best-effort deletion from HSM clusters, but backups of the cluster may retain deleted material.
- **Keys with imported material**: Deleting the KMS key is irreversible (for symmetric keys); deleting only the imported material is reversible via reimport.

---

## VPC Endpoints

AWS KMS supports Interface VPC endpoints via AWS PrivateLink, keeping KMS traffic off the public internet.

- One or more ENIs with private IPs in your VPC subnets handle traffic.
- Supports all AWS KMS API operations.
- Supports both standard and FIPS endpoints.
- Private DNS available — applications use the standard `kms.<region>.amazonaws.com` endpoint without code changes.
- Endpoint policies can restrict which keys and operations are allowed through the endpoint.

**Enforce VPC-only access** using a key policy condition:

```json
{
  "Condition": {
    "StringEquals": {
      "aws:SourceVpce": "vpce-1234abcdf5678c90a"
    }
  }
}
```

---

## CloudTrail Auditing

CloudTrail captures **all** AWS KMS API calls automatically:

- Read operations: `ListAliases`, `DescribeKey`, `GetKeyRotationStatus`
- Management operations: `CreateKey`, `PutKeyPolicy`, `UpdateAlias`, `ScheduleKeyDeletion`
- Cryptographic operations: `Encrypt`, `Decrypt`, `GenerateDataKey`, `Sign`, `Verify`
- Internal KMS operations: `RotateKey`, `SynchronizeMultiRegionKey`

### Logged In Both Accounts

Cross-account KMS operations are logged in both the caller's CloudTrail and the key owner's CloudTrail.

### What Is NOT Logged

- AWS owned key usage (no customer CloudTrail visibility).
- Sensitive field values: `Plaintext` parameter in Encrypt calls, decrypted payloads, key policy content from `GetKeyPolicy`.

### Key Event to Monitor

Since December 2022, AWS KMS adds the key ARN to `responseElements.keyId` for all operations — even operations that don't normally return a value (e.g., `DisableKey`). This makes it easy to search CloudTrail for all operations on a specific key.

### High-Volume Warning

`GenerateDataKey` calls can generate very high CloudTrail event volumes in data-intensive applications. Optionally exclude KMS events from a trail via `PutEventSelectors` — but note this breaks your audit trail.

---

## Patterns

### Service Integration (kms:ViaService)

Restricting a key policy so it can only be used when an AWS service calls KMS on the user's behalf:

```json
{
  "Condition": {
    "StringEquals": {
      "kms:ViaService": "s3.us-east-1.amazonaws.com"
    }
  }
}
```

### Encryption Context

Encryption context is a set of non-secret key-value pairs included in encrypt/decrypt calls. KMS binds the context to the ciphertext — decryption fails if the context doesn't match. Use it to enforce that data is only decrypted in the correct operational context.

```python
# Encrypt
kms.encrypt(
    KeyId=key_id,
    Plaintext=data_key,
    EncryptionContext={"Purpose": "S3FileEncryption", "Env": "prod"}
)

# Decrypt must supply same context
kms.decrypt(
    CiphertextBlob=ciphertext,
    EncryptionContext={"Purpose": "S3FileEncryption", "Env": "prod"}
)
```

### Terraform Pattern

```hcl
resource "aws_kms_key" "this" {
  description             = "CMK for ${var.project}-${terraform.workspace}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  multi_region            = false

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableIAMDelegation"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })

  tags = {
    Environment = terraform.workspace
    Project     = var.project
    ManagedBy   = "terraform"
  }
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.project}-${terraform.workspace}"
  target_key_id = aws_kms_key.this.key_id
}
```

---

## Gotchas

- **Root principal ≠ root user** — `arn:aws:iam::ACCOUNT:root` in a key policy enables IAM delegation; it is not the same as granting the account root user exclusive access.
- **Key policy is required for IAM delegation** — a key with no `EnableIAMUserPermissions` statement cannot be managed via IAM policies; only the key policy can grant access, and without this statement you can lock yourself out.
- **AWS owned keys have no CloudTrail** — if you need to audit who encrypted/decrypted data, you must use customer managed keys.
- **Multi-region ≠ free DR** — most AWS services don't leverage multi-region keys for cross-region replication; they decrypt and re-encrypt under the destination region's key even if a replica exists.
- **Rotation doesn't re-encrypt existing data** — old ciphertexts are decryptable using the old key material retained by KMS; rotation protects new encryptions only.
- **Asymmetric public key deletion risk** — downloaded public keys continue to work after the private key is deleted; resulting ciphertexts become permanently unrecoverable.
- **`kms:ViaService` condition on grants** — grants made with `kms:GrantIsForAWSResource` true restrict usage to AWS resource operations; direct application use is blocked.
- **Cross-account grants require key policy permission** — `CreateGrant` must be allowed in the key policy for the cross-account principal; the IAM policy alone is insufficient.
- **Key deletion waiting period can exceed stated window** — the actual deletion can occur up to 24 hours after the scheduled date; do not depend on exact timing.
- **Custom key store key deletion** — cluster backups may retain deleted material; you must delete the backups separately to fully purge the key.
- **High CloudTrail volume** — applications that call `GenerateDataKey` per-object (common in client-side encryption) generate one CloudTrail event per object; consider caching data keys or using the AWS Encryption SDK.

---

## References

- [[IAM/AWS IAM]]
- [[Storage/AWS S3]]
- [[Storage/AWS EFS]]
- [[Compute/AWS EC2]]
- [[Observability/AWS CloudWatch]]
