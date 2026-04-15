---
name: aws-ecr
description: Use when working with Amazon ECR - creating and managing container image repositories, pushing and pulling images, lifecycle policies, image scanning (basic and enhanced), cross-region and cross-account replication, pull through cache, tag immutability, repository policies, ECR Public, or any ECR architecture and troubleshooting decisions
---

# AWS ECR Expert Skill

Comprehensive Amazon ECR guidance covering repositories, image management, lifecycle policies, scanning, replication, and production patterns. Based on the official AWS ECR User Guide.

## When to Use This Skill

**Activate this skill when:**
- Creating or configuring ECR repositories (private or public)
- Setting up image push/pull authentication and permissions
- Writing lifecycle policies to manage image retention
- Configuring image scanning (basic CVE scanning or enhanced via Amazon Inspector)
- Setting up cross-region or cross-account replication
- Using pull through cache to proxy upstream registries
- Enforcing tag immutability
- Writing repository policies for cross-account access
- Troubleshooting image pull errors in ECS, EKS, or Lambda

**Don't use this skill for:**
- ECS task definitions or container orchestration — use aws-ecs skill
- General Docker image building and Dockerfile authoring

---

## Core Concepts

ECR is a fully managed Docker/OCI-compatible container registry. It has two tiers:

| Registry Type | Use Case | Authentication |
|--------------|----------|----------------|
| **Private** | Internal images; IAM-controlled access | AWS credentials (temporary token via `ecr:GetAuthorizationToken`) |
| **Public (ECR Public)** | Publicly distributable images; hosted at `public.ecr.aws` | Unauthenticated pull from any client; push requires AWS credentials |

---

## Authentication

ECR uses short-lived (12-hour) Docker login tokens issued by AWS:

```bash
# Authenticate Docker to your private registry
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin \
    123456789012.dkr.ecr.us-east-1.amazonaws.com
```

The IAM principal calling this must have `ecr:GetAuthorizationToken` permission. The token is scoped to all repositories in the registry for that region/account — not per-repository.

For ECS and EKS, the execution role (ECS) or node role (EKS) needs:
```
ecr:GetAuthorizationToken
ecr:BatchCheckLayerAvailability
ecr:GetDownloadUrlForLayer
ecr:BatchGetImage
```

The AWS managed policy `AmazonEC2ContainerRegistryReadOnly` grants these.

---

## Repositories

### Creating a Repository

```bash
aws ecr create-repository \
  --repository-name my-org/my-app \
  --image-tag-mutability IMMUTABLE \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=KMS,kmsKey=arn:aws:kms:...
```

**Naming:** Use namespaces (`org/team/service`) for organization — ECR supports `/` in repository names.

### Tag Immutability

Enable `IMMUTABLE` tag mutability on production repositories. This prevents overwriting an existing image tag — a `latest` tag cannot be silently overwritten. Enforces reproducibility and makes rollback reliable.

```bash
aws ecr put-image-tag-mutability \
  --repository-name my-app \
  --image-tag-mutability IMMUTABLE
```

With immutable tags, you must use a new tag for each image version. Common patterns: git SHA (`sha-a1b2c3d`), semantic version (`v1.2.3`), or build number.

### Encryption

ECR repositories are encrypted at rest by default (AES-256). For customer-managed key (CMK) encryption:
- Specify a KMS key at repository creation
- The key must be in the same region
- Grant ECR the `kms:GenerateDataKey` and `kms:Decrypt` permissions in the key policy

---

## Pushing and Pulling Images

```bash
# Tag and push
docker build -t my-app:v1.2.3 .
docker tag my-app:v1.2.3 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:v1.2.3
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:v1.2.3

# Pull
docker pull 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:v1.2.3
```

**Image manifest format:** ECR supports OCI and Docker manifest formats. ECR also supports multi-architecture image indexes (manifest lists) for `linux/amd64` + `linux/arm64` images.

### Digest vs Tag References

In production task definitions and Kubernetes manifests, reference images by digest instead of tag:

```
# Tag (mutable, can change)
123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:v1.2.3

# Digest (immutable, guaranteed reproducibility)
123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app@sha256:abc123...
```

Use digests in ECS task definitions for production deployments; use tags in CI/CD pipelines for convenience during build.

---

## Lifecycle Policies

