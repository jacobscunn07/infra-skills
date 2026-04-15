---
name: aws-cloudwatch
description: Use when working with Amazon CloudWatch - designing observability strategy, configuring metrics and alarms, CloudWatch Logs (log groups, metric filters, Logs Insights), dashboards, Container Insights, Lambda Insights, anomaly detection, composite alarms, cross-account monitoring, CloudWatch agent, or any CloudWatch architecture and troubleshooting decisions
---

# AWS CloudWatch Expert Skill

Comprehensive Amazon CloudWatch guidance covering metrics, alarms, logs, dashboards, insights, agent configuration, and production observability patterns. Based on the official AWS CloudWatch User Guide.

## When to Use This Skill

**Activate this skill when:**
- Designing an observability and alerting strategy
- Configuring CloudWatch metrics, dimensions, and namespaces
- Creating alarms (simple, composite, anomaly detection)
- Working with CloudWatch Logs — log groups, retention, metric filters
- Querying logs with CloudWatch Logs Insights
- Setting up Container Insights for ECS or EKS
- Installing and configuring the CloudWatch agent on EC2
- Building dashboards for operational visibility
- Implementing cross-account or cross-region monitoring
- Troubleshooting missing metrics, misfiring alarms, or log ingestion issues

**Don't use this skill for:**
- AWS X-Ray distributed tracing — separate service
- CloudTrail audit logging — separate service
- Application-level APM instrumentation (OpenTelemetry setup) — broader observability topic

---

## Core Concepts

### Namespaces

A namespace is a container for related metrics. AWS services publish to `AWS/<ServiceName>` (e.g., `AWS/EC2`, `AWS/ECS`, `AWS/Lambda`). Your custom metrics go in a namespace you define (e.g., `MyApp/Production`).

Namespaces are isolated — `CPUUtilization` in `AWS/EC2` is different from `CPUUtilization` in `MyApp/Production`.

### Metrics

A metric is a time-ordered set of data points. Each data point has a timestamp, value, and unit.

Key properties:

| Property | Description |
|----------|-------------|
| **Namespace** | Container (`AWS/EC2`) |
| **Metric name** | `CPUUtilization` |
| **Dimensions** | Name/value pairs that identify the metric instance (`InstanceId=i-0abc123`) |
| **Resolution** | Standard (1-minute) or high-resolution (1-second) |
| **Statistics** | Average, Min, Max, Sum, SampleCount, p99 |

**Dimensions** create unique metric series. `CPUUtilization` for `InstanceId=i-001` is a different metric from `InstanceId=i-002`. Up to 30 dimensions per metric.

### Metric Retention

| Data point resolution | Retention |
|----------------------|-----------|
| < 60 seconds (high-res) | 3 hours |
| 1 minute | 15 days |
| 5 minutes | 63 days |
| 1 hour | 15 months |

CloudWatch automatically aggregates high-resolution data into lower-resolution buckets for long-term storage.

### Custom Metrics

Publish from your application using `PutMetricData`:

```bash
aws cloudwatch put-metric-data \
  --namespace "MyApp/Orders" \
  --metric-data '[{
    "MetricName": "OrdersProcessed",
    "Value": 42,
    "Unit": "Count",
    "Dimensions": [
      {"Name": "Environment", "Value": "prod"},
      {"Name": "Region", "Value": "us-east-1"}
    ]
  }]'
```

Use high-resolution metrics (`--storage-resolution 1`) for latency-sensitive monitoring. Standard is sufficient for most business metrics.

---

## Alarms

An alarm watches a single metric (or metric math expression) and transitions between `OK`, `ALARM`, and `INSUFFICIENT_DATA` states.

### Simple Alarm

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "HighCPU-my-instance" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --dimensions Name=InstanceId,Value=i-0abc123 \
  --statistic Average \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:ops-alerts \
  --treat-missing-data notBreaching
```

- `period 300` + `evaluation-periods 3` = alarm fires after 15 continuous minutes above 80% CPU
- `treat-missing-data notBreaching` — if metrics stop flowing, don't alarm (useful for auto-scaled instances that may stop reporting)

### Alarm Actions

| Action Type | Use Case |
|-------------|---------|
| **SNS notification** | Alert via email, Slack (via Lambda), PagerDuty |
| **Auto Scaling policy** | Scale EC2 ASG based on metric |
| **EC2 action** | Stop, reboot, terminate, or recover the instance |
| **Systems Manager OpsItem** | Create incident ticket automatically |

### Metric Math Alarms

Alarm on expressions combining multiple metrics:

```bash
# Alarm on error rate (errors / total requests)
--metrics '[
  {"Id": "errors",   "MetricStat": {"Metric": {..."MetricName": "5XXError"...}, "Period": 60, "Stat": "Sum"}},
  {"Id": "requests", "MetricStat": {"Metric": {..."MetricName": "Count"...},    "Period": 60, "Stat": "Sum"}},
  {"Id": "rate",     "Expression": "errors/requests*100", "Label": "ErrorRate%"}
]' \
--alarm-name "HighErrorRate" \
--threshold 5 \
--metrics-based-on "rate"
```

### Anomaly Detection

CloudWatch ML model learns a baseline for a metric and alarms when it deviates beyond a configurable band:

```bash
aws cloudwatch put-anomaly-detector \
  --namespace AWS/ApplicationELB \
  --metric-name RequestCount \
  --dimensions Name=LoadBalancer,Value=app/my-alb/...

