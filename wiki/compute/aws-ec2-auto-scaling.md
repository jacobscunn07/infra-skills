---
title: AWS EC2 Auto Scaling
tags: [autoscaling, asg, ec2, scaling, spot, lifecycle, warm-pools, instance-refresh]
related: ["[[Compute/AWS EC2]]", "[[Compute/AWS ECS]]", "[[Observability/AWS CloudWatch]]", "[[Networking/AWS VPC]]"]
created: 2026-04-28
updated: 2026-04-28
---

## Overview

Amazon EC2 Auto Scaling maintains a fleet of EC2 instances by automatically adjusting capacity in response to demand, health failures, or a schedule. It is the primary mechanism for HA, cost optimization (Spot mixing), and zero-downtime deployments (instance refresh) on EC2. An Auto Scaling Group (ASG) is the core resource: it wraps a launch template, scaling policies, health checks, and lifecycle hooks into a single managed fleet.

## Key Concepts

- **Auto Scaling Group (ASG)**: Manages a fleet of EC2 instances across AZs. Defines min/max/desired capacity.
- **Launch template**: Versioned specification for new instances (AMI, instance type, security groups, user data). Always prefer over launch configurations.
- **Launch configuration**: Legacy, immutable. No versioning, no Spot mixing support. Do not use for new ASGs.
- **Scaling policy**: Rule that adjusts `DesiredCapacity` — target tracking, step, simple, scheduled, or predictive.
- **Lifecycle hook**: Intercepts instance launch or termination so custom actions can run before the transition completes.
- **Instance refresh**: Rolling replacement of all ASG instances when a launch template change is applied.
- **Warm pool**: Pre-warmed (stopped) instances ready to join the fleet immediately on scale-out.
- **Mixed instances policy**: Combines multiple instance types and on-demand + Spot in a single ASG.
- **Capacity rebalancing**: Proactively replaces at-risk Spot instances before the 2-minute interruption notice.

## Scaling Policies

### Target Tracking (recommended)
Sets a CloudWatch metric target and lets AWS handle the math. Creates and manages its own CloudWatch alarms automatically.

- **Best for**: CPU, ALB request count per target, SQS backlog, custom metrics.
- Scale-out cooldown: 60 s default. Scale-in cooldown: 300 s default.
- Disable scale-in (`DisableScaleIn`) for volatile workloads that should never shrink automatically.
- Use `ApproximateNumberOfMessagesVisible / DesiredCapacity` for SQS-driven worker fleets.

### Step Scaling
Multiple alarm thresholds trigger different magnitudes of scaling actions. Requires manual CloudWatch alarm creation. Use when response magnitude must be proportional (e.g., CPU 60–70% → +1, 70–80% → +2, >80% → +3). More complex than target tracking — prefer target tracking unless step response is essential.

### Simple Scaling (legacy)
One action per breach. Cooldown period blocks further scaling until it expires. Superceded by step and target tracking.

### Scheduled Scaling
Time-based capacity changes via cron expressions. Timezone-aware. Best for predictable load patterns (e.g., business hours scale-up).

### Predictive Scaling (ML-based)
Forecasts capacity needs using 14+ days of historical CloudWatch metrics. Proactively scales before traffic arrives. Modes:
- **Forecast and scale**: Adjusts capacity based on predictions.
- **Forecast only**: Generate recommendations without changing capacity.

## Instance Refresh

Rolling replacement of ASG instances when the launch template changes (new AMI, updated user data, etc.).

**Key parameters:**
- `MinHealthyPercentage`: % of desired capacity to keep running during refresh (default 90%).
- `InstanceWarmupSeconds`: Grace period before a new instance counts toward capacity.
- `CheckpointPercentages` + `CheckpointDelay`: Pause at specified completion % for validation.
- Auto-rollback: automatically reverts if new instances fail health checks.

**Workflow:**
1. Create a new launch template version.
2. Start instance refresh pointing to the new version.
3. Monitor via console or `describe-instance-refreshes`.
4. Cancel anytime; completed instances retain the new version.

## Lifecycle Hooks

Pause an instance in `pending:wait` (launch) or `terminating:wait` (terminate) while custom actions run.

**Sequence (launch):** `pending` → `pending:wait` → [hook handler executes] → `pending:proceed` → `running`

**Sequence (termination):** `terminating` → `terminating:wait` → [hook handler executes] → `terminating:proceed` → `terminated`

**Key parameters:**
- `HeartbeatTimeout`: Max time in wait state (default 3600 s, max 48 h). Extend with heartbeat calls.
- `NotificationTargetARN`: SNS topic or SQS queue to receive hook notifications.
- `DefaultResult`: `CONTINUE` or `ABANDON` when heartbeat times out.

**Graceful termination pattern:**
1. Receive termination notification (SNS/SQS).
2. Deregister instance from load balancer.
3. Drain in-flight connections.
4. Call `complete-lifecycle-action --lifecycle-action-result CONTINUE`.

## Warm Pools

Pre-warmed instances held in `stopped` state (reduced cost vs running). On scale-out, ASG resumes warm instances rather than launching cold ones — dramatically reduces scale-out latency for apps with long boot times.

