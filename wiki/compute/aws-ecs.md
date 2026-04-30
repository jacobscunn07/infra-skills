---
title: AWS ECS
tags: [ecs, containers, fargate, compute, orchestration, task-definition, capacity-providers, awsvpc]
related: ["[[Storage/AWS ECR]]", "[[Compute/AWS EC2]]", "[[Networking/AWS VPC]]", "[[IAM/IAM Roles]]", "[[Observability/AWS CloudWatch]]"]
created: 2026-04-28
updated: 2026-04-28
---

## Overview

Amazon ECS is a fully managed container orchestration service. It runs containers on three infrastructure options — Fargate (serverless), EC2 instances (self-managed), or on-premises (ECS Anywhere) — without requiring you to operate a control plane. The core building blocks are **clusters** (infrastructure grouping), **task definitions** (blueprints), **tasks** (single-run workloads), and **services** (long-running replicated workloads).

## Key Concepts

- **Cluster**: Logical grouping of infrastructure. A cluster can mix Fargate, EC2, and external capacity in a single namespace.
- **Task definition**: Versioned JSON blueprint describing containers, CPU/memory, network mode, IAM roles, volumes, logging, and environment variables. Each new `register-task-definition` call creates an immutable revision.
- **Task**: A running instantiation of a task definition. Single-shot for batch; managed by a service for long-running apps.
- **Service**: Maintains a `desiredCount` of tasks. Replaces failed or unhealthy tasks automatically and integrates with load balancers, service discovery, and auto scaling.
- **Capacity provider**: Links task placement to underlying infrastructure scaling (Fargate, FARGATE_SPOT, or an EC2 Auto Scaling Group).
- **Task IAM role**: Credentials used by application code inside the container to call AWS APIs.
- **Task execution role**: Credentials used by the ECS/Fargate agent to pull images and ship logs — not accessible to application code.

## Launch Types

| Feature | Fargate | EC2 |
|---------|---------|-----|
| Infrastructure management | None | You manage AMI, patching, instance types |
| Billing granularity | Per-task vCPU-second and GB-second | Per-instance-hour |
| Network mode | `awsvpc` only | `awsvpc`, `bridge`, `host` |
| GPU support | No | Yes |
| Cost at scale | Higher per unit | Lower for sustained load |
| Startup time | ~30s | Depends on ASG warm-up |
| Isolation | Task-level kernel isolation | Shared kernel on instance |

**Rule of thumb**: Use Fargate for variable workloads and simplicity; EC2 for GPU, large sustained load, or specialized instance types.

## Task Definitions

### Fargate CPU/Memory Combinations

Only specific combinations are valid — invalid values cause registration to fail:

| CPU (units) | vCPU | Memory range | OS support |
|-------------|------|-------------|------------|
| 256 | 0.25 | 512 MiB, 1–2 GB | Linux |
| 512 | 0.5 | 1–4 GB | Linux |
| 1024 | 1 | 2–8 GB | Linux, Windows |
| 2048 | 2 | 4–16 GB (1 GB increments) | Linux, Windows |
| 4096 | 4 | 8–30 GB (1 GB increments) | Linux, Windows |
| 8192 | 8 | 16–60 GB (4 GB increments) | Linux (platform 1.4.0+) |
| 16384 | 16 | 32–120 GB (8 GB increments) | Linux (platform 1.4.0+) |

Container-level `cpu` and `memory` values must sum to ≤ task-level values. `memory` is a hard limit; `memoryReservation` is a soft limit.

### Key Task Definition Parameters

```json
{
  "family": "my-app",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::123456789012:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::123456789012:role/ecsTaskRole",
  "containerDefinitions": [
    {
      "name": "app",
      "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:latest",
      "essential": true,
      "portMappings": [{ "containerPort": 8080, "protocol": "tcp" }],
      "environment": [{ "name": "ENV", "value": "prod" }],
      "secrets": [
        { "name": "DB_PASSWORD", "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:db-password" }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/my-app",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs",
          "mode": "non-blocking",
          "max-buffer-size": "10m"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
```

