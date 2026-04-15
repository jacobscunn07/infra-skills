---
name: aws-autoscaling
description: Use when working with Amazon EC2 Auto Scaling - designing Auto Scaling Groups, writing scaling policies (target tracking, step, scheduled, predictive), configuring launch templates, instance refresh, lifecycle hooks, warm pools, mixed instance policies, health checks, capacity rebalancing, or any Auto Scaling architecture and troubleshooting decisions
---

# AWS EC2 Auto Scaling Expert Skill

Comprehensive EC2 Auto Scaling guidance covering ASG configuration, scaling policies, launch templates, lifecycle hooks, warm pools, instance refresh, and production patterns. Based on the official AWS EC2 Auto Scaling User Guide.

## When to Use This Skill

**Activate this skill when:**
- Designing or configuring Auto Scaling Groups (min/desired/max)
- Writing or choosing scaling policies (target tracking, step, scheduled, predictive)
- Configuring launch templates or mixed instance policies
- Setting up instance refresh for rolling AMI updates
- Using lifecycle hooks for custom launch/termination logic
- Implementing warm pools for latency-sensitive scale-out
- Combining Spot and On-Demand instances in an ASG
- Configuring health checks (EC2 vs ELB)
- Troubleshooting scaling activities, launch failures, or thrashing

**Don't use this skill for:**
- ECS Service Auto Scaling — different mechanism (Application Auto Scaling)
- DynamoDB or Lambda auto scaling — use Application Auto Scaling skill
- Initial EC2 instance type or purchasing decisions — use aws-ec2 skill

---

## Core Architecture

An Auto Scaling Group has three layers:

| Layer | Component | Purpose |
|-------|-----------|---------|
| **What to run** | Launch Template | AMI, instance type, security groups, IAM role, user data |
| **Where and how many** | Auto Scaling Group | Min/desired/max, AZs, health checks, load balancer |
| **When to change count** | Scaling Policies | Rules that increase or decrease desired capacity |

---

## Auto Scaling Group (ASG) Configuration

### Capacity Bounds

```
min ≤ desired ≤ max

min:     Never go below this (e.g., 2 for HA across AZs)
desired: Current target (ASG works to maintain this)
max:     Never exceed this (cost control)
```

- Set `min ≥ 2` across at least two AZs for production workloads
- Set `max` to a value you're comfortable paying for if scaling runs unchecked
- Scale to zero (`min=0`, `desired=0`) is valid for batch/off-hours workloads

### Availability Zone Balancing

ASG automatically balances instances across configured AZs. If an AZ becomes unhealthy, ASG launches replacements in other AZs. Configure all AZs you want to use — more AZs = more Spot capacity pools and better Spot interruption distribution.

### Health Check Types

| Health Check | What It Tests | Use When |
|-------------|--------------|----------|
| **EC2** (default) | Instance status checks (hypervisor/hardware) | Minimum baseline |
| **ELB** | Load balancer target health check (app responds) | Any ALB/NLB-fronted service |
| **Custom** | Your app marks instance unhealthy via API | Complex readiness signals |

**Always enable ELB health checks** when your ASG is behind a load balancer — EC2 health checks won't catch a crashed app process on an otherwise healthy instance.

Health check grace period (default 300s): gives a new instance time to boot and pass health before ASG considers it unhealthy. Tune this to your actual boot time.

---

## Launch Templates

Always use launch templates (not the legacy launch configurations). They support versioning, mixed instance policies, and all current EC2 features.

### Key Settings

```json
{
  "LaunchTemplateName": "my-app-lt",
  "LaunchTemplateData": {
    "ImageId": "{{resolve:ssm:/my-org/golden-ami/latest}}",
    "InstanceType": "m7g.large",
    "IamInstanceProfile": { "Name": "my-app-instance-profile" },
    "SecurityGroupIds": ["sg-0abc123"],
    "MetadataOptions": {
      "HttpTokens": "required",
      "HttpPutResponseHopLimit": 1
    },
    "BlockDeviceMappings": [{
      "DeviceName": "/dev/xvda",
      "Ebs": { "VolumeType": "gp3", "VolumeSize": 30, "Encrypted": true }
    }],
    "UserData": "<base64-bootstrap-script>"
  }
}
```

**Always set `HttpTokens: required`** (IMDSv2) to prevent SSRF attacks from reading instance credentials.

Reference AMI IDs via SSM Parameter Store (`{{resolve:ssm:...}}`) so instance refresh triggers automatically when you publish a new AMI.

### Versioning

Launch templates are versioned. ASG can pin to `$Latest`, `$Default`, or a specific version. Use `$Default` in the ASG and advance the default version as part of your release process.

---

## Mixed Instance Policies (Spot + On-Demand)

The most cost-effective production pattern. Keeps a floor of On-Demand for reliability, fills the rest with Spot.

