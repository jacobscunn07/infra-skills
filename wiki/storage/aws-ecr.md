---
title: AWS ECR
tags: [ecr, containers, registry, docker, oci, lifecycle, scanning, replication, pull-through-cache]
related: ["[[Compute/AWS ECS]]", "[[Storage/AWS S3]]", "[[IAM/IAM Policies]]", "[[Concepts/Least Privilege]]"]
created: 2026-04-28
updated: 2026-04-28
---

## Overview

Amazon ECR is a fully managed container image registry. It stores Docker images, OCI artifacts (Helm charts, SBOMs, signatures), and multi-architecture manifest lists. Access is controlled entirely by IAM, with optional resource-based repository policies for cross-account sharing. ECR integrates natively with ECS, EKS, Lambda, and CodeBuild.

## Key Concepts

- **Registry**: One per AWS account per region; addressed as `<account-id>.dkr.ecr.<region>.amazonaws.com`
- **Repository**: Logical namespace within a registry; holds related images with independent settings for tag mutability, scanning, and lifecycle
- **Image**: Identified by both a human-readable tag and an immutable SHA-256 digest (`sha256:abc123...`)
- **Layer**: Content-addressable image layer; deduplicated within a registry — multiple images sharing a base layer store it once
- **OCI artifact**: Non-container content (Helm charts, Notation signatures, SBOMs) stored using the OCI spec alongside images
- **Authorization token**: Short-lived 12-hour credential obtained via `ecr:GetAuthorizationToken`; required for all push/pull operations
- **Pull-through cache**: On-demand mirror of external registries (Docker Hub, ECR Public, Quay) hosted within your account
- **Replication**: Asynchronous copy of images across regions or accounts based on configurable rules

## Patterns

### Tag Immutability

Enable `imageTagMutability = IMMUTABLE` on production repositories to prevent tag overwrites.

- Prevents `docker push myapp:latest` from silently replacing a deployed image
- **Does not prevent deletion** — immutable tags can still be removed via `BatchDeleteImage`
- Pulling by digest (`IMAGE@sha256:...`) bypasses tag semantics entirely and is always safe

### Lifecycle Policies

Automate image cleanup to control cost and reduce CVE exposure from stale images.

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep last 10 images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": { "type": "expire" }
    }
  ]
}
```

- Rules apply in ascending `rulePriority` order; lower number wins
- Untagged images must be explicitly targeted — they do not auto-delete without a rule
- Always do a dry-run (`PreviewLifecyclePolicy`) before activating; deletion is immediate and irreversible
- Common pattern: keep N most recent tagged images + delete untagged images older than 1 day

### Image Scanning

**Basic scanning** (built-in): Scans on push for CVEs using the Common Vulnerabilities and Exposures database. Results appear within minutes. Enabled per-repository or as a registry default.

**Enhanced scanning** (Amazon Inspector): Continuously re-evaluates stored images as new CVEs are published. Finds vulnerabilities discovered after a push — critical for long-lived base images. Requires Inspector subscription.

- Scan findings are stored separately from images; deleting an image does not delete its findings history
- Integrate findings into CI/CD: fail builds when `CRITICAL` findings exist

### Cross-Account Pull (Resource-Based Policy)

To allow an external account to pull images without cross-account IAM role assumption:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::CONSUMER_ACCOUNT:root" },
    "Action": [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages"
    ],
    "Resource": "arn:aws:ecr:REGION:PRODUCER_ACCOUNT:repository/REPO_NAME"
  }]
}
```

The consuming account still needs `ecr:GetAuthorizationToken` in its own IAM policy — `GetAuthorizationToken` is a registry-level action, not repository-level, and cannot be granted via repository policy.

### Cross-Region / Cross-Account Replication

Replication is async and rule-based. Rules can filter by repository name prefix or tag pattern.

- Deletion in the source does **not** propagate — replicated copies must be cleaned up independently
- Repository names must match exactly across source and destination
- The replication service needs `ecr:CreateRepository` in the destination to auto-create repos

### Pull-Through Cache

Mirror upstream public registries into your own ECR namespace. On first pull, ECR fetches from upstream and caches. Subsequent pulls use the cache.

```
docker pull <account>.dkr.ecr.<region>.amazonaws.com/ecr-public/amazonlinux/amazonlinux:latest
```

- Cache repositories are created automatically on first pull
- External registry credentials (Docker Hub rate limits) stored in Secrets Manager
- No automatic sync — cache refreshes only on explicit pull; images can become stale

### Credential Refresh Pattern

The 12-hour token expiry is a common failure mode in long-running processes (CI pipelines, ECS agents).

- Use `amazon-ecr-credential-helper` as the Docker credential helper — it auto-refreshes before expiry
- On ECS/EKS, the node's IAM role handles authentication automatically; no manual refresh needed
- Avoid storing the token in environment variables that outlive the 12-hour window

## Gotchas

- **`GetAuthorizationToken` is not repository-scoped** — any principal with this permission can attempt to authenticate to the registry, even without access to specific repositories. Grant it broadly but rely on repository policies for access control.
- **Tag immutability ≠ deletion protection** — immutable tags block overwrites but not `BatchDeleteImage`. Use lifecycle dry-runs and access policies to guard deletions.
- **Untagged images persist and accrue cost** — untagged images do not self-clean. A lifecycle rule targeting `tagStatus: untagged` is required.
- **Replication is eventual and one-way** — do not rely on replication latency for blue/green deployments; deletes do not propagate.
- **Layer deduplication is registry-wide, not cross-account** — shared base images save storage within a single registry, not across accounts.
- **BatchDeleteImage has a 100-image-per-call limit** — pagination required when bulk-deleting.
- **Scanning does not block pulls** — findings are informational only unless you build enforcement into CI/CD or admission controllers.
- **Cross-region data transfer is charged** — replication doubles storage costs; weigh against pull latency savings.
- **ECR Public is a separate service** — `ecr-public` actions and API endpoints differ from private ECR; IAM policies must reference the correct service.

## Common Failure Modes

| Error | Cause | Fix |
|---|---|---|
| `AccessDenied` on pull | Missing `ecr:GetAuthorizationToken` | Add to the IAM role |
| `RepositoryNotFoundException` | Wrong region or account in registry URL | Verify URL format: `<account>.dkr.ecr.<region>.amazonaws.com` |
| `ImageAlreadyExistsException` | Pushing tag that already exists with immutability enabled | Delete the tag first or use a new tag |
| `UnauthorizedOperation` | Expired 12-hour token | Refresh with `aws ecr get-login-password` |
| `LimitExceededException` | Service quota hit | Request increase or delete old images |
| Lifecycle policy not firing | Rule saved but no matching images, or wrong `tagStatus` | Use `PreviewLifecyclePolicy` to debug |
| Scan findings not appearing | Scan still running or scan not enabled | Enable `scanOnPush`; enhanced scanning needs Inspector |

## References

- [[Compute/AWS ECS]]
- [[Storage/AWS S3]]
- [[IAM/IAM Policies]]
