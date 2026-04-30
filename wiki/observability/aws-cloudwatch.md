---
title: AWS CloudWatch
tags: [cloudwatch, observability, monitoring, metrics, alarms, logs, aws]
related: ["[[Compute/AWS EC2]]", "[[Compute/AWS ECS]]", "[[Storage/AWS S3]]", "[[Database/AWS RDS]]", "[[Concepts/Google SRE Book]]"]
created: 2026-04-28
updated: 2026-04-28
---

## Overview

Amazon CloudWatch is the AWS-native monitoring and observability service. It ingests metrics, logs, and traces from AWS services and custom applications, then lets you visualize, alarm, and automate responses. It covers the full observability stack: infrastructure metrics, structured logs, distributed traces (via X-Ray integration), synthetic testing, and real-user monitoring.

## Key Concepts

### Metrics

- **Namespace** — container for metrics; AWS services use `AWS/<Service>` (e.g., `AWS/EC2`). Must be specified for every `PutMetricData` call; no default.
- **Metric identity** = namespace + metric name + up to **30 dimensions**. Each unique dimension combination is a distinct metric.
- **Dimensions** — name/value pairs that identify a metric. You can only query exact combinations you published; CloudWatch does not aggregate across partial dimension sets for custom metrics (AWS services do).
- **Resolution** — **standard** (1-minute, default for all AWS services) or **high** (1-second, custom metrics only). High-resolution costs more per `PutMetricData` call.
- **Periods** — valid values: 1, 5, 10, 30, or any multiple of 60 seconds. Sub-minute periods only work for custom metrics stored at 1-second resolution. Alarm periods must be ≥ the metric's resolution.
- **Statistics** — `SampleCount`, `Sum`, `Average`, `Min`, `Max`, percentiles (`p95`, `p99.9`), `TrimmedMean`, `WinsorizedMean`, `PercentileRank`. Percentiles require raw unsummarized data.
- **Timestamps** — accept up to 2 weeks in the past or 2 hours in the future. Use UTC; non-UTC timestamps can cause `INSUFFICIENT_DATA` alarms or delayed evaluations.
- **Statistic sets** — pre-aggregate multiple data points (Min/Max/Sum/SampleCount) into a single `PutMetricData` call to reduce API costs.

**Retention schedule** (automatic rollup, not deletable):

| Age | Resolution |
|-----|-----------|
| 0–3 hours | 1 second (high-res only) |
| 0–15 days | 1 minute |
| 15–63 days | 5 minutes |
| 63 days–15 months | 1 hour |

Metrics auto-expire 15 months after the last data point. Inactive metrics (no data for 2+ weeks) disappear from the console and `list-metrics` — use `get-metric-data` or `get-metric-statistics` to still retrieve them.

### Alarms

Three types:

| Type | Description |
|------|-------------|
| **Metric alarm** | Watches one metric or metric math expression |
| **Composite alarm** | Combines other alarm states with Boolean logic (`AND`, `OR`, `NOT`); reduces noise |
| **PromQL alarm** | Evaluates PromQL instant queries on OTLP-ingested metrics |

**Alarm states**: `OK` (green), `ALARM` (red), `INSUFFICIENT_DATA` (gray).

**Evaluation window** = period × number of evaluation periods. Max 7 days for periods ≥ 1 hour; max 1 day for shorter periods.

**Datapoints to alarm** — `M` out of the last `N` evaluation periods must breach for the alarm to trigger. The oldest of those `M` periods must have breached.

**Missing data treatment** — configurable: `missing` (default, state stays or goes to `INSUFFICIENT_DATA`), `notBreaching`, `breaching`, `ignore`. Resources that stop emitting (e.g., detached EBS volumes) naturally produce `INSUFFICIENT_DATA`.

**Actions**:
- Metric alarms: SNS, EC2 actions (stop/reboot/terminate/recover), Auto Scaling policies, Systems Manager OpsItems/incidents, CloudWatch Investigations
- Composite alarms: SNS and Systems Manager only — cannot trigger EC2 or Auto Scaling actions

