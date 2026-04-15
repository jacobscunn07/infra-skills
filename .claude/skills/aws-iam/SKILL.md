---
name: aws-iam
description: Use when working with AWS IAM - designing identity and access management strategy, writing IAM policies (identity-based, resource-based, SCPs), configuring IAM roles and trust policies, cross-account access, federation (SAML, OIDC), STS temporary credentials, permissions boundaries, IAM Access Analyzer, or any IAM architecture and troubleshooting decisions
---

# AWS IAM Expert Skill

Comprehensive AWS Identity and Access Management guidance covering policies, roles, federation, STS, permissions boundaries, and production patterns. Based on the official AWS IAM User Guide.

## When to Use This Skill

**Activate this skill when:**
- Designing IAM policy structure (identity-based, resource-based, SCPs, RCPs)
- Writing or debugging IAM policy JSON
- Configuring IAM roles and trust policies
- Setting up cross-account access
- Implementing federation (SAML 2.0, OIDC/WebIdentity)
- Using STS to obtain temporary credentials
- Configuring permissions boundaries for delegated administration
- Implementing least-privilege using IAM Access Analyzer
- Troubleshooting access denied errors or unexpected permission grants
- Designing multi-account guardrails with AWS Organizations

**Don't use this skill for:**
- AWS IAM Identity Center (SSO) configuration — separate service
- Cognito identity pools (end-user identity)
- Resource-level access control for specific services (e.g., S3 bucket policies in isolation)

---

## Core Concepts

### The Two Questions IAM Answers

| Question | IAM Mechanism |
|----------|--------------|
| **Who are you?** (Authentication) | Users, roles, federated identities, service principals |
| **What can you do?** (Authorization) | Policies evaluated against the request context |

### Principal Types

| Principal | Long-Term Credentials | Typical Use |
|-----------|----------------------|-------------|
| **Root user** | Email + password | Account setup only — never for daily use |
| **IAM user** | Password + access keys | Legacy; prefer federation for humans |
| **IAM role** | None (temporary via STS) | Services, cross-account, federation |
| **Federated identity** | External IdP (SAML, OIDC) | Human users via SSO |
| **Service principal** | Managed by AWS | AWS services acting on your behalf |

> **Key principle:** Humans should use federation with temporary credentials. Workloads on AWS should use IAM roles. Long-term access keys are a last resort.

### IAM Is Eventually Consistent

Changes to users, groups, roles, and policies replicate across AWS's global infrastructure. Don't put IAM changes in critical high-availability code paths. Use separate initialization routines and verify propagation before production workflows depend on the change.

---

## Policy Types

AWS evaluates seven policy types. Understanding which applies when is critical for debugging access issues.

| Policy Type | Attached To | Grants Permissions? | Use Case |
|-------------|------------|--------------------|---------| 
| **Identity-based** | User, role, or group | Yes | Primary way to grant permissions |
| **Resource-based** | Resource (S3, KMS, etc.) | Yes | Cross-account access, resource sharing |
| **Permissions boundary** | User or role | No (limits only) | Delegate admin with guardrails |
| **SCP** | AWS Org OU or account | No (limits only) | Organization-wide guardrails |
| **RCP** | AWS Org OU or account | No (limits only) | Resource-level org guardrails |
| **Session policy** | Temporary session | No (limits only) | Restrict assumed-role sessions |
| **ACL** | Resource (S3, WAF, VPC) | Yes | Cross-account only; non-JSON |

---

