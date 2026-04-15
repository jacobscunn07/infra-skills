---
name: conventional-commits
description: Use when writing git commit messages or branch names - formats commits as conventional commits (feat/fix/chore/etc with optional scope and breaking change markers), validates message structure, or advises on type selection for any change
---

# Conventional Commits

Commit messages follow the [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) specification.

---

## Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

- **type** — required. Describes the category of change (see types below).
- **scope** — optional. A noun in parentheses describing the section of the codebase affected (e.g., `vpc`, `rds`, `iam`).
- **description** — required. Short imperative summary. Capitalised first letter. No trailing period.
- **body** — optional. Free-form explanation of *why* (not what). Separated from description by a blank line.
- **footer(s)** — optional. One or more `Token: value` lines. Separated from body (or description if no body) by a blank line. `BREAKING CHANGE:` is a special footer.

---

## Types

| Type | When to use |
|---|---|
| `feat` | A new feature or capability |
| `fix` | A bug fix |
| `docs` | Documentation only changes |
| `style` | Formatting, whitespace — no logic change |
| `refactor` | Code restructuring with no feature or bug change |
| `perf` | Performance improvement |
| `test` | Adding or correcting tests |
| `build` | Changes to build system or external dependencies |
| `ci` | Changes to CI/CD configuration |
| `chore` | Routine tasks, dependency bumps, tooling changes that don't fit above |
| `revert` | Reverts a previous commit |

---

## Breaking Changes

Breaking changes must be indicated in **one of two ways** (or both):

1. Append `!` after the type/scope: `feat(iam)!: Replace inline policies with managed policies`
2. Add a `BREAKING CHANGE:` footer with a description of what breaks and how to migrate.

Both can be used together for maximum clarity.

---

## Examples

Simple:
```
fix(sg): Correct egress rule CIDR for app tier
```

With scope and body:
```
feat(rds): Add Aurora Serverless v2 cluster

Replaces the provisioned RDS instance in dev with Aurora Serverless v2
to reduce idle costs. Staging and prod remain provisioned.
```

Breaking change with `!` and footer:
```
feat(vpc)!: Migrate from single NAT gateway to per-AZ

BREAKING CHANGE: NAT gateway EIPs will be destroyed and recreated.
Existing connections through the NAT gateway will be interrupted during
apply. Run during a maintenance window.
```

Revert:
```
revert: Revert feat(ecs): Add container insights

Reverts commit a1b2c3d. Container Insights is generating unexpected
CloudWatch costs in dev.
```

No scope needed:
```
chore: Bump AWS provider to 5.54.0
```

Multiple footers:
```
fix(kms): Rotate data key on next encrypt call

Reviewed-by: Jane Smith
Refs: #42
```

---

## Choosing a Type

- Did it add something new the user/system can do? → `feat`
- Did it fix something broken? → `fix`
- Did it only touch comments, READMEs, or runbooks? → `docs`
- Did it restructure Terraform modules without changing what gets deployed? → `refactor`
- Did it change a CI workflow, Makefile, or build script? → `ci` or `build`
- Did it bump a provider version or update a lock file? → `chore`
- Does it break existing behaviour, destroy infrastructure, or require manual steps on apply? → use `!` and/or `BREAKING CHANGE:` footer on top of the type

---

## Scope Suggestions for Infrastructure Repos

Use the resource domain or layer as scope:

`vpc`, `subnet`, `sg`, `nacl`, `tgw`, `dx` — networking
`ec2`, `asg`, `alb`, `nlb` — compute and load balancing
`rds`, `aurora`, `elasticache` — databases
`s3`, `efs`, `ebs` — storage
`iam`, `scp`, `org` — identity
`kms`, `acm`, `secrets` — secrets and certificates
`ecs`, `ecr`, `eks` — containers
`cloudwatch`, `cloudtrail`, `config` — observability
`cloudfront`, `waf`, `r53` — edge and DNS
`ci`, `hooks`, `settings` — repo tooling