**Gotchas**:
- Alarms invoke actions only on **state transitions**, not on sustained state (exception: Auto Scaling repeats once/minute while in ALARM)
- CloudWatch does **not validate** that action targets (SNS topic, Auto Scaling group) exist — missing targets fail silently
- Cross-account composite alarms are **not supported**
- `SetAlarmState` overrides last only until the next evaluation
- Alarm history is kept for **30 days**

### CloudWatch Logs

**Structure**: log groups → log streams → log events.

- **Retention** — default: indefinitely. Configurable from 1 day to 10 years per log group. Deletion protection available.
- **Log classes**: `STANDARD` (full features) and `INFREQUENT_ACCESS` (lower ingestion cost, subset of features — no `pattern`, `diff`, `unmask` commands in Logs Insights).
- **Metric filters** — extract numeric values from log events and emit them as custom CloudWatch metrics. Filter patterns use space-delimited terms; JSON log events support dotted field paths.
- **Subscription filters** — stream matching log events in real time to Kinesis Data Streams, Kinesis Data Firehose, or Lambda.
- **Live Tail** — real-time streaming view for incident troubleshooting; filter and highlight by terms.
- **Log anomaly detection** — ML-based; surfaces unusual patterns without manual pattern authoring.

### Logs Insights Query Syntax

Pipe-separated commands (`|`). Comments start with `#`. Auto-discovered fields prefixed with `@` (e.g., `@timestamp`, `@message`, `@logStream`, `@ingestionTime`).

**Commands**:

| Command | Purpose |
|---------|---------|
| `fields` | Project fields; supports expressions and functions |
| `filter` | Filter events by condition |
| `stats` | Aggregate (count, sum, avg, min, max, percentile, stddev) |
| `sort` | Order results (`asc`/`desc`) |
| `limit` | Cap result count |
| `dedup` | Deduplicate on a field |
| `parse` | Extract fields via glob or regex |
| `display` | Override which fields to show |
| `diff` | Compare current period to the previous equal-length period |
| `pattern` | Auto-cluster log lines into shared text patterns (STANDARD only) |
| `anomaly` | ML-based anomaly detection on log patterns |
| `unmask` | Reveal masked fields (requires permission; STANDARD only) |
| `filterIndex` | Restrict scan to indexed fields (faster, cheaper) |
| `SOURCE` | Specify log groups by prefix, account ID, or class (CLI/API only) |
| `unnest` | Flatten array fields into multiple records |
| `lookup` | Enrich events from reference tables |
| `join` | Combine events from different log groups |
| `subqueries` | Nested queries for intermediate result sets |

**Functions available**: aggregation, arithmetic, comparison, conditional, string, datetime, IP address.

**Performance tips**:
- Narrow the time range and log group selection as much as possible
- Use `filterIndex` when you've defined field indexes
- Cancel queries before closing the console (they continue running and incur cost otherwise)
- Avoid high-frequency dashboard refresh on Logs Insights widgets

### Anomaly Detection

- ML model trains on up to **2 weeks** of historical data; can be enabled with less data.
- Model is specific to the **metric + statistic** combination (e.g., AVG model ≠ MAX model).
- **Band threshold** — higher = wider expected range = fewer false positives.
- **Exclude time periods** after model creation to prevent deployments or incidents from skewing training data.
- Supports metric math expressions.
- Anomaly detection alarms trigger when the metric goes **above**, **below**, or **outside** the expected band — no static threshold needed.
- `ANOMALY_DETECTION_BAND` math function is available in `GetMetricData` API.
- **Not supported** in cross-account metric alarm math expressions.
- Anomaly detection models on alarms incur additional charges.

### CloudWatch Agent

Collects from EC2 instances and on-premises servers (Linux and Windows).