**Fargate-specific constraints:**
- `networkMode` must be `awsvpc`
- Only `SYS_PTRACE` Linux capability can be added
- Windows Fargate: port 3150 is reserved; no environment files; no FSx support
- No GPU, Elastic Inference, `host` IPC mode, `disableNetworking`, `links`, or `dnsServers`

## Networking

### Network Modes

| Mode | Fargate | EC2 | Security groups | Use case |
|------|---------|-----|-----------------|----------|
| `awsvpc` | Required | Supported | Per-task | Default for all new workloads |
| `bridge` | No | Yes | Host-level only | Legacy Docker; dynamic port mapping |
| `host` | No | Yes | Host-level only | High-performance; one task per port |

### awsvpc Mode

Each task gets its own ENI with a private IP in the VPC. Security groups are applied at the task level, enabling fine-grained isolation.

**Gotchas:**
- ENI allocation is limited per instance type (typically 2–15 ENIs per instance). Tasks fail with `ResourceInitializationError` when the limit is exhausted — use ENI trunking or Fargate to avoid this.
- VPC must have `enableDnsHostnames = true` and `enableDnsSupport = true` for proper hostname resolution.
- Security groups must allow: inbound from ALB/NLB, outbound to ECR (or use VPC endpoints), outbound to Secrets Manager/SSM for secrets injection.

### Fargate-Specific Networking

- Each task gets one ENI managed by AWS — cannot be manually modified.
- Maximum **5 security groups** and **16 subnets** per task's `awsvpcConfiguration`.
- Platform v1.4.0+ reduces to 1 ENI per task (down from 2), enables EFS, jumbo frames, and complete VPC Flow Log visibility.
- For private subnets, tasks need either a NAT gateway or ECR/S3/Secrets Manager **VPC interface endpoints** to pull images and fetch secrets.
- For IPv6-only mode: requires IPv6 VPC CIDR, IPv6-enabled subnets, DNS64+NAT64 for IPv4 service access. ECS Exec and Windows are not supported.

**DHCP gotcha**: Updating a subnet's DHCP options set does not affect running tasks — start new tasks, then stop old ones.

### Bridge Mode

Containers share the host's docker bridge (`172.17.0.x`). Dynamic port mapping allows multiple tasks per instance but requires ALB (which tracks ephemeral ports) — NLB cannot use dynamic host ports. No task-level security groups.

### Load Balancer Requirements

- Fargate supports **ALB and NLB only** — no Classic Load Balancer.
- Target group `targetType` must be `ip` (not `instance`) for awsvpc/Fargate tasks.
- ALB supports dynamic host port mapping for EC2 bridge mode via target type `instance`.

## IAM Roles

### Task Role vs Execution Role

```
Task Execution Role (ecsTaskExecutionRole)
  └── Used by: ECS agent / Fargate agent
  └── Needs: ecr:GetAuthorizationToken, ecr:BatchGetImage, logs:CreateLogStream, secretsmanager:GetSecretValue

Task IAM Role (application role)
  └── Used by: Your application code inside the container
  └── Needs: Whatever AWS APIs your app calls (S3, DynamoDB, SQS, etc.)
```

**Critical distinction**: The execution role is consumed by infrastructure; the task role is consumed by application code. Never confuse them — a missing execution role breaks image pulls and logging; a missing task role breaks app-level AWS SDK calls.

