---
name: aws-ecs
description: Use when working with Amazon ECS - designing clusters, writing task definitions, choosing between Fargate and EC2 launch types, configuring services, load balancing, auto scaling, networking (awsvpc/bridge), IAM roles (task role vs execution role), service discovery, deployments, or any ECS architecture and troubleshooting decisions
---

# AWS ECS Expert Skill

Comprehensive Amazon ECS guidance covering architecture, task definitions, services, networking, IAM, auto scaling, and production patterns. Based on the official AWS ECS developer guide.

## When to Use This Skill

**Activate this skill when:**
- Designing ECS cluster architecture (Fargate vs EC2, capacity providers)
- Writing or debugging task definitions
- Configuring ECS services (deployment strategy, health checks, scaling)
- Setting up load balancing for ECS services
- Choosing a network mode (awsvpc, bridge, host)
- Configuring IAM roles for ECS (task role vs execution role)
- Setting up service auto scaling
- Implementing service discovery (Service Connect, Route 53, VPC Lattice)
- Running CI/CD deployments to ECS (blue/green, rolling)
- Troubleshooting container connectivity, task failures, or image pull errors

**Don't use this skill for:**
- EKS (Kubernetes) — different orchestrator
- General Docker or container image questions unrelated to ECS
- EC2 instance management unrelated to ECS clusters

---

## Core Architecture

ECS has three layers:

| Layer | What It Does |
|-------|-------------|
| **Capacity** | Infrastructure where containers run (Fargate, EC2, on-premises) |
| **Controller** | ECS scheduler — places, starts, and monitors tasks |
| **Provisioning** | How you interface with ECS (Console, CLI, CDK, SDK) |

### Key Components

| Component | Description |
|-----------|-------------|
| **Task Definition** | JSON blueprint describing containers, CPU/memory, networking, IAM, volumes |
| **Task** | A running instance of a task definition (one-off or batch) |
| **Service** | Long-running task manager — maintains desired count, replaces failures |
| **Cluster** | Logical grouping of capacity and services |

---

## Launch Types

### Fargate (Serverless) — Default Choice

- AWS manages the underlying compute — no EC2 instances to provision or patch
- Each task gets its own isolated compute environment (separate kernel, CPU, memory, ENI)
- Uses `awsvpc` network mode exclusively
- Must use `ip` target type on load balancer target groups
- Supports Fargate Spot for interruptible, cost-sensitive workloads (~70% cheaper, 2-min interruption warning)
- Pay per vCPU and GB of memory per second

**When to use Fargate:**
- Default for new workloads — less operational overhead
- Variable or unpredictable traffic
- Security-sensitive workloads (stronger isolation)
- Teams without EC2 expertise

### EC2 Launch Type

- You manage EC2 instances in the cluster (type, count, patching)
- Full control over instance type (GPU, high-memory, ARM)
- Supports multiple network modes (awsvpc, bridge, host)
- Container Instance Role required (allows EC2 to register with cluster)
- Better for: consistent high-utilization workloads, GPU containers, Windows containers, custom AMIs

### ECS Anywhere (Hybrid)

- Register on-premises servers or VMs as external instances
- Useful for data-residency requirements or workloads that can't move to cloud

### Capacity Provider Strategy

Preferred over hardcoding launch type — lets you mix Fargate and EC2, or Fargate and Fargate Spot:

```json
"capacityProviderStrategy": [
  { "capacityProvider": "FARGATE",      "weight": 1, "base": 1 },
  { "capacityProvider": "FARGATE_SPOT", "weight": 3, "base": 0 }
]
```
This runs 1 guaranteed Fargate task, then places 3x as many on Spot.

---

## Task Definitions

Task definitions are versioned JSON documents. Each new registration creates a new revision; old revisions remain available.

### Critical Parameters