## Policy JSON Structure

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ReadAccess",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::123456789012:role/my-role" },
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::my-bucket",
        "arn:aws:s3:::my-bucket/*"
      ],
      "Condition": {
        "Bool": { "aws:SecureTransport": "true" }
      }
    }
  ]
}
```

### Element Reference

| Element | Required | Notes |
|---------|----------|-------|
| `Version` | Recommended | Always use `"2012-10-17"` |
| `Sid` | No | Human-readable statement ID; useful for debugging |
| `Effect` | Yes | `Allow` or `Deny` |
| `Principal` | Resource-based only | Omit in identity-based policies |
| `Action` | Yes | Service prefix + action name (`s3:GetObject`) |
| `Resource` | Yes (identity-based) | ARN of target resource; `"*"` for global actions |
| `Condition` | No | Narrows when the statement applies |

### Common Condition Keys

```json
"Condition": {
  "Bool":          { "aws:MultiFactorAuthPresent": "true" },
  "StringEquals":  { "aws:RequestedRegion": "us-east-1" },
  "StringLike":    { "s3:prefix": ["home/${aws:username}/*"] },
  "ArnLike":       { "aws:PrincipalArn": "arn:aws:iam::*:role/dev-*" },
  "IpAddress":     { "aws:SourceIp": "203.0.113.0/24" },
  "DateLessThan":  { "aws:CurrentTime": "2025-12-31T23:59:59Z" },
  "Null":          { "aws:TokenIssueTime": "false" }
}
```

---

## Policy Evaluation Logic

### The Core Rule: Explicit Deny Wins

AWS evaluates all applicable policies and uses this priority:
1. **Explicit Deny** — overrides everything, no exceptions
2. **Explicit Allow** — grants access if no deny exists
3. **Default Deny** — everything is denied unless explicitly allowed

### Same-Account Evaluation

When the principal and resource are in the same account:

```
Identity-based policy OR Resource-based policy = Allow
(either one granting access is sufficient)

If Permissions Boundary exists:
  Effective = Identity-based ∩ Permissions Boundary
  (resource-based policies are NOT limited by the boundary for IAM users)

If in AWS Organization:
  Effective = Identity-based ∩ SCP ∩ RCP
```

### Cross-Account Evaluation

Both sides must explicitly allow:

```
Account A resource-based policy must allow Account B principal
AND
Account B identity-based policy must allow the action on Account A resource
```

A role ARN in a resource policy is NOT sufficient alone — the account B principal needs `sts:AssumeRole` permission pointing at the Account A role.

### Visual Decision Flow

```
Request arrives
    │
    ▼
Explicit Deny anywhere? ──Yes──▶ DENY
    │ No
    ▼
SCP allows? (if in Org) ──No──▶ DENY
    │ Yes
    ▼
Resource-based policy allows? ──Yes──▶ ──────────────────────────┐
    │ No                                                           │
    ▼                                                             ▼
Identity-based policy allows? ──No──▶ DENY          Permissions boundary allows?
    │ Yes                                              (if boundary attached)
    ▼                                                  Yes──▶ ALLOW
Permissions boundary allows? ──No──▶ DENY              No──▶ DENY
    │ Yes
    ▼
ALLOW
```

---

## IAM Roles

Roles are the preferred identity mechanism for all non-human access. They provide temporary credentials — no long-term keys to rotate or leak.

### Role vs. User

| | IAM Role | IAM User |
|---|---|---|
| **Credentials** | Temporary (STS) | Long-term (access keys) |
| **Rotation** | Automatic | Manual |
| **Who uses it** | Anyone who assumes it | One specific person/service |
| **Audit trail** | RoleSessionName in CloudTrail | Username |

### Role Anatomy

Every role has two policies:

**1. Trust policy** — *who can assume this role* (resource-based policy on the role itself)
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "lambda.amazonaws.com"
    },
    "Action": "sts:AssumeRole"
  }]
}
```

**2. Permissions policy** — *what the role can do* (identity-based policy attached to the role)

### Common Trust Policy Principals

```json
// AWS service
"Principal": { "Service": "ec2.amazonaws.com" }
"Principal": { "Service": "ecs-tasks.amazonaws.com" }
"Principal": { "Service": "lambda.amazonaws.com" }

// Another account (cross-account)
"Principal": { "AWS": "arn:aws:iam::ACCOUNT-ID:root" }

// Specific role in another account
"Principal": { "AWS": "arn:aws:iam::ACCOUNT-ID:role/role-name" }

// OIDC federation (GitHub Actions)
"Principal": { "Federated": "arn:aws:iam::ACCOUNT-ID:oidc-provider/token.actions.githubusercontent.com" }

// SAML federation
"Principal": { "Federated": "arn:aws:iam::ACCOUNT-ID:saml-provider/MyCorpIdP" }
```