### Trust Policy (with confused deputy protection)

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ecs-tasks.amazonaws.com" },
    "Action": "sts:AssumeRole",
    "Condition": {
      "ArnLike": { "aws:SourceArn": "arn:aws:ecs:us-east-1:123456789012:*" },
      "StringEquals": { "aws:SourceAccount": "123456789012" }
    }
  }]
}
```

Always include `aws:SourceAccount` (and optionally `aws:SourceArn`) to prevent confused deputy attacks.

### EC2 Security Isolation Warning

On EC2 launch type, containers share the host kernel and **can reach credentials for other tasks** on the same instance via the metadata service. Mitigate with:
- `ECS_AWSVPC_BLOCK_IMDS=true` environment variable (awsvpc mode)
- iptables DROP to `169.254.169.254/32` (bridge mode)

Fargate provides task-level kernel isolation — no cross-task credential leakage.

### Credential Delivery

- Credentials reach application code via the **container credential provider endpoint** (`169.254.170.2:80` on EC2, well-defined interface on Fargate).
- The AWS SDK picks this up automatically — no manual credential configuration needed.
- CloudTrail logs include `taskArn` for per-task audit trails.
- Tasks do **not** need `sts:AssumeRole` to use their own task role; AWS handles the assumption automatically.

## Capacity Providers

Capacity providers decouple task scheduling from infrastructure scaling.

### Types

| Provider | Cost | Interruption risk | Best for |
|----------|------|-------------------|---------|
| `FARGATE` | $$$ | None | Production, unpredictable traffic |
| `FARGATE_SPOT` | $ (~70% off) | 2-min notice | Batch, CI/CD, fault-tolerant async |
| EC2 ASG (managed scaling) | $$ at scale | Low | Sustained load, GPU, large fleets |

### Base and Weight

```json
{
  "capacityProviderStrategy": [
    { "capacityProvider": "FARGATE",      "base": 2, "weight": 1 },
    { "capacityProvider": "FARGATE_SPOT", "base": 0, "weight": 4 }
  ]
}
```

- `base`: Always place this many tasks on this provider first (applied before weights).
- `weight`: Distribute remaining tasks proportionally. Weight 1:4 = 20%/80% split of overflow tasks.
- **Always set a FARGATE base** when mixing with FARGATE_SPOT — provides a stable floor if SPOT capacity is interrupted.

### EC2 Managed Scaling

ECS computes required capacity and drives the ASG — more intelligent than standalone ASG policies since it accounts for actual task CPU/memory requirements:

```json
{
  "managedScaling": {
    "status": "ENABLED",
    "targetCapacity": 80,
    "minimumScalingStepSize": 1,
    "maximumScalingStepSize": 100,
    "instanceWarmupPeriod": 300
  },
  "managedTerminationProtection": "ENABLED"
}
```

`targetCapacity: 80` means ECS targets 80% utilization — it may overprovision to achieve this when tasks are large.

## Services

### Scheduler Behavior

- The service scheduler continuously reconciles `runningCount` → `desiredCount`.
- Before stopping a failing task, it launches a replacement first (subject to `maximumPercent`).
- If tasks repeatedly fail to reach `RUNNING`, the scheduler **throttles launch attempts** to prevent resource waste — monitor service event messages.

### Deployment Strategies

| Type | Mechanism | Zero-downtime | Rollback |
|------|-----------|---------------|---------|
| Rolling update | Controlled by `minimumHealthyPercent` / `maximumPercent` | Yes (with correct config) | Manual (update task def) |
| Blue/green (CodeDeploy) | Dual target groups, weighted shift | Yes | Automatic or manual |
| External | Custom controller | Custom | Custom |

**Deployment circuit breaker**: Automatically rolls back a rolling deployment if a threshold of tasks fail to reach steady state. Enable via `deploymentCircuitBreaker.enable = true` and `rollback = true`.

### Health Checks

Two independent systems:
1. **Container health check** (defined in task definition) — ECS acts on `UNHEALTHY` status.
2. **Load balancer target group health check** — ELB deregisters unhealthy tasks; ECS replaces them.

**`healthCheckGracePeriodSeconds`**: Set this to your app's startup time to prevent the service from killing tasks that are still initializing. Default is 0 — dangerous for slow-starting apps.

### Service Auto Scaling

Adjusts `desiredCount` via AWS Application Auto Scaling. Common policies:
- **Target tracking**: Track ECS metric (CPU, memory utilization, ALB request count per target).
- **Step scaling**: Scale in/out based on CloudWatch alarm thresholds.
- **Scheduled scaling**: Scale ahead of known traffic patterns.

### Service Interconnection

| Method | When to use |
|--------|-------------|
| **Service Connect** | Simple service-to-service within a cluster; zero-config DNS |
| **Service Discovery (Route 53)** | DNS-based, cross-cluster; needs VPC DNS enabled |
| **VPC Lattice** | Multi-account, cross-VPC; adds cost |

## Logging

### awslogs (CloudWatch Logs)

Default log driver; requires execution role with `logs:CreateLogStream` and `logs:PutLogEvents`. Use `mode: non-blocking` (default since June 2025) to prevent log backpressure from blocking the application.

### FireLens

Sidecar log router (Fluent Bit / Fluentd) that can fan out logs to multiple destinations (S3, Kinesis, third-party SIEMs). The sidecar container requires its own task role permissions for FireLens log forwarding.

## Storage

| Volume type | Fargate Linux | Fargate Windows | EC2 | Notes |
|-------------|--------------|-----------------|-----|-------|
| EFS | Yes (platform 1.4.0+) | No | Yes | Shared persistent storage across tasks |
| EBS | Yes | Yes | Yes | Per-task persistent block storage |
| Bind mount | Yes (ephemeral) | Yes (ephemeral) | Yes | Shared between containers in a task; lost on task stop |
| FSx Windows File Server | No | No | Yes | EC2 only |

**EFS with awsvpc**: Enable `transitEncryption = ENABLED` and IAM authorization via an access point for least-privilege EFS access per service.

## Patterns

### Sidecar Pattern

Add a non-essential container (FireLens, Datadog agent, Envoy proxy) alongside the main app container in the same task definition. Sidecars share the task's network namespace and ephemeral storage. Set `essential: false` so a sidecar crash doesn't kill the task.

### Immutable Deployments

Register a new task definition revision for every deployment. Never mutate a running task definition revision. Combine with ECR image tag immutability ([[Storage/AWS ECR]]) for full auditability.

### Private Subnets + VPC Endpoints

Run tasks in private subnets with no internet route. Create interface endpoints for ECR API, ECR DKR (docker), S3 (gateway endpoint), CloudWatch Logs, Secrets Manager, and SSM to keep all traffic on the AWS network.

## Gotchas

- **ENI exhaustion on EC2**: `awsvpc` mode consumes 1 ENI per task per instance. ENI trunking increases limits but requires supported instance types. Check `AvailableCapacity` before scaling up task count.
- **FARGATE_SPOT interruptions**: 2-minute warning via task metadata endpoint and EventBridge event. Apps must handle `SIGTERM` gracefully and finish in-flight work within 120 seconds.
- **Health check grace period**: Default is 0 seconds. Slow-starting apps will be killed and replaced in a loop until you set `healthCheckGracePeriodSeconds` ≥ app startup time.
- **Deployment circuit breaker off by default**: Without it, a broken deployment will continue attempting to launch unhealthy tasks indefinitely.
- **Windows Fargate port 3150**: Reserved by the platform — using it causes task launch failures.
- **Execution role ≠ Task role**: Wrong assignment is the most common ECS IAM mistake. Execution role powers agent infrastructure; task role powers application code.
- **DHCP options on Fargate**: Updating a subnet's DHCP options does not propagate to running tasks — bounce tasks explicitly.
- **Log driver blocking**: The legacy default was `blocking` mode. If the CloudWatch endpoint is slow, the app blocks. Verify `mode: non-blocking` is set, especially on high-throughput services.
- **Service throttling**: Repeated task launch failures cause exponential backoff in the ECS scheduler. Fix the root cause (broken image, misconfigured secrets, missing execution role) — the throttle resets on a service update.
- **EC2 credentials isolation**: Unlike Fargate, EC2 tasks share the host kernel. Without IMDS blocking, any container on the instance can reach the metadata service and other tasks' credentials.

## References

- [[Compute/AWS EC2]]
- [[Storage/AWS ECR]]
- [[IAM/IAM Roles]]
- [[Networking/VPC]]
- [[Observability/AWS CloudWatch]]