aws cloudwatch put-metric-alarm \
  --alarm-name "AnomalousRequestCount" \
  --metrics '[{"Id":"m1","MetricStat":{...}},{"Id":"ad1","Expression":"ANOMALY_DETECTION_BAND(m1,2)"}]' \
  --comparison-operator GreaterThanUpperThreshold \
  --threshold-metric-id "ad1"
```

The `2` in `ANOMALY_DETECTION_BAND(m1,2)` is the number of standard deviations. Higher = less sensitive.

### Composite Alarms

Combine multiple alarms with boolean logic — reduce alert noise by only paging when multiple symptoms are true simultaneously:

```bash
aws cloudwatch put-composite-alarm \
  --alarm-name "ServiceDegraded" \
  --alarm-rule "ALARM(HighLatency) AND ALARM(HighErrorRate)" \
  --alarm-actions arn:aws:sns:...:pagerduty-critical

aws cloudwatch put-composite-alarm \
  --alarm-name "PossibleIssue" \
  --alarm-rule "ALARM(HighLatency) OR ALARM(HighErrorRate)" \
  --alarm-actions arn:aws:sns:...:slack-warning
```

---

## CloudWatch Logs

### Key Concepts

| Concept | Description |
|---------|-------------|
| **Log group** | Collection of log streams with shared retention and access settings |
| **Log stream** | Sequence of events from a single source (one EC2 instance, one Lambda invocation) |
| **Log event** | A single timestamped log entry |
| **Metric filter** | Extracts a numeric value from log data to create a CloudWatch metric |
| **Subscription filter** | Streams log events in real-time to Lambda, Kinesis, or Firehose |

### Log Group Retention

Set retention on every log group — unconfigured log groups retain logs forever:

```bash
aws logs put-retention-policy \
  --log-group-name /ecs/my-app \
  --retention-in-days 90
```

Common retention policies:
- Application logs: 30–90 days
- Access logs: 90–365 days
- Audit/compliance logs: 365–2557 days (7 years)

### Metric Filters

Extract metrics from unstructured logs without changing application code:

```bash
# Count ERROR occurrences
aws logs put-metric-filter \
  --log-group-name /ecs/my-app \
  --filter-name "ErrorCount" \
  --filter-pattern "ERROR" \
  --metric-transformations '[{
    "metricName": "ErrorCount",
    "metricNamespace": "MyApp/Errors",
    "metricValue": "1",
    "defaultValue": 0,
    "unit": "Count"
  }]'
```

For JSON logs, extract specific field values:
```
# Filter: requests where latency > 1000ms from JSON log { "latency": 1234, "path": "/api" }
--filter-pattern '{ $.latency > 1000 }'
--metric-transformations '[{"metricName":"SlowRequests","metricValue":"1",...}]'
```

### CloudWatch Logs Insights

Ad-hoc query language for log analysis. Charges per GB scanned.

```sql
-- Find the 10 slowest API requests in the last hour
fields @timestamp, requestId, duration, path
| filter path like /api/
| sort duration desc
| limit 10

-- Count errors by type
filter level = "ERROR"
| stats count() by errorType
| sort count desc

-- P99 latency over time
filter @logStream like /ecs/
| stats pct(duration, 99) as p99 by bin(5m)
| sort @timestamp desc

-- Lambda cold starts
filter @message like /Init Duration/
| parse @message "Init Duration: * ms" as initDuration
| stats avg(initDuration), max(initDuration), count() by bin(1h)
```

---

## CloudWatch Agent

Install on EC2 or on-premises servers to collect:
- System-level metrics: memory, disk usage, swap (not available via default EC2 metrics)
- Custom application metrics
- Log files from disk

### Install and Configure

```bash
# Install on Amazon Linux 2
sudo yum install -y amazon-cloudwatch-agent

# Configure via SSM Parameter Store (recommended)
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c ssm:/cloudwatch-agent/config
```

### Agent Configuration (SSM Parameter)

```json
{
  "metrics": {
    "namespace": "MyApp/System",
    "metrics_collected": {
      "mem": { "measurement": ["mem_used_percent"] },
      "disk": {
        "measurement": ["disk_used_percent"],
        "resources": ["/", "/data"]
      },
      "cpu": {
        "measurement": ["cpu_usage_user", "cpu_usage_system"],
        "totalcpu": true
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [{
          "file_path": "/var/log/myapp/app.log",
          "log_group_name": "/ec2/my-app",
          "log_stream_name": "{instance_id}",
          "timezone": "UTC"
        }]
      }
    }
  }
}
```

Instance profile must include `CloudWatchAgentServerPolicy` managed policy.

---

## Container Insights

Purpose-built monitoring for containerized workloads. Collects metrics at the cluster, service, task, and container level.

### Enable for ECS

```bash
aws ecs update-cluster-settings \
  --cluster my-cluster \
  --settings name=containerInsights,value=enabled