```json
{
  "MixedInstancesPolicy": {
    "InstancesDistribution": {
      "OnDemandBaseCapacity": 2,
      "OnDemandPercentageAboveBaseCapacity": 20,
      "SpotAllocationStrategy": "capacity-optimized",
      "SpotInstancePools": 0
    },
    "LaunchTemplate": {
      "LaunchTemplateSpecification": {
        "LaunchTemplateName": "my-app-lt",
        "Version": "$Default"
      },
      "Overrides": [
        { "InstanceType": "m7g.large" },
        { "InstanceType": "m6g.large" },
        { "InstanceType": "m7i.large" },
        { "InstanceType": "m6i.large" },
        { "InstanceType": "m5.large" }
      ]
    }
  }
}
```

- `OnDemandBaseCapacity: 2` — first 2 instances are always On-Demand
- `OnDemandPercentageAboveBaseCapacity: 20` — above the base, 20% On-Demand / 80% Spot
- `SpotAllocationStrategy: capacity-optimized` — picks Spot pools with the most available capacity (minimizes interruptions); prefer over `lowest-price`
- List 4–6 instance types in `Overrides` — diversity dramatically reduces correlated interruptions

**Capacity Rebalancing:** Enable `CapacityRebalance: true` on the ASG. When AWS signals that a Spot instance is at elevated risk, ASG proactively launches a replacement before the interruption, then terminates the at-risk instance cleanly.

---

## Scaling Policies

### 1. Target Tracking (Default Choice)

Maintain a CloudWatch metric at a target value. AWS handles the math — you just set the target.

```json
{
  "PolicyType": "TargetTrackingScaling",
  "TargetTrackingConfiguration": {
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ASGAverageCPUUtilization"
    },
    "TargetValue": 70.0,
    "ScaleOutCooldown": 60,
    "ScaleInCooldown": 300,
    "DisableScaleIn": false
  }
}
```

**Available predefined metrics:**
- `ASGAverageCPUUtilization`
- `ASGAverageNetworkIn` / `ASGAverageNetworkOut`
- `ALBRequestCountPerTarget` (requires load balancer)

For custom metrics (e.g., SQS queue depth per instance), use `CustomizedMetricSpecification`.

**Cooldown guidance:**
- Scale-out cooldown (60s): short so you react to traffic spikes quickly
- Scale-in cooldown (300s): long to avoid thrashing when load oscillates

### 2. Step Scaling

Add or remove a specific number of instances at defined CloudWatch alarm thresholds. More granular than target tracking but more complex to tune.

```
Alarm: CPUUtilization > 60% for 2 periods
  Step: 60–70% → add 1 instance
  Step: 70–90% → add 2 instances
  Step: 90%+   → add 4 instances
```

Use when you need asymmetric scaling (scale out aggressively, scale in slowly).

### 3. Scheduled Scaling

Scale at predetermined times. Good for predictable traffic patterns.

```bash
aws autoscaling put-scheduled-update-group-action \
  --auto-scaling-group-name my-app-asg \
  --scheduled-action-name scale-up-business-hours \
  --recurrence "0 8 * * MON-FRI" \
  --min-size 4 --desired-capacity 8 --max-size 20

aws autoscaling put-scheduled-update-group-action \
  --auto-scaling-group-name my-app-asg \
  --scheduled-action-name scale-down-overnight \
  --recurrence "0 20 * * MON-FRI" \
  --min-size 2 --desired-capacity 2 --max-size 20
```

### 4. Predictive Scaling

ML-based forecasting using historical CloudWatch data. Proactively adds capacity before predicted load increases rather than reacting after the fact. Best for workloads with regular daily or weekly cycles.

Requires at least 24 hours of metric history; improves with more data. Can run in **forecast-only** mode first to validate predictions before enabling actual scaling.

---

## Instance Refresh

Rolling replacement of all instances in an ASG — used to deploy a new AMI or launch template change.

```bash
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name my-app-asg \
  --preferences '{
    "MinHealthyPercentage": 80,
    "InstanceWarmup": 120,
    "CheckpointPercentages": [20, 50, 100],
    "CheckpointDelay": 600
  }'
```

- `MinHealthyPercentage: 80` — keep 80% of instances healthy at all times during refresh
- `InstanceWarmup: 120` — wait 120s after launch before counting a new instance as healthy
- Checkpoints: pause at 20% and 50% replaced, wait 10 minutes each — lets you validate before continuing
- Canary deployment: set `MinHealthyPercentage: 100` and use a small `MaxHealthyPercentage` to replace just one instance first

Refresh can be cancelled with `cancel-instance-refresh` and automatically rolls back if the replacement instance fails health checks.

---

## Lifecycle Hooks

Pause an instance during launch or termination to run custom actions.

```
LAUNCH:
  EC2 pending:wait → [your code runs] → pending:proceed → running
  (e.g., configure app, pull secrets, register with service mesh)

TERMINATE:
  EC2 terminating:wait → [your code runs] → terminating:proceed → terminated
  (e.g., drain connections, flush cache, deregister from discovery)
```

### How to Respond to Hooks