Lifecycle policies automatically expire unneeded images to control storage costs. Evaluated daily.

### Policy Structure

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep last 10 tagged releases",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["v"],
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": { "type": "expire" }
    },
    {
      "rulePriority": 2,
      "description": "Expire untagged images older than 7 days",
      "selection": {
        "tagStatus": "untagged",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 7
      },
      "action": { "type": "expire" }
    },
    {
      "rulePriority": 3,
      "description": "Keep last 5 dev branch images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["dev-"],
        "countType": "imageCountMoreThan",
        "countNumber": 5
      },
      "action": { "type": "expire" }
    }
  ]
}
```

**Rule evaluation:** Rules are evaluated from lowest `rulePriority` number first. An image matched by an earlier rule is not evaluated against later rules.

**Test before applying:** Use `start-lifecycle-policy-preview` to dry-run a policy and see which images would be expired without actually deleting them.

**Important:** Lifecycle policies do not protect images referenced in running ECS tasks or EKS pods. Build your tag/count strategy to ensure actively deployed image versions are always within the retention window.

---

## Image Scanning

### Basic Scanning

- Uses AWS-native CVE database
- Scans for **OS-level vulnerabilities** only
- Triggers: manual or `scanOnPush`
- Results available via `describe-image-scan-findings` API

### Enhanced Scanning (Recommended)

- Powered by **Amazon Inspector**
- Scans for OS vulnerabilities **and** programming language package vulnerabilities (npm, pip, gem, etc.)
- Scanning modes:
  - `SCAN_ON_PUSH` — scans each new image pushed
  - `CONTINUOUS_SCAN` — re-scans images as new CVEs are discovered (14-day window)
- Results pushed to **EventBridge** automatically — use to trigger Slack notifications, fail deployments, etc.

```bash
# Enable enhanced scanning at the registry level
aws ecr put-registry-scanning-configuration \
  --scan-type ENHANCED \
  --rules '[{
    "repositoryFilters": [{"filter": "*", "filterType": "WILDCARD"}],
    "scanFrequency": "CONTINUOUS_SCAN"
  }]'
```

### Acting on Scan Results

Subscribe to EventBridge for Inspector findings:
```json
{
  "source": ["aws.inspector2"],
  "detail-type": ["Inspector2 Finding"],
  "detail": {
    "severity": ["CRITICAL", "HIGH"],
    "resources": [{ "type": ["AWS_ECR_CONTAINER_IMAGE"] }]
  }
}
```

Route to SNS → Slack, or Lambda → auto-block image deployment if CRITICAL findings exist.

---

## Repository Policies

Resource-based policies on individual repositories control cross-account access.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowAccountBPull",
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::ACCOUNT-B:root" },
    "Action": [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage"
    ]
  }]
}
```

The pulling account also needs `ecr:GetAuthorizationToken` in their IAM policy. Both the repository policy and IAM policy must allow the action for cross-account pulls.

---

## Cross-Region and Cross-Account Replication

Replication is configured at the **registry level** (not per-repository) and applies to all or filtered repositories.

```bash
aws ecr put-replication-configuration \
  --replication-configuration '{
    "rules": [{
      "destinations": [
        { "region": "eu-west-1", "registryId": "123456789012" },
        { "region": "ap-southeast-1", "registryId": "123456789012" }
      ],
      "repositoryFilters": [{
        "filter": "prod/",
        "filterType": "PREFIX_MATCH"
      }]
    }]
  }'
```

**Cross-account replication:** The destination account must create a registry policy allowing the source account to replicate:
```json
{
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::SOURCE-ACCOUNT:root" },
    "Action": ["ecr:CreateRepository", "ecr:ReplicateImage"],
    "Resource": "arn:aws:ecr:REGION:DEST-ACCOUNT:repository/*"
  }]
}
```

Replication is asynchronous. Use it to:
- Pre-position images in regions before deploying (faster cold starts)
- Disaster recovery (replicate to secondary region)
- Multi-region ECS/EKS deployments

---

## Pull Through Cache

Pull Through Cache allows ECR to act as a caching proxy for upstream public registries. ECR automatically checks the upstream registry for newer versions.