### Service-Linked Roles

AWS services create these automatically. They are:
- Named with `AWSServiceRoleFor*` prefix
- Not editable — permissions are defined by the service
- Deleted only after the service resources using them are removed

Do not confuse with service roles (which you create and manage).

### Role Chaining

Assuming a role from a role (RoleA → RoleB). Key limitation: **maximum session duration is always 1 hour**, regardless of the individual role's `MaxSessionDuration` setting. Plan around this for long-running pipelines.

---

## STS Temporary Credentials

### STS API Reference

| API | Caller Needs | Default Duration | Max Duration | Use Case |
|-----|-------------|-----------------|--------------|----------|
| `AssumeRole` | Valid AWS credentials | 1 hour | 12 hours | Cross-account, federation, service access |
| `AssumeRoleWithWebIdentity` | OIDC JWT token (unsigned) | 1 hour | 12 hours | GitHub Actions, Google, Facebook |
| `AssumeRoleWithSAML` | SAML assertion (unsigned) | 1 hour | 12 hours | Active Directory, OpenLDAP |
| `GetFederationToken` | IAM user credentials | 12 hours | 36 hours | Custom broker applications |
| `GetSessionToken` | IAM user credentials | 12 hours | 36 hours | MFA-required sessions |

### AssumeRole Example

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::123456789012:role/MyRole \
  --role-session-name my-session \
  --duration-seconds 3600
```

Response includes `AccessKeyId`, `SecretAccessKey`, `SessionToken`, and `Expiration`. Set all three as environment variables or use the SDK's credential provider chain.

### External ID (Confused Deputy Prevention)

When granting a third party (different AWS account/org) access to your account, always require an external ID:

```json
{
  "Effect": "Allow",
  "Principal": { "AWS": "arn:aws:iam::THIRD-PARTY-ACCOUNT:root" },
  "Action": "sts:AssumeRole",
  "Condition": {
    "StringEquals": { "sts:ExternalId": "unique-customer-specific-id" }
  }
}
```

The third party passes the external ID when calling `AssumeRole`. This prevents a compromised third-party service from accessing your account using another customer's role ARN.

---

## Permissions Boundaries

Permissions boundaries set the **maximum permissions** an identity-based policy can grant. They don't grant anything on their own.

```
Effective permissions = Identity-based policy ∩ Permissions boundary
```

### Primary Use Case: Safe Delegation

Allow a developer or automation to create IAM roles, but cap what those roles can do:

```json
// Boundary applied to all new roles created by the delegate
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowedServices",
      "Effect": "Allow",
      "Action": ["s3:*", "dynamodb:*", "logs:*"],
      "Resource": "*"
    },
    {
      "Sid": "DenyIAMEscalation",
      "Effect": "Deny",
      "Action": ["iam:*", "organizations:*", "sts:*"],
      "Resource": "*"
    }
  ]
}
```

### Boundary + Delegation Pattern

The delegating admin:
1. Creates a boundary policy defining the ceiling
2. Gives the delegate permission to create roles **only if** they attach the boundary:
```json
{
  "Effect": "Allow",
  "Action": ["iam:CreateRole", "iam:AttachRolePolicy"],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "iam:PermissionsBoundary": "arn:aws:iam::ACCOUNT:policy/TeamBoundary"
    }
  }
}
```
3. Denies the delegate from deleting or modifying the boundary policy itself

### Boundaries and Resource-Based Policies

- **IAM roles:** Resource-based policy access is limited by the permissions boundary
- **IAM users:** Resource-based policy access is NOT limited by the permissions boundary

---

## AWS Organizations Guardrails

### SCPs (Service Control Policies)

Limit what identities (users and roles) in member accounts can do. Apply to an entire OU or account.

```json
// Deny all actions outside us-east-1 and us-west-2
{
  "Effect": "Deny",
  "Action": "*",
  "Resource": "*",
  "Condition": {
    "StringNotEquals": {
      "aws:RequestedRegion": ["us-east-1", "us-west-2"]
    }
  }
}
```

Common SCP patterns:
- Deny root user actions
- Require encryption on S3 puts
- Restrict to approved regions
- Prevent disabling CloudTrail or GuardDuty
- Prevent leaving the organization

### RCPs (Resource Control Policies)

Limit what can be done TO resources in member accounts, regardless of who the caller is. Newer than SCPs; use for cross-account resource protection.

```json
// Deny non-HTTPS access to all S3 buckets in the org
{
  "Effect": "Deny",
  "Action": "s3:*",
  "Resource": "*",
  "Condition": {
    "Bool": { "aws:SecureTransport": "false" }
  }
}
```

---

## Federation

### SAML 2.0 (Active Directory / Enterprise IdP)

Flow:
```
User → IdP login → SAML assertion → sts:AssumeRoleWithSAML → Temp credentials → AWS Console/CLI
```

Setup requirements:
1. Create SAML provider in IAM with the IdP's metadata XML
2. Create IAM roles with a trust policy using `Federated: arn:aws:iam::ACCOUNT:saml-provider/Name`
3. IdP sends `Role` and `RoleSessionName` attributes in the SAML assertion

### OIDC / WebIdentity (GitHub Actions, Google, etc.)

Flow:
```
Workload → OIDC token from IdP → sts:AssumeRoleWithWebIdentity → Temp credentials
```

GitHub Actions example trust policy:
```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:myorg/myrepo:*"
    }
  }
}
```

Lock down the `sub` condition to specific repos and branches — don't use `"*"`.

---

## Architecture Patterns

### Service Role (EC2 / Lambda / ECS)

```
EC2 instance or Lambda function
    │
    └── Instance/Execution Role (trust: service principal)
         └── Permissions policy: s3:GetObject, dynamodb:PutItem, etc.

