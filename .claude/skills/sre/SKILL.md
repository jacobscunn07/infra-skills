---
name: sre
description: Use when working on Site Reliability Engineering topics - designing SLIs/SLOs/SLAs, error budgets, on-call rotations, incident management, postmortem culture, toil elimination, monitoring strategy (four golden signals), cascading failure prevention, load shedding, release engineering, or any reliability architecture and troubleshooting decisions. Based on the Google SRE Book.
---

# SRE Expert Skill

Comprehensive Site Reliability Engineering guidance covering reliability principles, observability, incident management, and production practices. Based on the [Google SRE Book](https://sre.google/sre-book/table-of-contents/).

## When to Use This Skill

**Activate this skill when:**
- Designing or reviewing SLIs, SLOs, or SLAs
- Calculating and managing error budgets
- Setting up or improving on-call rotations and runbooks
- Managing or reviewing an active incident
- Writing or reviewing postmortems
- Reducing toil through automation
- Designing monitoring and alerting strategy
- Architecting for reliability: load shedding, graceful degradation, retry logic
- Preventing or recovering from cascading failures
- Planning a safe production release or rollout strategy
- Reviewing operational readiness of a new service

**Don't use this skill for:**
- Provider-specific monitoring configuration (use aws-cloudwatch skill instead)
- Infrastructure provisioning unrelated to reliability (use terraform, aws-ec2, etc.)
- Application performance profiling at the code level

---

## Part I: Foundations

### What Is SRE?

SRE is what happens when you ask a software engineer to design an operations team. — Benjamin Treynor Sloss, founder of Google SRE

SRE applies software engineering discipline to operations. Rather than manual sysadmin work, SREs automate operational tasks away. The structural difference from traditional ops:

| Traditional Ops | SRE |
|-----------------|-----|
| Team size scales linearly with service complexity | Team size scales sublinearly |
| Dev and ops have opposing incentives | Shared incentives via error budgets |
| Stability through change gates | Stability through automation and measurement |
| 100% uptime goal | Explicit reliability targets with managed risk |

**Staffing model:** ~50% software engineers, ~50% specialists who can automate. The high hiring bar keeps teams small relative to scope.

### The 50% Rule

SREs spend no more than **50% of their time on operational work** (on-call, tickets, manual tasks). The remaining 50% must be engineering work — building systems that reduce future burden.

If operational load exceeds 50%, excess work is redirected back to the product development team. This creates a structural incentive for developers to ship reliable software.

Maximum on-call load: **25% of total time** — broken down as primary + secondary rotations within the 50% ops cap.

---

## Part II: Service Level Objectives

### SLI / SLO / SLA Definitions

**SLI (Service Level Indicator):** A quantitative measurement of service behavior.

Common SLIs by service type:

| Service Type | Primary SLIs |
|-------------|-------------|
| User-facing serving | Availability, latency (p50/p99), error rate |
| Storage | Latency, availability, durability |
| Big data / pipelines | Throughput, end-to-end latency |
| All services | Availability |

**SLO (Service Level Objective):** A target or range for an SLI.

```
SLI ≤ target
lower bound ≤ SLI ≤ upper bound

Examples:
  99.9% of requests complete in < 200ms (measured over 28 days)
  99.95% availability over rolling 30-day window
  Error rate < 0.1% over any 1-hour window
```

**SLA (Service Level Agreement):** An explicit contract with consequences for missing SLOs (rebates, penalties, credits). If there's no stated consequence, it's an SLO, not an SLA.

Key distinction: **SLOs are internal commitments. SLAs are external contracts.**

### Setting SLOs

**Start with what users care about, not what's easy to measure.**

Good SLO targets:
- User-visible symptoms, not internal health checks
- Based on user research or historical data, not aspirational guesses
- Achievable — avoid perfection targets like 100%
- Minimal — a small set that drives real prioritization decisions

**Avoid these pitfalls:**
- Defaulting to current performance without reflection
- Using averages — they hide tail behavior; use percentiles (p95, p99)
- Setting too many SLOs — every SLO you add is a commitment you must honor

**Safety margins:** Set internal SLOs tighter than advertised ones. If you promise 99.9%, operate to 99.95% internally. This provides buffer before customer-visible violations.

**Deliberate under-performance:** If actual performance significantly exceeds stated SLOs, users form implicit dependencies on better-than-promised reliability. Controlled degradation or throttling can reset expectations appropriately.

### Error Budgets

The error budget is the gap between your SLO and 100% reliability.

```
SLO: 99.9% availability
Error budget: 0.1% = ~43.8 minutes/month of allowed downtime
```

Error budgets transform reliability from a political negotiation into an objective metric both product and SRE teams accept. Key properties:

- **Budget remaining → ship faster.** Teams can take more risk on releases.
- **Budget exhausted → slow down.** Product team becomes self-policing.
- **Budget tracks against quarterly burn rate.** A partial outage consumes partial budget.

This aligns incentives: developers want the budget to spend; SREs want to preserve it. Both need reliability to serve feature velocity.

---

## Part III: Monitoring and Alerting

### The Four Golden Signals

If you can only measure four metrics for a user-facing system, use these:

| Signal | Definition | Examples |
|--------|-----------|---------|
| **Latency** | Time to service a request. Separate successful from error latencies. | p99 HTTP response time, DB query time |
| **Traffic** | Demand on the system | HTTP RPS, messages/sec, active connections |
| **Errors** | Rate of failed requests (explicit or implicit) | 5xx rate, failed transactions, SLO violations |
| **Saturation** | How full is the most constrained resource | CPU%, memory%, queue depth, disk I/O % |

Saturation is the leading indicator — systems often degrade before errors appear. Monitor the resource that will run out first.

### Alerting Philosophy

Every alert should require **urgent, human action**. If an alert doesn't need immediate human response, it shouldn't page.

| Alert type | Response | Routing |
|-----------|----------|---------|
| **Pages** | Requires immediate action, wakes people up | PagerDuty / on-call |
| **Tickets** | Needs attention within a day | Issue tracker |
| **Logging** | Informational, no action needed | Dashboards / logs |

Downgrade anything that frequently fires but requires no action. Alert fatigue kills response quality.

**Symptoms vs. causes:**
- Alert on **symptoms** (user-visible problems): high error rate, slow responses, data unavailability
- Investigate **causes** (internal signals): high CPU, low memory, slow DB queries
- Cause-based alerts create noise; symptom-based alerts create urgency

**White-box vs. black-box monitoring:**
- **Black-box:** Tests externally visible behavior; catches active, user-impacting problems
- **White-box:** Inspects system internals; useful for diagnosis but should not drive pages

### Monitoring Design Principles

1. Every page should be **actionable** — humans take a specific action, not just read and dismiss
2. Every page should be **urgent** — if it can wait until morning, it shouldn't page
3. Alerts should represent **novel problems** — known conditions should be automated away
4. The monitoring system interprets data; **humans should not read alerts to decide whether to act**

---

## Part IV: On-Call

### Structuring On-Call Rotations

Minimum team size for 24/7 coverage:
- **Single-site team:** 8 engineers (primary + secondary rotations)
- **Multi-site team:** 6 engineers per site

Response time requirements by service criticality:

| Service type | Response SLA |
|-------------|-------------|
| User-facing production | 5 minutes |
| Internal infrastructure | 30 minutes |

Match response SLA to your service's availability target. A 99.99% service has ~13 minutes/quarter of allowed downtime; that forces a 5-minute response.

### Incident Volume Targets

| Metric | Target |
|--------|--------|
| Pages per 12-hour shift | ≤ 2 incidents |
| Time per incident (response + postmortem) | ~6 hours |
| Ops work as % of SRE time | ≤ 50% |
| On-call pages as % of SRE time | ≤ 25% |

If pages exceed these targets, reduce alert noise — don't add more on-call engineers as the first response.

### Managing Cognitive Load

On-call engineers face time pressure and incomplete information. Reduce stress to preserve rational decision-making:

- Maintain **clear escalation paths** — engineers should never wonder who to call
- Keep **runbooks current** — a prepared response is ~3× faster than ad-hoc
- Run **Wheel of Misfortune** drills — role-play historical incidents with new engineers
- Conduct **blameless postmortems** — psychological safety enables honest retrospectives

**Operational underload is also a risk.** Engineers who rarely touch production systems lose the intuition needed to respond effectively. Ensure every SRE engages with production quarterly at minimum.

---

## Part V: Incident Management

### When to Declare an Incident

Declare if **any** of these apply:
- A second team's involvement is needed
- The issue is customer-visible
- The problem remains unresolved after one hour of focused effort

Declare early. Undeclared incidents waste time and diffuse accountability.

### Incident Command Structure

Based on the **Incident Command System (ICS)**:

```
Incident Commander (IC)
├── Operations Lead         # only role modifying production systems
├── Communications Lead     # external and stakeholder updates
└── Planning Lead           # tracks deviations, files bugs, handles handoffs
```

**Incident Commander responsibilities:**
- Maintains high-level incident state
- Assigns and delegates specific responsibilities
- Removes blockers for the response team
- Holds all undelegated roles

**Critical rule:** Only the Operations Lead modifies production systems during an incident. Others diagnose, communicate, and coordinate.

### Incident Lifecycle

```
1. Triage        — Assess severity. Stabilize before investigating.
2. Coordinate    — Declare incident, assign roles, open incident document
3. Mitigate      — Stop the bleeding (rollback, reroute, shed load)
4. Investigate   — Root cause analysis
5. Communicate   — Periodic updates every 30 minutes minimum
6. Resolve       — Confirm system health, document timeline
7. Postmortem    — Within 24–48 hours
```

**First instinct trap:** When a major outage hits, the instinct is to start troubleshooting. **Resist it.** Stabilize the service first. Preserve evidence. Then investigate.

### Handoffs

Explicit verbal handoff with acknowledgment:

> "You're now the Incident Commander, okay?"

Await firm acknowledgment before the outgoing IC leaves. Implicit handoffs cause gaps in situational awareness.

### Incident Document Template

Every incident should have a live, collaborative document containing:

```
Title: [SERVICE] — [SYMPTOM]
Status: Investigating / Mitigating / Resolved
Severity: SEV1 / SEV2 / SEV3
IC: [Name]
Comms: [Name]
Start time: [UTC]
Detection: [How was it found?]

Timeline:
  HH:MM — [Action/observation]

Current hypothesis:
  [What we think is happening]

Actions taken:
  [What has been done]

Open questions:
  [What we don't know yet]

Customer impact:
  [What users are experiencing]
```

---

## Part VI: Postmortems

### Philosophy

Writing a postmortem is not punishment — it is a learning opportunity.

Postmortems are blameless. They assume participants acted with good intent given available information. Blame cultures suppress incident reporting and prevent systemic fixes.

> "You can't 'fix' people, but you can fix systems and processes to better support people making the right choices."

### When to Write a Postmortem

Required triggers:
- User-visible service disruption exceeding defined thresholds
- Any data loss event
- On-call engineer intervention (rollback, traffic reroute)
- Resolution time exceeding organizational limits
- Monitoring system failure

### Postmortem Structure

```markdown
## Incident Summary
One paragraph: what happened, when, user impact, resolution.

## Timeline
Chronological list of events, detections, actions, and resolution.

## Root Cause(s)
The underlying conditions that enabled the incident.
Use "5 Whys" — don't stop at the proximate cause.

## Contributing Factors
Secondary conditions that made the incident worse.

## Impact
Quantified: duration, % of users affected, error budget consumed.

## What Went Well
Actions that limited the blast radius.

## What Could Be Improved
Gaps in process, tooling, documentation, or monitoring.

## Action Items
| Action | Owner | Due Date |
|--------|-------|----------|
| Add alert for X | @name | YYYY-MM-DD |
| Update runbook for Y | @name | YYYY-MM-DD |
```

### Blameless Root Cause Analysis

Use the **5 Whys** technique, but stop when you reach systemic factors:

```
Incident: Database became unavailable
Why? → Primary instance ran out of disk space
Why? → Write-ahead logs accumulated over 7 days
Why? → Log rotation job had been silently failing
Why? → Job failure was not monitored or alerted on
Why? → No standard for monitoring cron job health

Root cause: No organizational standard for monitoring scheduled jobs
Action: Add cron job monitoring to service checklist
```

The last "why" should point to a system or process improvement, not a person's mistake.

### Postmortem Culture Practices

- Monthly postmortem highlight emails to the org
- Postmortem reading clubs with cross-functional attendance
- Wheel of Misfortune drills for new engineers
- Visible recognition from leadership for high-quality postmortems

---

## Part VII: Eliminating Toil

### Definition of Toil

Toil is **manual, repetitive, automatable, tactical, devoid of enduring value, and scales linearly with service growth**.

Toil is NOT simply unpleasant work. Running a novel, complex investigation the first time is not toil. Running it the tenth time without automating it is.

**Identifying toil — all five must apply:**

| Trait | Test |
|-------|------|
| Manual | Requires direct human hands-on effort |
| Repetitive | Performed multiple times, not a novel problem |
| Automatable | A machine could do it equally well |
| Tactical | Interrupt-driven, not strategy-driven |
| No enduring value | Service state unchanged after completion |

### Toil Budget

Keep toil below 50% of SRE time. Track it explicitly — teams that don't measure toil can't reduce it.

Common toil sources:

- Responding to alerts that don't require action
- Manual capacity provisioning
- Running deployments by hand
- Applying the same config change across many services
- Responding to user access requests that could be self-service
- Manually restarting failed jobs

### Elimination Strategies

1. **Automate the task** — write code that does what you do manually
2. **Fix the underlying cause** — eliminate the failure condition producing the manual response
3. **Push to product team** — if a service generates too much operational load, it's a product quality issue
4. **Design for self-service** — user access requests, config changes, common operations

Target: **services that grow by an order of magnitude with zero additional operational work**.

---

## Part VIII: Release Engineering

### Core Principles

**Self-service releases:** Teams manage their own release processes through automated tools. Release engineering should not be a bottleneck or a team you wait on.

**High velocity:** Frequent, small releases are safer than infrequent large ones. Fewer changes between versions means easier testing and faster rollback.

**Hermetic builds:** The same source revision must produce identical binaries regardless of build machine, time of day, or external state. Isolate builds from external dependencies.

### Deployment Strategies

| Strategy | Use When |
|----------|----------|
| **Push on Green** | Internal/dev services; deploy every build passing tests |
| **Canary** | Validate on a small % of production traffic before full rollout |
| **Cluster-by-cluster** | Large user-facing services; roll forward one cluster at a time |
| **Multi-day regional rollout** | Critical infrastructure; days between each geography |

**Canary pattern:**
```
1. Deploy to 1% of instances/traffic
2. Monitor golden signals for a bake period (hours to days)
3. If clean: expand to 10% → 50% → 100%
4. If degraded: roll back immediately; bake period catches issues before full impact
```

**Config vs. binary separation:** Decouple feature flags and configuration from binary deploys. This enables rapid flag changes without full redeployment and safer rollbacks (revert config, not binary).

### Safety Checklist for Releases

- [ ] Automated tests pass (unit, integration, load)
- [ ] Canary deployment validated on real traffic
- [ ] Rollback plan documented and tested
- [ ] Monitoring and alerts in place before rollout
- [ ] Capacity provisioned for new version's resource profile
- [ ] Config changes staged separately from binary changes
- [ ] On-call team notified of release window

---

## Part IX: Reliability Architecture

### Cascading Failure Prevention

A cascading failure expands progressively — one component fails, increasing load on others, triggering their failure.

**Primary causes:**

| Cause | Description |
|-------|-------------|
| **Traffic redirection** | Cluster A goes down; traffic shifts to B, C; they overload and fail |
| **CPU exhaustion** | Requests slow, in-flight count rises, threads saturate |
| **Memory exhaustion** | GC thrashing creates a "GC death spiral" consuming more CPU |
| **Thread starvation** | Health checks fail from thread pool exhaustion; system marked unhealthy; cascades |

**Prevention patterns:**

1. **Load test to failure.** Understand the breaking point before production does.
2. **Provision N+2.** Never be one failure away from cascading.
3. **Small queues.** Keep queue depth ≤ 50% of thread pool. Reject early rather than queue indefinitely.
4. **Deadline propagation.** Set an absolute deadline at the frontend; propagate remaining time to all downstream RPCs. Abandon work that can't complete before the deadline.
5. **Circuit breakers.** Stop calling a downstream when it's clearly unhealthy; fail fast rather than pile on.

### Load Shedding and Graceful Degradation

**Load shedding:** Return `HTTP 503` or reduced-quality responses when overloaded rather than crashing.

**Graceful degradation:** Serve diminished results rather than no results.

```
Full mode:     Query all 10 database shards, return complete result
Degraded mode: Query 3 shards, return partial result with "results may be incomplete" notice
Emergency:     Return cached results from 60 seconds ago
```

### Request Criticality Tiers

Assign criticality to every request type. Shed lower tiers first under load:

| Tier | Description | Example |
|------|-------------|---------|
| `CRITICAL_PLUS` | Never shed; small volume | Payment processing |
| `CRITICAL` | Shed only under extreme load | Core user-facing reads |
| `SHEDDABLE_PLUS` | Shed when capacity < 80% | Non-critical writes, analytics |
| `SHEDDABLE` | Always first to shed | Background jobs, batch exports |

Backends reject lower tiers first. Never reject a higher tier while accepting a lower one.

### Retry Logic

Naive retries amplify load. Safe retry patterns:

```
Per-request retry limit:    3 attempts max
Per-client retry budget:    ≤ 10% of total requests retried
Backoff:                    Randomized exponential (jitter prevents thundering herd)
Retry scope:                Only retriable errors (5xx, timeouts; NOT 4xx)
```

**Retry amplification:** If service A retries 3×, and it calls B which retries 3×, and B calls C which retries 3×, a single user request can generate 27 backend calls. Use retry budgets at each layer.

### Recovering from Cascading Failure

```
1. Add capacity — spin up more instances if possible
2. Disable non-critical load — drop batch jobs, background work
3. Temporarily disable failing health checks — prevent restart loops
4. Drop traffic aggressively — reduce to ~1% of normal load
5. Gradually ramp — increase load 10% at a time with stabilization bake periods
```

---

## Part X: Troubleshooting

### Framework: Hypothetico-Deductive Method

```
Observe → Hypothesize → Test → Treat
```

Never skip triage. Stabilize before investigating.

### Five Steps

```
1. Problem Report    — Document: what was expected? what happened? how to reproduce?
                       Log in a searchable system immediately.

2. Triage            — How severe? Who is affected? Mitigate first, investigate second.
                       "Ignore the instinct to troubleshoot — stop the bleeding first."

3. Examine           — Metrics, logs, traces. Recent changes. System state.
                       What changed? When? Who deployed what?

4. Diagnose          — Form hypotheses. Simplify. Bisect. Ask "what, where, why."
                       Eliminate causes as fast as possible.

5. Test & Treat      — Validate each hypothesis with a targeted test.
                       Document findings. Apply fix. Verify resolution.
```

### Diagnostic Techniques

**Bisection:** Split the system in half. Is the problem in the first half or the second? Recurse until isolated.

**Simplify and reduce:** Test individual components with known-good inputs to isolate failure scope.

**Change analysis:** Check every deployment, config change, and load pattern shift in the past 24–48 hours before digging into code.

**Correlation ≠ causation:** Two metrics moving together does not prove one caused the other. Test it.

### Common Pitfalls

| Pitfall | Mitigation |
|---------|-----------|
| Assuming past causes are current causes | Always re-examine the current incident independently |
| Stopping at the first plausible explanation | Continue testing until the hypothesis is confirmed |
| Ignoring multiple contributing factors | Complex systems fail from combinations, not single causes |
| Not documenting investigation steps | Future postmortem and knowledge base lose valuable signal |
| Jumping to fix before confirming root cause | Fixes applied to wrong root causes don't work and waste time |

---

## Architecture Patterns

### Service Reliability Checklist (Pre-Launch)

```
SLOs
  [ ] SLIs defined for user-facing behavior
  [ ] SLO targets set with error budget calculated
  [ ] SLA drafted if external-facing
  [ ] Error budget policy documented

Monitoring
  [ ] Four golden signals instrumented
  [ ] Dashboards for all critical SLIs
  [ ] Alerts for SLO-threatening conditions
  [ ] No alerts without runbook entries
  [ ] Black-box monitoring from external endpoints

On-Call
  [ ] Runbook for every page
  [ ] Escalation path defined
  [ ] On-call rotation staffed with minimum 6–8 engineers
  [ ] Incident management process documented

Resilience
  [ ] Load tested to failure; breaking point known
  [ ] Graceful degradation implemented
  [ ] Request criticality tiers assigned
  [ ] Retry limits and backoff configured
  [ ] Cascading failure scenarios modeled

Release
  [ ] Canary deployment configured
  [ ] Rollback tested
  [ ] Feature flag strategy defined
  [ ] Config changes decoupled from binary changes
```

### Error Budget Policy

Document what happens at each burn rate threshold:

| Budget remaining | Action |
|-----------------|--------|
| > 50% | Normal velocity — ship features, take risks |
| 25–50% | Increased review — review high-risk launches with SRE |
| 10–25% | Slow down — defer risky launches, prioritize reliability work |
| < 10% | Freeze — halt non-critical changes; focus on reliability |
| 0% | Full freeze + postmortem — no releases until budget recovers |

### SLO Dashboard Layout

```
Row 1: Current error budget status (% remaining, burn rate)
Row 2: Four golden signals (latency p50/p99, traffic, error rate, saturation)
Row 3: SLI trend over 28 days vs. SLO target line
Row 4: Recent incidents and budget consumption events
Row 5: Upcoming releases and projected budget impact
```

---

## Common Anti-Patterns

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| 100% availability target | No room for change; incentivizes no deployments | Set explicit SLO with error budget |
| Alert on every anomaly | Alert fatigue; engineers stop responding seriously | Alert on symptoms; log causes |
| Blame individuals in postmortems | Suppresses honest reporting; fixes nothing | Focus on systems and processes |
| Toil treated as "just part of the job" | Toil grows until it consumes the team | Measure toil; cap at 50%; automate or push back |
| On-call rotation too small | Burnout; vacation impossible; high turnover | Minimum 6–8 engineers per rotation |
| Big-bang releases | Large blast radius; slow rollback | Canary + progressive rollout |
| Retrying without backoff | Load amplification under stress | Exponential backoff with jitter |
| Undeclared incidents | Diffuse accountability; poor coordination | Low threshold for declaring; normalize it |
| Postmortem action items without owners | Nothing gets fixed | Every action item has a named owner and due date |