```json
{
  "family": "my-app",
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc",
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::ACCOUNT:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::ACCOUNT:role/my-app-task-role",
  "containerDefinitions": [
    {
      "name": "my-app",
      "image": "123456789.dkr.ecr.us-east-1.amazonaws.com/my-app:latest",
      "portMappings": [{ "containerPort": 8080, "protocol": "tcp" }],
      "essential": true,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/my-app",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "secrets": [
        { "name": "DB_PASSWORD", "valueFrom": "arn:aws:secretsmanager:..." }
      ]
    }
  ]
}
```

### Fargate CPU/Memory Valid Combinations

| CPU (units) | Valid Memory |
|-------------|-------------|
| 256 (.25 vCPU) | 512 MB – 2 GB |
| 512 (.5 vCPU) | 1 GB – 4 GB |
| 1024 (1 vCPU) | 2 GB – 8 GB |
| 2048 (2 vCPU) | 4 GB – 16 GB |
| 4096 (4 vCPU) | 8 GB – 30 GB |
| 8192 (8 vCPU) | 16 GB – 60 GB |
| 16384 (16 vCPU) | 32 GB – 120 GB |

### Container Restart Policy

Configure per-container so a sidecar crash doesn't kill the whole task:
```json
"restartPolicy": {
  "enabled": true,
  "ignoredExitCodes": [0],
  "restartAttemptPeriod": 300
}
```

---

## IAM Roles — The Most Common Source of Confusion

ECS uses three distinct roles. Mixing them up causes the most common permission errors.

### Task Execution Role
**Who uses it:** The ECS agent (not your code)
**Purpose:** Allows ECS to do setup work on your task's behalf

Required permissions for common scenarios:
```
ecr:GetAuthorizationToken          — always needed for ECR images
ecr:BatchCheckLayerAvailability    — always needed for ECR images
ecr:GetDownloadUrlForLayer         — always needed for ECR images
ecr:BatchGetImage                  — always needed for ECR images
logs:CreateLogStream               — needed for awslogs driver
logs:PutLogEvents                  — needed for awslogs driver
secretsmanager:GetSecretValue      — needed if task def references Secrets Manager
ssm:GetParameters                  — needed if task def references SSM Parameter Store
kms:Decrypt                        — needed if secrets are encrypted with custom KMS key
```

The AWS managed policy `AmazonECSTaskExecutionRolePolicy` covers ECR + CloudWatch Logs.

### Task Role
**Who uses it:** Your application code inside the container
**Purpose:** Allows your app to call AWS services

Example: an app that reads from S3 and writes to DynamoDB needs:
```
s3:GetObject, s3:PutObject
dynamodb:GetItem, dynamodb:PutItem
```

> **Rule:** Task execution role = ECS infrastructure needs. Task role = your app's needs.

### EC2 Container Instance Role
**Who uses it:** The EC2 instance running ECS agent (EC2 launch type only)
**Purpose:** Allows the instance to register with the ECS cluster

Use AWS managed policy: `AmazonEC2ContainerServiceforEC2Role`

---

## Networking

### Network Modes

| Mode | Launch Type | Description | Use Case |
|------|-------------|-------------|----------|
| **awsvpc** | Fargate + EC2 | Task gets its own ENI with private IP | Recommended for all new workloads |
| **bridge** | EC2 only | Docker bridge network with dynamic port mapping | Legacy EC2 workloads |
| **host** | EC2 only | Task shares host's network stack directly | Max network performance, one task per instance |
| **none** | EC2 only | No external connectivity | Fully isolated batch jobs |

### awsvpc Mode (Recommended)

- Each task gets its own Elastic Network Interface (ENI)
- Apply Security Groups directly to tasks (not just EC2 instances)
- Supports both IPv4 and IPv6
- Required for Fargate; strongly recommended for EC2
- Load balancer target group must use `ip` target type (not `instance`)

**ENI limits per instance** (EC2 launch type): limited by instance type. Enable ENI trunking for higher task density.

### Security Groups for ECS Tasks (awsvpc)

With `awsvpc`, security groups apply at the task level:
```
ALB SG  → Task SG: allow containerPort (e.g., 8080)
Task SG → RDS SG:  allow 5432
Task SG → 0.0.0.0/0: allow 443 (for ECR image pull, Secrets Manager, etc.)
```