No access keys in code or environment variables.
SDK credential chain picks up the role automatically.
```

### Cross-Account Access (Resource Owner Pattern)

```
Account A (resource owner — e.g., data lake)
    S3 bucket policy: allow Account B role → s3:GetObject

Account B (consumer — e.g., analytics)
    IAM role: allow sts:AssumeRole on Account A role
    App assumes role → gets temp creds for Account A S3
```

Both sides must allow explicitly.

### Cross-Account Role Assumption

```
Account A: Role "ReadonlyAuditRole"
  Trust policy: Principal = Account B root or specific role
  Permissions: read-only actions

Account B: IAM entity with policy:
  sts:AssumeRole → arn:aws:iam::ACCOUNT-A:role/ReadonlyAuditRole
```

### Delegated IAM Administration

```
Admin (full IAM access)
    Creates boundary policy: "DeveloperBoundary" (caps at non-IAM services)
    Creates delegate role with:
      - iam:CreateRole (only with boundary condition)
      - iam:AttachRolePolicy
      - Deny: iam:DeletePolicy on "DeveloperBoundary"

Developer
    Can create roles with DeveloperBoundary attached
    Cannot escalate beyond the boundary
    Cannot remove the boundary policy
```

### OIDC CI/CD (GitHub Actions → AWS)

```
GitHub Actions workflow
    │ requests OIDC JWT from GitHub
    │
    └── sts:AssumeRoleWithWebIdentity
         Role trust: token.actions.githubusercontent.com
         Condition: sub matches repo:org/repo:ref:refs/heads/main
         Permissions: ecr:GetAuthorizationToken, ecr:BatchGetImage, etc.
