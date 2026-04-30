---
title: Google SRE Book
tags: [sre, reliability, slo, sli, toil, incidents, monitoring, oncall, postmortem]
related: ["[[Observability/AWS CloudWatch]]"]
created: 2026-04-28
updated: 2026-04-28
---

## Overview

The Google SRE Book (*Site Reliability Engineering: How Google Runs Production Systems*, O'Reilly 2016) defines the SRE discipline and its core practices. It is organized around five themes: principles, practices, management, and conclusions. The concepts below are the ones most applicable to infrastructure-as-code and cloud operations.

Source: https://sre.google/sre-book/table-of-contents/

## Key Concepts

### Embracing Risk (Ch. 3)

- Reliability is a spectrum, not a binary. 100% uptime is the wrong target — it eliminates room for deployment velocity and is indistinguishable from 99.999% to most users.
- **Error budget** — the allowable unreliability per SLO period (e.g., 0.1% for a 99.9% SLO). When the budget is exhausted, new feature releases are frozen until it replenishes.
- Cost of reliability is not linear: going from 99.9% to 99.99% requires far more investment than 99% to 99.9%.

### SLIs, SLOs, SLAs (Ch. 4)

- **SLI (Service Level Indicator)** — a quantitative measure of service behavior (e.g., request latency p99, error rate, availability).
- **SLO (Service Level Objective)** — the internal reliability target for an SLI (e.g., p99 latency < 200 ms over a 30-day window). This is what the team is accountable to.
- **SLA (Service Level Agreement)** — the external contractual commitment, with financial consequences. SLAs must be looser than SLOs to leave a buffer.
- SLOs should be set based on user happiness, not what is technically easy to achieve.

### Eliminating Toil (Ch. 5)

- **Toil** — manual, repetitive, automatable, tactical work that scales linearly with traffic. It has no enduring value.
- SREs should spend < 50% of their time on toil. The rest goes to engineering work that reduces future toil.
- Tracking toil sources over time reveals where automation investment pays off most.

### Monitoring Distributed Systems (Ch. 6)

The **four golden signals** — the minimum viable monitoring set for any service:

| Signal | What it measures |
|--------|-----------------|
| **Latency** | Time to serve a request (distinguish successful vs. error latency) |
| **Traffic** | Demand on the system (RPS, queries/sec, throughput) |
| **Errors** | Rate of failed requests (explicit 5xx, implicit wrong content, policy violations) |
| **Saturation** | How "full" the service is; utilization of constrained resources (CPU, memory, I/O, queue depth) |

- Alert on **symptoms** (user-visible pain), not causes. Cause-based alerts are noisy and mask the real signal.
- Use **pages** only for conditions requiring immediate human action. Everything else is a ticket or dashboard.

### Release Engineering (Ch. 8)

- **Hermetic builds** — builds are reproducible and self-contained; same source always produces the same binary.
- Release branches cut from a known-good state; hotfixes cherry-picked in, never developed on the branch directly.
- Configuration management is a first-class concern: config changes carry the same risk as code changes.

### Simplicity (Ch. 9)

- Boring solutions are correct solutions. Every new abstraction or framework is a liability until proven otherwise.
- "Simplicity is a prerequisite for reliability." Complex systems fail in complex, unpredictable ways.
- Code that isn't deployed is a risk. Dead code should be removed.

## Patterns

### On-Call Design (Ch. 11)

- Aim for < 2 incidents per 12-hour on-call shift to allow proper incident response and follow-up.
- On-call engineers need clear escalation paths and runbooks for every page they might receive.
- Postmortems are required for all on-call incidents above a severity threshold.

### Effective Troubleshooting (Ch. 12)

Systematic diagnosis loop:
1. **Triage** — assess severity, stop the bleeding (mitigate first, diagnose second).
2. **Examine** — gather data from monitoring, logs, and recent changes.
3. **Diagnose** — form and test hypotheses one at a time.
4. **Test/Treat** — apply fix and verify impact.

Common anti-patterns: testing multiple hypotheses simultaneously, making changes without recording them, fixing symptoms rather than root cause.

### Incident Management (Ch. 14)

ICS-inspired structure:
- **Incident Commander (IC)** — owns the incident, delegates tasks, controls communications.
- **Operations Lead** — executes changes under IC direction; the only person making production changes.
- **Communications Lead** — keeps stakeholders informed so the IC and ops lead can focus.
- Declare incidents early and escalate; a false alarm costs far less than a late declaration.

### Postmortem Culture (Ch. 15)

- **Blameless postmortems** — focus on system and process failures, not individual errors. Psychological safety is a prerequisite for honest postmortems.
- Every postmortem must produce actionable items with owners and due dates.
- Template: timeline, root cause, contributing factors, action items, lessons learned.
- Postmortems should be shared broadly — learning is the point.

### Handling Overload (Ch. 21)

- **Load shedding** — reject requests explicitly when overloaded rather than accepting them and degrading for everyone.
- Return meaningful errors (HTTP 503, gRPC RESOURCE_EXHAUSTED) with Retry-After hints so clients back off gracefully.
- Per-client quotas prevent a single bad actor from consuming all capacity.

### Cascading Failures (Ch. 22)

- Cascading failures begin when a resource (CPU, threads, connections) becomes exhausted, causing latency to rise, causing queues to fill, causing upstream timeouts.
- Prevention: **capacity buffers**, **circuit breakers**, **timeout budgets**, **graceful degradation**.
- During a cascade: add capacity first, then diagnose. Reducing load almost always helps; adding more features to a failing system almost never does.

## Gotchas

- SLO windows matter: a 30-day rolling window catches gradual degradation; a calendar-month window can mask it with a fresh reset.
- Error budgets only work if the team actually stops deploying when the budget is spent. A policy with no enforcement is theater.
- "Alert on every error" is a toil generator. Alert fatigue desensitizes on-call engineers and causes pages to be silenced.
- Postmortems without action item follow-through become a ritual rather than a learning mechanism.
- Handcrafted runbooks that are never exercised will be wrong when you need them most. Runbooks must be tested in drills.
- The four golden signals are a minimum — high-percentile latency (p99, p999) is often more important than average latency for catching tail latency problems.

## References

- [[Observability/AWS CloudWatch]]
- Source book: https://sre.google/sre-book/table-of-contents/
- Companion volume: *The Site Reliability Workbook* (practical exercises)