**Supported upstream registries:**
- Docker Hub (`registry-1.docker.io`)
- ECR Public (`public.ecr.aws`)
- Quay (`quay.io`)
- Kubernetes (`registry.k8s.io`)
- GitHub Container Registry (`ghcr.io`)

```bash
# Create a pull through cache rule
aws ecr create-pull-through-cache-rule \
  --ecr-repository-prefix "docker-hub" \
  --upstream-registry-url "registry-1.docker.io"

# Pull nginx via cache (first pull fetches from Docker Hub, subsequent pulls serve from ECR cache)
docker pull 123456789012.dkr.ecr.us-east-1.amazonaws.com/docker-hub/library/nginx:latest
```

Benefits:
- Eliminates Docker Hub rate limiting in CI/CD pipelines
- Images cached in your account — available even if upstream is down
- Apply ECR lifecycle policies to control cached image retention
- IAM-controlled access (instead of anonymous Docker Hub pulls)

---

## Repository Creation Templates

Automatically configure settings for repositories created through replication, pull through cache, or create-on-push:

```bash
aws ecr create-repository-creation-template \
  --prefix "prod/" \
  --applied-for PULL_THROUGH_CACHE REPLICATION \
  --image-tag-mutability IMMUTABLE \
  --encryption-configuration encryptionType=KMS \
  --lifecycle-policy '{"rules":[...]}' \
  --tags '[{"Key":"Env","Value":"prod"}]'
```

Templates ensure consistent configuration without manual setup for each auto-created repository.

---

## Architecture Patterns

### CI/CD Pipeline

```
GitHub Actions / CodeBuild
  1. Build Docker image
  2. Authenticate: aws ecr get-login-password | docker login
  3. Tag with git SHA: my-app:sha-a1b2c3d
  4. Push to ECR
  5. Scan: wait for Inspector finding results
  6. Gate: fail pipeline if CRITICAL findings
  7. Update ECS task definition or Helm chart with new image digest
  8. Deploy
```

### Multi-Region Image Distribution

```
Primary registry: us-east-1
  Replication rules:
    prod/* → us-west-2, eu-west-1, ap-southeast-1

ECS deployments in each region pull from the local ECR registry
  (no cross-region data transfer cost; faster cold starts)
```

### Secure Cross-Account Pattern (Shared Services)

```
Account: image-registry (shared services)
  ECR repositories: org/service-a, org/service-b
  Repository policy: allow Account B, C, D to pull

Account B/C/D: workload accounts
  IAM execution role: ecr:GetAuthorizationToken + pull permissions
  ECS task definitions: reference Account image-registry ARN
```

---

## Security Best Practices

1. **Enable tag immutability** on production repos — prevents accidental or malicious overwrite of a deployed tag
2. **Enable enhanced scanning** with CONTINUOUS_SCAN — catches new CVEs in already-deployed images
3. **Use KMS encryption** for sensitive images — gives CloudTrail audit trail and key control
4. **Least-privilege repository policies** — grant only pull permissions to consuming accounts; write access only to CI/CD roles
5. **Lifecycle policies on all repos** — prevent unbounded storage growth; untagged images accumulate quickly in active CI pipelines
6. **Pull through cache instead of direct Docker Hub** — avoids rate limiting and removes dependency on external registry availability
7. **Reference by digest in production** — ensures the exact image deployed is reproducible; never rely on mutable tags like `latest` in production

---

## Common Troubleshooting

| Symptom | Likely Cause |
|---------|-------------|
| `no basic auth credentials` on pull | Docker not authenticated; re-run `get-login-password` (token expires after 12 hours) |
| `AccessDeniedException` on image pull | IAM role missing pull permissions; or repository policy doesn't allow the account |
| `CannotPullContainerError` in ECS | Execution role missing ECR permissions; or VPC has no NAT/VPC endpoint for ECR; check `ecr.api` and `ecr.dkr` VPC endpoints |
| Image pull slow / cold starts | Image is large (>500 MB); use multi-stage builds to shrink; or image not yet replicated to local region |
| Lifecycle policy not expiring images | Images tagged with a prefix included in a keep rule; test with `start-lifecycle-policy-preview` |
| Replication not working | Destination registry policy doesn't allow source account; or replication is asynchronous — wait a few minutes |
| Tag mutation error | Repository has `IMMUTABLE` tag mutability; push with a new tag |