```

No static credentials stored in GitHub Secrets.

---

## IAM Access Analyzer

Three capabilities:

| Capability | What It Does |
|-----------|-------------|
| **External access analysis** | Finds resources (S3, KMS, IAM roles, etc.) accessible outside your account/org |
| **Unused access analysis** | Identifies unused roles, users, keys, and permissions |
| **Policy validation** | 100+ checks on policy JSON for correctness and best practices |

Enable an analyzer per region. Set the zone of trust to your AWS Organization to catch cross-account but intra-org findings separately from truly external findings.

**Policy generation from CloudTrail:** Access Analyzer can read 90 days of CloudTrail logs and generate a least-privilege policy based on what was actually called. Use this to tighten overly broad policies.

---

## Security Best Practices

1. **No root user for daily tasks** — lock down root with MFA and a hardware key; only use for account-level tasks (billing, support tier changes, account deletion)
2. **Humans use federation** — IAM Identity Center (or direct SAML/OIDC) with temporary credentials; no IAM user accounts for people
3. **Workloads use roles** — never embed access keys in code, environment variables, or config files; use instance profiles, Lambda execution roles, ECS task roles
4. **Least privilege** — start with AWS managed policies to unblock, then replace with customer-managed policies scoped to exact actions and resources
5. **Require MFA** — enforce with a condition key on sensitive actions:
   ```json
   "Condition": { "Bool": { "aws:MultiFactorAuthPresent": "true" } }
   ```
6. **Require TLS** — add a deny on `aws:SecureTransport: false` for any resource-based policy
7. **Use permissions boundaries for delegation** — don't give developers `iam:*`; give them scoped create permissions with a mandatory boundary
8. **SCPs as guardrails** — deny root actions, restrict regions, prevent disabling security services; never rely on SCPs as your only control
9. **Regularly review unused access** — use IAM Access Analyzer unused access findings and last-accessed data in the console to prune stale permissions
10. **Validate policies before deploying** — run `aws accessanalyzer validate-policy` in CI/CD pipelines
11. **External IDs for third-party roles** — always require an external ID when a third-party service needs to assume a role in your account
12. **Audit with CloudTrail** — all IAM and STS API calls are logged; set up alerts for `sts:AssumeRole` by unexpected principals and `iam:CreateUser`/`iam:AttachUserPolicy`

---

## Common Troubleshooting

### Access Denied Errors

| Symptom | Likely Cause |
|---------|-------------|
| `AccessDenied` on same-account call | Identity-based policy doesn't allow the action; or explicit deny somewhere |
| `AccessDenied` on cross-account call | Either the resource-based policy OR the identity-based policy is missing — both required |
| `AccessDenied` despite correct IAM policy | SCP in the organization is blocking it; or permissions boundary limiting it |
| `AccessDenied` after assuming role | Forgot to include the session token; or policy not attached to the role |
| `AccessDenied` for a service (e.g., Lambda) | Trust policy doesn't include the service principal; or action not in permissions policy |
| `UnauthorizedOperation` | Different phrasing for same issue — evaluate as `AccessDenied` |

**Debugging steps:**
1. Use **IAM Policy Simulator** to test a specific principal + action + resource combination
2. Check **CloudTrail** for the `errorCode: AccessDenied` event — the event includes the policy type that denied
3. Check **SCPs** if the account is in an AWS Organization
4. Check **permissions boundary** if the role was created by a delegated admin
5. For cross-account: verify BOTH the resource-based policy AND the identity-based policy allow the action

### Role Assumption Failures

| Symptom | Likely Cause |
|---------|-------------|
| `AccessDenied` on `sts:AssumeRole` | Caller's identity-based policy doesn't allow `sts:AssumeRole` on that role ARN |
| Trust policy error | Principal in trust policy doesn't match the caller exactly (case-sensitive ARNs) |
| `InvalidClientTokenId` | Credentials have expired; old session token |
| `ExpiredTokenException` | Session token expired — re-assume the role |
| Role chaining > 1 hour | Role chaining caps session at 1 hour regardless of `MaxSessionDuration` |

### Policy Writing Mistakes

| Mistake | Fix |
|---------|-----|
| `s3:ListBucket` on `bucket/*` instead of `bucket` | `ListBucket` applies to bucket ARN; object actions apply to `bucket/*` |
| `"Resource": "*"` for IAM actions that support resource-level | Scope to specific role/user ARNs where possible |
| Missing `sts:AssumeRole` permission on the caller | Add `sts:AssumeRole` to the identity-based policy of the entity doing the assuming |
| Wildcard `Principal: "*"` in Allow | Allows anyone; should almost always be a specific ARN or have restrictive Conditions |
| Forgetting `Version: "2012-10-17"` | Some condition keys (like `${aws:username}`) won't interpolate correctly without it |
