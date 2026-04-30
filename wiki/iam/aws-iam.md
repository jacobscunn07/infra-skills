---
title: AWS IAM
tags: [iam, security, access-control, federation, abac, rbac, scp, permissions]
related: ["[[Concepts/Least Privilege]]", "[[Compute/AWS EC2]]", "[[Storage/AWS S3]]", "[[Storage/AWS ECR]]", "[[Security/AWS KMS]]"]
created: 2026-04-28
updated: 2026-04-28
---

## Overview

AWS Identity and Access Management (IAM) controls who can authenticate and what they are authorized to do in your AWS environment. It is free to use (except IAM Access Analyzer unused-access and custom policy check features). IAM changes are **eventually consistent** — propagation across AWS data centers can take time, so never place IAM changes in critical high-availability code paths.

## Key Concepts

### Identity Types

- **Root user** — full account access; never use for daily tasks; cannot attach identity-based policies or set a permissions boundary.
- **IAM users** — long-term credentials (password + access keys); prefer federation over creating users; only justified for workloads that can't use temporary credentials (legacy third-party tools, CodeCommit SSH, Amazon Keyspaces service credentials, emergency break-glass access).
- **IAM groups** — organizational container for users; cannot be principals in policies.
- **IAM roles** — no long-term credentials; issue temporary credentials via STS; the correct mechanism for compute workloads (EC2, Lambda, ECS), cross-account access, and federated identities.
- **Federated identities** — external users authenticated via SAML 2.0, OIDC, or IAM Identity Center; they assume a role and receive temporary credentials.
- **Service-linked roles** — pre-linked to specific AWS services; IAM admins can view but not edit permissions; must delete related resources before deleting the role.

### Policy Types

| Type | Grants permissions? | Scope |
|---|---|---|
| Identity-based | Yes | Attached to IAM user, group, or role |
| Resource-based | Yes | Attached to a resource (S3 bucket, KMS key, IAM role trust policy) |
| Permissions boundary | No (ceiling only) | Applied to IAM user or role; limits identity-based policies |
| SCP (Service Control Policy) | No (ceiling only) | AWS Organizations; limits all principals in account/OU including root |
| RCP (Resource Control Policy) | No (ceiling only) | AWS Organizations; limits resource permissions regardless of identity |
| Session policy | No (ceiling only) | Passed at `AssumeRole` / `AssumeRoleWithWebIdentity` / `AssumeRoleWithSAML` time |
| ACL | Yes (cross-account only) | Non-JSON; S3, WAF, VPC; cannot control same-account access |

**Managed vs. inline identity-based policies:**
- Managed (AWS-managed or customer-managed): reusable, standalone, attached to multiple identities.
- Inline: 1:1 with identity; deleted when identity is deleted; use only when policy must not be accidentally reused.

**Resource-based policies are always inline** — there are no managed resource-based policies.

### Trust Policies

A trust policy is the resource-based policy on an IAM role that defines which principals are trusted to assume it. Key rules:
- **Cannot use wildcards (`*`) in ARN principal elements** — you must specify exact ARNs.
- Service principals look like `"Service": "ec2.amazonaws.com"`.
- Federated principals use `"Federated": "arn:aws:iam::ACCOUNT:oidc-provider/..."` or SAML ARN.

## Patterns

### Policy Evaluation Logic

**Same-account, identity-based + resource-based:**
```
Allow = Identity-based UNION Resource-based (OR logic)
Explicit Deny in either = final deny
```

**Identity-based + permissions boundary:**
```
Allow = Identity-based INTERSECT Permissions-boundary (AND logic)
```

**Identity-based + SCP/RCP (Organizations member):**
```
Allow = Identity-based INTERSECT SCP INTERSECT RCP (AND logic)
```

**Cross-account access (no resource-based policy):**
Both the resource-account's identity-based policy AND the trusting account's resource-based policy must grant access. Missing either side = deny.

**Session policies:**
- Resource-based policy specifies **entity ARN** → session policy *does* limit resource-based access.
- Resource-based policy specifies **session ARN** → resource-based access bypasses session policy limit.
- With permissions boundary: `Allow = Session INTERSECT Boundary INTERSECT Identity-based`.

**Universal override:** An explicit `Deny` in *any* policy type overrides all `Allow` statements everywhere.

**Default:** Implicit deny — if no policy explicitly allows, the action is denied.

### Cross-Account Access

Pattern 1 — Role assumption (recommended):
1. Create a role in the **trusting account** with a trust policy naming the **trusted account** (or specific principal).
2. Attach a permissions policy on the user/role in the trusted account granting `sts:AssumeRole` on the target role ARN.

Pattern 2 — Resource-based policy (S3, SNS, SQS, KMS, etc.):
- Add the external principal directly to the resource policy.
- The principal's identity-based policy must also allow the action.

### Federation