```

Metrics available in `ECS/ContainerInsights` namespace:
- `CpuUtilized`, `CpuReserved`, `MemoryUtilized`, `MemoryReserved` (per cluster, service, task, container)
- `NetworkRxBytes`, `NetworkTxBytes`
- `StorageReadBytes`, `StorageWriteBytes`
- `RunningTaskCount`, `PendingTaskCount`

Container Insights also surfaces pre-built dashboards in the CloudWatch console under **Container Insights**.

### Enable for EKS

Requires deploying the CloudWatch agent as a DaemonSet. Use the AWS-provided Helm chart or the `aws-cloudwatch-metrics` addon for managed node groups.

---

## Dashboards

Dashboards are shareable, multi-widget views. Supports metrics, logs, alarms, and text.

```bash
aws cloudwatch put-dashboard \
  --dashboard-name "ProductionOverview" \
  --dashboard-body file://dashboard.json
```

**Best practices:**
- Pin to **automatic dashboards** provided by AWS for individual services (EC2, ECS, RDS, Lambda) as a starting point — free and pre-configured
- Add **alarm status widgets** so dashboard shows red/green at a glance
- Use **metric math** in dashboard widgets to show derived values (error rate %, cost per request)
- Share across accounts using **cross-account dashboards** with the source account linked to a monitoring account

---

## Cross-Account Monitoring

Link multiple source accounts to a central **monitoring account**:

```
Monitoring account (central)
  └── Linked source accounts: A, B, C
        └── View metrics, logs, alarms from all accounts in one place
        └── Create cross-account dashboards and composite alarms
```

Link via AWS Organizations (all accounts) or individually (specific account IDs).

---

## Architecture Patterns

### Standard Production Alarm Stack

```
Service metrics:
  ALBRequestCount → target tracking (Auto Scaling)
  TargetResponseTime p99 > 2s for 3 periods → SNS warning
  HTTPCode_Target_5XX_Count / RequestCount > 1% → SNS critical
  UnhealthyHostCount > 0 for 2 periods → SNS critical

Composite alarm:
  "ALARM(HighLatency) AND ALARM(HighErrorRate)" → PagerDuty

EC2 system:
  CPUUtilization > 90% → SNS
  MemoryUsed > 90% (via CW agent) → SNS
  DiskUsed > 80% → SNS
```

### Log-Based Alerting

```
Application emits structured JSON logs:
  {"level":"ERROR","type":"DatabaseTimeout","latency":5023}

Metric filter: { $.level = "ERROR" && $.type = "DatabaseTimeout" }
  → Metric: MyApp/Errors/DatabaseTimeout

Alarm: DatabaseTimeout > 5 in 5 minutes → SNS → PagerDuty
```

### Centralized Observability

```
Dev accounts (A, B):
  CloudWatch Logs subscription filter → Kinesis Data Streams
    → Kinesis Firehose → S3 (central log archive)

Production account (C):
  Container Insights enabled on all ECS clusters
  Custom metrics via CloudWatch agent on EC2

Monitoring account:
  Cross-account links to A, B, C
  Central dashboard: all service health in one view
  Composite alarms: cross-account alert correlation
```

---

## Security Best Practices

1. **Set retention on all log groups** — unconfigured log groups retain forever and generate unbounded costs
2. **Encrypt log groups with KMS** — for sensitive logs (`aws logs associate-kms-key`); KMS key must be in the same region
3. **IAM least privilege for PutMetricData** — restrict to specific namespaces; don't grant `cloudwatch:*`
4. **Use metric filters instead of log queries for alarms** — metric filters are cheaper and more reliable than scheduled Logs Insights queries
5. **Cross-account monitoring account** — centralize alarms and dashboards; reduces blast radius if a workload account has an IAM issue

---

## Common Troubleshooting

| Symptom | Likely Cause |
|---------|-------------|
| EC2 memory/disk metrics missing | CloudWatch agent not installed or not running; check agent logs at `/opt/aws/amazon-cloudwatch-agent/logs/` |
| Alarm stuck in `INSUFFICIENT_DATA` | Metric not being published; check namespace and dimensions exactly match alarm configuration |
| Alarm fires then immediately returns to OK | Evaluation period too short — increase `evaluation-periods`; or add `datapoints-to-alarm` parameter |
| Logs not appearing in log group | Check log group name in agent config; verify IAM role has `logs:CreateLogStream` and `logs:PutLogEvents` |
| Metric filter not generating metrics | Filter pattern syntax error; test with `filter-log-events --filter-pattern` first; metric only appears after a matching log event |
| Logs Insights query returns nothing | Wrong log group selected; or time range doesn't include the events; or `@message` field name is wrong |
| Container Insights metrics missing for ECS | `containerInsights` cluster setting not enabled; or tasks not using awslogs log driver |
| High CloudWatch costs | High-resolution custom metrics (1s) are 3× more expensive; check for noisy `PutMetricData` loops in application code |