If tasks are in private subnets without a NAT Gateway, use VPC Interface Endpoints for ECR, CloudWatch Logs, Secrets Manager, and SSM.

---

## Services

### Deployment Strategies

| Strategy | Description | Best For |
|----------|-------------|----------|
| **Rolling update** | Gradually replace old tasks with new | Default; most workloads |
| **Blue/Green (CodeDeploy)** | New tasks fully up before traffic shifts; instant rollback | Zero-downtime deploys |
| **External** | You control the deployment logic | Custom CI/CD |

**Rolling update key parameters:**
```json
"deploymentConfiguration": {
  "minimumHealthyPercent": 100,
  "maximumPercent": 200,
  "deploymentCircuitBreaker": {
    "enable": true,
    "rollback": true
  }
}
```
- `minimumHealthyPercent: 100` + `maximumPercent: 200` = double capacity during deploy, no downtime
- Circuit breaker: auto-rolls back if new tasks fail health checks repeatedly

### Load Balancing

| ALB | NLB | GLB |
|-----|-----|-----|
| HTTP/HTTPS (L7) | TCP/UDP (L4) | Virtual appliances |
| Path/host routing | Ultra-low latency | Firewalls, IDS/IPS |
| Most common choice | gRPC, WebSocket | Specialized use |

**ALB target group config for ECS:**
- Target type: `ip` (required for awsvpc)
- Health check: match your app's health endpoint (e.g., `/health`)
- Deregistration delay: tune down (e.g., 30s) for faster deploys if your app drains quickly

### Service Discovery

| Option | Mechanism | Cost | Use Case |
|--------|-----------|------|----------|
| **Service Connect** | ECS-managed proxy, short names | Free | Recommended default |
| **Service Discovery (Route 53)** | DNS A/SRV records | Route 53 fees | DNS-based discovery |
| **VPC Lattice** | Managed app networking | Additional cost | Multi-account/VPC mesh |

**Service Connect** is the easiest — services reference each other by short name (e.g., `http://backend:8080`) without managing DNS or load balancers.

---

## Auto Scaling

ECS Service Auto Scaling uses Application Auto Scaling under the hood.

### Scaling Policy Types

| Type | How It Works | Best For |
|------|-------------|----------|
| **Target Tracking** | Maintain a target metric value (e.g., 70% CPU) | Default choice — simplest |
| **Step Scaling** | Add/remove N tasks at defined CloudWatch alarm thresholds | Faster reaction to spikes |
| **Scheduled** | Scale at specific times | Predictable traffic patterns |
| **Predictive** | ML-based on historical patterns | Daily/weekly traffic cycles |

### Target Tracking Example (recommended)

```json
{
  "TargetValue": 70.0,
  "PredefinedMetricSpecification": {
    "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
  },
  "ScaleOutCooldown": 60,
  "ScaleInCooldown": 300
}
```

**Available predefined metrics:**
- `ECSServiceAverageCPUUtilization`
- `ECSServiceAverageMemoryUtilization`
- `ALBRequestCountPerTarget`

### Cooldown Guidance
- **Scale-out cooldown:** Keep short (30–60s) so you react to traffic spikes quickly
- **Scale-in cooldown:** Keep longer (300s) to avoid thrashing when load oscillates

### Scale to Zero
Set `minimumCapacity: 0` to scale services completely down during off-hours. Scale-out triggers on the first data point above zero.

---

## Logging

Always configure `awslogs` log driver — it's the simplest and most reliable:

```json
"logConfiguration": {
  "logDriver": "awslogs",
  "options": {
    "awslogs-group": "/ecs/my-service",
    "awslogs-region": "us-east-1",
    "awslogs-stream-prefix": "ecs",
    "awslogs-create-group": "true"
  }
}
```

Execution role needs `logs:CreateLogStream` and `logs:PutLogEvents`.

For structured logging at scale, consider sending to Kinesis Data Firehose → S3 via the `awsfirelens` log driver with a Fluent Bit sidecar.