**What it collects**:
- **Metrics** — system-level (CPU, memory, disk, network, processes); custom app metrics via StatsD (Linux + Windows) or collectd (Linux only). Sent to CloudWatch and/or Amazon Managed Service for Prometheus (AMP). Default namespace: `CWAgent`.
- **Logs** — aggregates from multiple sources; does **not** support FIFO pipes.
- **Traces** — v1.300025.0+, forwards to X-Ray; eliminates the separate X-Ray daemon.
- **Application Signals** — v1.300031.0+ enables auto-instrumentation for CloudWatch Application Signals.

**Configuration**: JSON config file; manage centrally via Systems Manager Parameter Store. The agent has a defined credentials preference order (documented separately). All agent metrics are billed as custom metrics.

### Embedded Metric Format (EMF)

EMF lets you emit custom metrics by embedding them in structured log events — no separate `PutMetricData` calls needed. CloudWatch Logs detects the `_aws` metadata key and extracts the metrics automatically.

**Minimal valid EMF document**:

```json
{
  "_aws": {
    "Timestamp": 1574109732004,
    "CloudWatchMetrics": [
      {
        "Namespace": "MyApp/Payments",
        "Dimensions": [["Environment", "Service"]],
        "Metrics": [
          { "Name": "Latency", "Unit": "Milliseconds", "StorageResolution": 60 }
        ]
      }
    ]
  },
  "Environment": "prod",
  "Service": "checkout",
  "Latency": 135.5
}
```

**Key rules**:
- `_aws.CloudWatchMetrics` — array of `MetricDirective` objects (max 100 metrics per directive)
- Dimension and metric values must be **root-level** keys (not nested)
- Metric values can be a number or array of numbers (max 100 elements — emits a statistical distribution)
- `StorageResolution`: `1` (high-res, sub-minute) or `60` (standard, 1-minute). Default `60`.
- Max document size: 1 MB

**EMF limits**:

| Constraint | Limit |
|-----------|-------|
| Max metrics per directive | 100 |
| Max dimensions per set | 30 |
| Max dimension key length | 250 chars |
| Namespace / metric name | 1024 chars |
| Numeric array elements | 100 |

**High-cardinality gotcha**: each unique dimension combination creates a separate custom metric — avoid dimensions like `requestId` or `userId`, which will create millions of metrics and inflate costs.

### Container Insights

Collects performance data from containerized workloads.

**Supported platforms**: Amazon ECS (Linux + Windows), Amazon EKS (Linux + Windows), ROSA, Kubernetes on EC2, AWS Fargate (ECS + EKS).

**Collected metrics**: CPU, memory, disk, network at cluster, node, pod/task, and service levels. Network metrics are **not available** for ECS `host` network mode (only `bridge` and `awsvpc`).

**Data format**: performance log events in EMF — high-cardinality data ingested as structured JSON, then automatically creates the log group.

- **Enhanced Observability (EKS)** — charges per observation rather than per metric/log; cost-optimized for high-cardinality K8s environments.
- **OpenTelemetry (EKS, preview)** — collects via OTLP, supports PromQL queries, enriches metrics with up to 150 labels.
- **KMS encryption** — supported on the log group; symmetric keys only, asymmetric keys not supported. Must be manually activated.
- CloudWatch does **not** auto-create all possible metrics; use Logs Insights on the raw performance log events for additional granularity beyond what's in the default metric set.

### Cross-Account and Cross-Region Monitoring

**Architecture**: designate one or more **monitoring accounts**; all other accounts are **sharing (source) accounts**.

**Setup**:
1. In each sharing account: CloudWatch Console → Settings → Configure → grant permissions → CloudFormation creates `CloudWatch-CrossAccountSharingRole`.
2. In the monitoring account: enable cross-account viewing, choose account selector type (manual ID / Organizations dropdown / custom list). CloudWatch auto-creates `AWSServiceRoleForCloudWatchCrossAccount`.
3. Optional: for Organizations-wide account list, deploy a CloudFormation stack in the management account.