- `PoolSize`: Number of instances to keep warm.
- `ReusePreviousInstances`: Return scale-in instances to the pool instead of terminating (cost optimization).
- Instances move: warm pool → `pending:wait` → `pending:proceed` → `running`.
- Lifecycle hooks apply to warm pool transitions separately.

## Mixed Instances Policy

Combines multiple instance types and purchase options (on-demand + Spot) in one ASG.

**Allocation strategies (set `SpotAllocationStrategy`):**
- `price-capacity-optimized` (**recommended**): Lowest cost pools with available capacity, reducing interruption risk.
- `capacity-optimized`: Prioritizes pools with most available capacity (lower interruption rate).
- `lowest-price`: Cheapest Spot pools; highest interruption risk.

**Best practices:**
- Span ≥ 3 instance families (e.g., `m5`, `m6i`, `m7i`) across multiple Spot pools.
- Set on-demand base capacity (e.g., 20–30%) for stability; let Spot handle burst.
- Use attribute-based instance type selection (vCPU/memory min) instead of an explicit allowlist.
- Enable **capacity rebalancing** for Spot instances to get proactive replacement before interruption.

**Instance weighting:** Assign custom capacity unit weights per instance type so ASG tracks logical capacity rather than instance count (e.g., `m5.xlarge = 4`, `m5.large = 2`).

## Health Checks

| Type | What it checks | Use when |
|------|---------------|----------|
| EC2 (default) | Instance system status only | Basic fleet management |
| ELB | Target group health | Instances behind ALB/NLB |
| Custom | Application-defined via API | App-level health not exposed via ELB |

- **Health check grace period** (default 300 s): Prevents premature replacement of slow-starting instances. Set longer for apps with DB migrations or heavy init scripts.
- Unhealthy instances are replaced: `running` → `impaired` → `unhealthy` → `terminating` → replacement launches.

## Termination Policies

Default order: oldest launch configuration → oldest launch template → closest to next billing hour → random.

Custom policies (applied in order specified):
- `OldestInstance`, `NewestInstance`, `OldestLaunchConfiguration`, `OldestLaunchTemplate`
- `ClosestToNextInstanceHour`: Cost-optimized (avoids wasted partial billing hours)
- `AllocationStrategy`: Respects mixed instances strategy (Spot vs on-demand balance)

**Instance scale-in protection:** Mark individual instances so ASG will not terminate them during scale-in. Useful for long-running jobs. Remove protection manually when safe.

## Cooldown Periods

- **Default cooldown** (simple/step scaling): 300 s. Blocks further scaling actions during this window.
- **Target tracking** has separate scale-out (60 s) and scale-in (300 s) cooldowns.
- Set shorter cooldowns (≥ 60 s) only for fast-responding, stateless workloads.
- Warm pools effectively replace cooldown needs for launch latency.

## Patterns

**Target tracking + mixed instances**: Default pattern for web/API tiers. CPU or request-count target, on-demand base + Spot burst, `price-capacity-optimized`, capacity rebalancing enabled.

**SQS worker fleet**: Target tracking on `ApproximateNumberOfMessagesVisible / DesiredCapacity`. Scale to zero by setting min=0 and using scheduled scaling for predictable windows.

**Zero-downtime update**: Launch template version bump → instance refresh with `MinHealthyPercentage=90` and checkpoint at 10% for canary validation.

**Graceful stateful shutdown**: Lifecycle hook on termination → drain connections → call `complete-lifecycle-action`. Combine with ELB deregistration delay on the target group.

**Blue/green with two ASGs**: Two ASGs share one ALB; shift traffic via weighted target groups, then terminate old ASG after confidence period.

## Gotchas

- **Launch configurations are immutable**: Any change requires creating a new one. Use launch templates instead — they support versioning.
- **Desired capacity persists after manual changes**: Manually setting desired capacity via CLI/console overrides scaling policies until the next scaling event.
- **Cooldown interacts with instance refresh**: Ongoing instance refreshes can delay scaling policy reactions. Factor this into grace periods.
- **Mixed instances weight rounding**: ASG rounds up to the nearest weight unit, which can cause desired capacity to exceed the requested value.
- **ELB health checks require attachment**: The ASG must be attached to a target group for ELB health checks to take effect; EC2 checks are used otherwise regardless of configuration.
- **Warm pool instances still incur EBS charges**: Stopped instances do not pay for CPU/RAM but do pay for attached EBS volumes.
- **Predictive scaling needs 14 days of history**: If the metric is too new, predictive scaling can't produce a model.
- **Capacity rebalancing may temporarily exceed max capacity**: ASG briefly launches a replacement before terminating the at-risk Spot instance, exceeding `MaxSize` by up to 10% momentarily.
- **Quotas**: 500 ASGs per region, 5000 launch configurations per region, 5000 launch templates per region.

## References

- [[Compute/AWS EC2]]
- [[Compute/AWS ECS]]
- [[Observability/AWS CloudWatch]]
- [[Networking/AWS VPC]]