---

## Architecture Patterns

### Standard Fargate Web Service
```
Internet
    │
    ALB (public subnets)
    │   Target type: ip
    │
ECS Service (private subnets)
    │   Network mode: awsvpc
    │   Security group: allow 8080 from ALB SG
    │
    ├── RDS (isolated subnets, allow 5432 from task SG)
    └── ElastiCache (isolated subnets, allow 6379 from task SG)
```

### Fargate + Fargate Spot (Cost Optimized)
```
Capacity provider strategy:
  FARGATE      weight=1  base=1   (1 guaranteed on-demand task)
  FARGATE_SPOT weight=3  base=0   (3x preference for Spot)

Use when: stateless services that handle interruption gracefully
Savings: ~50-70% on compute cost
Requirement: tasks must handle SIGTERM within 2 minutes
```

### Sidecar Pattern (Fargate)
```json
"containerDefinitions": [
  { "name": "app",     "essential": true,  "image": "my-app" },
  { "name": "fluentbit", "essential": false, "image": "fluent/fluent-bit" }
]
```
Mark sidecars `essential: false` so a sidecar crash doesn't kill the main container.

### Private Subnet with No NAT Gateway (VPC Endpoints)
Required endpoints for Fargate tasks in private subnets without NAT:
```
com.amazonaws.REGION.ecr.api        (Interface)
com.amazonaws.REGION.ecr.dkr        (Interface)
com.amazonaws.REGION.logs           (Interface)
com.amazonaws.REGION.secretsmanager (Interface)
com.amazonaws.REGION.ssm            (Interface)
com.amazonaws.REGION.s3             (Gateway — for ECR layer pulls)
```

---

## Security Best Practices

1. **One task role per service** — least-privilege, no shared roles across services
2. **Never store secrets in environment variables** — use `secrets` in task definition (pulls from Secrets Manager or SSM at launch)
3. **Use awsvpc network mode** — apply security groups at the task level, not instance level
4. **Private subnets for tasks** — only the ALB should be in public subnets
5. **Enable Container Insights** — CloudWatch Container Insights for task-level CPU/memory metrics
6. **Pin image tags in production** — avoid `latest`; use digest (`image@sha256:...`) or immutable ECR tags
7. **Enable ECR image scanning** — catch vulnerabilities before images reach production
8. **Fargate for multi-tenant** — stronger isolation than EC2 (separate kernel per task)

---

## Common Troubleshooting

### Task fails to start

| Symptom | Likely Cause |
|---------|-------------|
| `CannotPullContainerError` | Execution role missing ECR permissions, or no route to ECR (missing NAT/VPC endpoint) |
| `ResourceInitializationError` | Secrets Manager/SSM fetch failed — check execution role and VPC connectivity |
| Task stops immediately (exit code 0) | App process exiting — check CloudWatch Logs for application errors |
| Task stops immediately (exit code 1) | App crash — check CloudWatch Logs |
| `AGENT` stopped reason | ECS agent issue on EC2 instance — check instance IAM role |

### Service stuck in deployment

| Symptom | Likely Cause |
|---------|-------------|
| New tasks starting but old never draining | Health check failing — check ALB target group health check path/port |
| `(service) is unable to consistently start tasks` | Circuit breaker triggered — new task definition is broken |
| Tasks healthy but count oscillating | Auto scaling + cooldown misconfigured |
| Deployment never completes | `minimumHealthyPercent: 100` + insufficient cluster capacity |

### Connectivity issues

1. Check task security group allows traffic on `containerPort` from source (ALB SG or other task SG)
2. Check NACL on task's subnet allows inbound on `containerPort` and outbound on ephemeral ports (32768–60999)
3. With awsvpc: confirm target group target type is `ip`, not `instance`
4. Check the task's route table — does it have a path to ECR, Secrets Manager, etc. (NAT GW or VPC endpoint)?
5. Enable VPC Flow Logs to confirm ACCEPT/REJECT at the network layer