1. Subscribe an SQS queue or Lambda to the lifecycle hook notification
2. Your code performs the action
3. Call `complete-lifecycle-action` with `CONTINUE` or `ABANDON`
   - `CONTINUE` — proceed with launch/termination
   - `ABANDON` — for launch hooks: terminate the new instance; for termination hooks: same as CONTINUE

Default heartbeat timeout: 1 hour. Extend with `record-lifecycle-action-heartbeat` for long-running operations.

**Scale-in protection:** Mark a specific instance as protected from scale-in while it's processing a long job:
```bash
aws autoscaling set-instance-protection \
  --instance-ids i-0abc123 \
  --auto-scaling-group-name my-app-asg \
  --protected-from-scale-in
```

---

## Warm Pools

Pre-initialize instances in a stopped or running state so they're ready to launch quickly on scale-out. Eliminates cold-start latency for apps with long initialization times (e.g., JVM warmup, large model loading).

```bash
aws autoscaling put-warm-pool \
  --auto-scaling-group-name my-app-asg \
  --pool-state Stopped \
  --min-size 2
```

- `Stopped` — instances are initialized and stopped; resume quickly (faster than full boot, no EC2 running cost)
- `Running` — instances are initialized and running; instant scale-out (pay for running instances in pool)
- `Hibernated` — RAM preserved on EBS for even faster resume (requires encrypted root volume)

Use lifecycle hooks with warm pools to pre-configure instances (install app, pull config) before they enter the pool.

---

## Default Instance Warmup

Configure at the ASG level so scaling policies know to wait before counting new instances in metrics:

```bash
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name my-app-asg \
  --default-instance-warmup 180
```

Without this, a new instance appears in CloudWatch metrics immediately — before it's actually serving traffic — causing the scaling policy to think load dropped and potentially triggering premature scale-in.

---

## Termination Policies

Controls which instance gets terminated during scale-in. Default: `Default` (terminates oldest launch configuration, then oldest instance, then closest to billing hour).

Common alternatives:
- `OldestLaunchTemplate` — terminates instances using outdated launch template versions first (useful during instance refresh)
- `NewestInstance` — terminates newest first (canary rollback)
- `ClosestToNextInstanceHour` — maximize use of already-paid compute

---

## Architecture Patterns

### Standard Web Service (Spot + On-Demand)

```
ALB (public subnets)
    │
ASG (private subnets, 3 AZs)
    min=2, desired=4, max=40
    MixedInstancesPolicy:
      OnDemandBase=2, OnDemandPct=20, strategy=capacity-optimized
      Overrides: m7g.large, m6g.large, m7i.large, m6i.large
    Health check: ELB + 300s grace
    Target tracking: ALBRequestCountPerTarget = 1000
    CapacityRebalance: true
```

### Batch Processing (Scale to Zero)

```
SQS queue → EventBridge rule → Lambda → update ASG desired
  OR
ASG + target tracking on SQS ApproximateNumberOfMessagesVisible
  metric math: QueueDepth / RunningInstances = messages-per-instance
  target: 100 messages per instance

min=0, max=50
Lifecycle hook on termination: drain current job before shutdown
Spot only (no On-Demand base)
```

### Blue/Green via Two ASGs

```
ASG Blue (current):  desired=10, weight=100
ASG Green (new):     desired=10, weight=0
  → deploy new AMI to Green
  → instance refresh on Green
  → shift ALB target group weights: Blue=50, Green=50
  → validate → Blue=0, Green=100
  → scale Blue to 0 or delete
```

---

## Security Best Practices

1. **IMDSv2 required** — set `HttpTokens: required` in all launch templates
2. **IAM instance profiles** — never put access keys in user data or environment variables
3. **Encrypt EBS volumes** — enable account-wide EBS encryption default
4. **Private subnets** — ASG instances should not have public IPs; use NAT GW or VPC endpoints
5. **Least-privilege IAM** — instance profile should only have permissions the app actually needs
6. **Pin AMI via SSM** — reference AMI ID from Parameter Store, not hardcoded in launch template

---

## Common Troubleshooting

| Symptom | Likely Cause |
|---------|-------------|
| ASG not scaling out | Scaling policy cooldown active; or max capacity already reached; or CloudWatch alarm not triggering |
| New instances immediately terminated | ELB health check failing — app not ready before grace period expires; increase `HealthCheckGracePeriod` |
| `InsufficientInstanceCapacity` | No On-Demand capacity in AZ — add more instance types to `Overrides` or try additional AZs |
| Instances oscillating (scale in/out repeatedly) | Scale-in cooldown too short; or target metric is noisy — increase `ScaleInCooldown` or smooth the metric |
| Instance refresh stalls | `MinHealthyPercentage` too high for current capacity; or new instances failing health checks — check app logs |
| Lifecycle hook timeout | Your hook processor didn't call `complete-lifecycle-action` within the timeout — increase heartbeat timeout or fix the processor |
| Warm pool instances never launch | Check warm pool `MinSize`; warm pool has its own lifecycle separate from the main ASG |