| Method | Use case | STS API |
|---|---|---|
| IAM Identity Center | Human users, multi-account, SSO | N/A (managed) |
| SAML 2.0 | Corporate IdP (ADFS, Okta, etc.) | `AssumeRoleWithSAML` |
| OIDC / Web Identity | GitHub Actions, EKS IRSA, external workloads | `AssumeRoleWithWebIdentity` |
| Amazon Cognito Identity Pools | Mobile/web app end users | `AssumeRoleWithWebIdentity` |
| IAM Roles Anywhere | On-premises machines, external servers | Certificate-based |

Setup for SAML/OIDC federation:
1. Create an identity provider entity in IAM.
2. Establish trust between AWS account and the IdP.
3. Add the IdP ARN as the `Federated` principal in a role trust policy.

### ABAC (Attribute-Based Access Control)

ABAC grants access by matching tags on principals (session tags) against tags on resources — instead of listing specific resource ARNs.

```json
"Condition": {
  "StringEquals": {
    "aws:ResourceTag/access-project": "${aws:PrincipalTag/access-project}"
  }
}
```

**ABAC vs. RBAC:**
- ABAC: fewer policies, auto-scales to new tagged resources, dynamic; requires strict tag discipline.
- RBAC: explicit role-per-function policies; easier to audit; required when services don't support tag-based conditions.

Federated users can carry ABAC tags from corporate directories via SAML/OIDC session tags.

### STS and Temporary Credentials

- Standard `AssumeRole` max duration: 43,200 seconds (12 hours).
- **Role chaining hard limit: 1 hour** — if RoleA assumes RoleB and then RoleB assumes RoleC, the session is capped at 1 hour regardless of `max_session_duration`. Requesting `DurationSeconds > 3600` fails.
- Users temporarily surrender own permissions when they assume a role; original permissions restore when the session ends.

### Least Privilege

1. Generate a policy from CloudTrail activity (`Access Analyzer > Policy Generation`).
2. Review Access Advisor "last accessed" data to identify unused service permissions.
3. Run `Access Analyzer > Policy Validation` (100+ checks) on every new policy.
4. Classify actions: List → Read → Write → Permissions Management → Tagging; prefer narrower categories.
5. Use custom policy checks (`ValidatePolicy` API) to enforce org security standards in CI.

## Gotchas

- **Eventual consistency** — IAM changes replicate globally with a delay; do not put IAM creation/update calls in the critical path of automated workflows.
- **Permissions boundary scope** — boundaries limit identity-based policies only; they do NOT limit resource-based policies (unless the resource-based policy explicitly names the role ARN as a session principal).
- **No managed resource-based policies** — all resource-based policies (S3 bucket policies, KMS key policies, role trust policies) are inline; you cannot detach and reuse them.
- **ACL cross-account only** — ACLs on S3/VPC/WAF cannot be used to grant access to principals in the same account.
- **Service-linked role deletion** — must delete the service's resources first; IAM admins cannot edit the role's permissions policy.
- **Role chaining cap** — 1-hour session maximum regardless of role `max_session_duration`; plan architecture to avoid deep chains when long-running sessions are needed.
- **Trust policy wildcards** — `*` is not valid in the principal ARN of a trust policy; you must name exact ARN(s).
- **Root user** — cannot attach identity-based policies or set permissions boundaries on root; root is affected by SCPs/RCPs when in an Organization.
- **Access Analyzer regional scope** — external access analyzers must be enabled per-region; unused access analyzers cover all regions from any single region.
- **Access Analyzer delays** — findings from normal policy changes appear in ~30 min; multi-region S3 access point changes up to 6 hours; some periodic scans up to 24 hours.
- **ABAC tag discipline** — if tags can be modified by the principal themselves, they can potentially escalate their own access; restrict `aws:RequestTag` and `aws:TagKeys` conditions carefully.

## IAM Access Analyzer

Six capabilities:

| Capability | What it does | Pricing |
|---|---|---|
| External access analysis | Finds resources shared with external principals | Free |
| Internal access analysis | Maps principal-to-resource access within org | Per resource/month |
| Unused access analysis | Detects unused roles, keys, passwords, service permissions | Per IAM entity/month |
| Policy validation | 100+ grammar and best-practice checks | Free |
| Custom policy checks | Validates against org security standards | Per API request |
| Policy generation | Generates least-privilege policy from CloudTrail | Free |

Resources analyzed for external access: S3 buckets, IAM roles, KMS keys, Lambda, SQS, SNS, Secrets Manager, EBS/RDS/ECR snapshots, EFS, DynamoDB.

Internal access analysis is limited to: S3 buckets, RDS snapshots, DynamoDB tables/streams.

## References

- [[Compute/AWS EC2]]
- [[Storage/AWS S3]]
- [[Storage/AWS ECR]]
- [[Observability/AWS CloudWatch]]