**Permission levels** (sharing account configures):
- Read-only metrics, dashboards, and alarms
- Include automatic dashboards
- Include X-Ray trace map read access
- Include Database Insights read access
- Full read-only access

**What is and isn't shareable**:

| Data type | Cross-account | Cross-region |
|-----------|--------------|--------------|
| Metrics | ✅ | ✅ |
| Dashboards | ✅ | ✅ |
| Automatic dashboards | ✅ | ✅ |
| Alarms | ❌ (view only via sharing role) | ❌ |
| Logs | ❌ | — |
| Traces | ❌ (Trace Map only) | — |

**IAM gotcha for logs**: cross-account Logs Insights queries require `"Resource": "*"` on `logs:StartQuery` in the monitoring account's IAM policy — resource-specific ARNs are not supported even if the sharing role allows them.

Cross-region monitoring is automatic once cross-account is enabled; no additional setup.

## Patterns

### Four Golden Signals Alarms

Model alarms on latency (p99), traffic (request rate), errors (5xx count or rate), and saturation (CPU, memory, connection pool). Use composite alarms to aggregate per-service health into a single indicator.

### Metric Math for Cross-Region Aggregation

CloudWatch does not aggregate across regions automatically. Use metric math with `SEARCH()` to query metrics across multiple regions in a single expression and sum/average them.

```
SUM(SEARCH('{AWS/ApplicationELB,LoadBalancer} RequestCount', 'Sum', 300))
```

### EMF for Lambda Custom Metrics

Use EMF in Lambda (via the `aws-embedded-metrics` library) instead of `PutMetricData` to emit custom metrics synchronously with the invocation. Metrics are extracted asynchronously from logs — no latency impact, no extra API call costs.

### Anomaly Detection for Seasonal Metrics

For metrics with strong weekly/daily cycles (e.g., web traffic), anomaly detection outperforms static thresholds. Exclude maintenance windows and deployment periods from the training data after model creation.

### Composite Alarms for On-Call Noise Reduction

Avoid paging on individual low-signal alarms. Create a composite alarm that combines CPU, memory, and error rate alarms — page only when two or more fire simultaneously.

### Container Insights + Logs Insights for Deep Container Analysis

Container Insights creates performance log events (EMF) in addition to metrics. Query these directly with Logs Insights to get per-container-ID granularity not exposed in the default metrics.

## Gotchas

- **Non-UTC timestamps** on `PutMetricData` calls can cause alarms to show `INSUFFICIENT_DATA` or evaluate with delays.
- **Partial dimension queries** return nothing for custom metrics. You must query the exact dimension set you published.
- **Inactive metrics** (2+ weeks no data) disappear from the console and `list-metrics` but can still be retrieved via `get-metric-data`.
- **Alarm actions are not validated** at creation time — a misconfigured SNS ARN fails silently until the alarm fires.
- **Composite alarms cannot trigger EC2 or Auto Scaling actions** — only SNS and Systems Manager.
- **Cross-account composite alarms are not supported**.
- **Anomaly detection on alarms costs extra** — charges apply per anomaly detection model used for alarms.
- **EMF high-cardinality dimensions** (requestId, userId, traceId) create one metric per unique combination — this compounds quickly and creates large unexpected bills.
- **Container Insights does not capture network metrics** for ECS tasks in `host` network mode.
- **Logs Insights queries keep running** after you close the browser tab — cancel explicitly or you'll be charged for the full scan.
- **Percentile statistics require raw data** — they cannot be computed from statistic sets unless `Min == Max`.
- **CloudWatch does not auto-aggregate across regions** — metric math with `SEARCH()` is required for multi-region aggregation.
- **Anomaly detection models** train on the specific statistic — a model trained on `Average` cannot be used for `Maximum` alarms.

## References

- [[Compute/AWS EC2]]
- [[Compute/AWS ECS]]
- [[Storage/AWS S3]]
