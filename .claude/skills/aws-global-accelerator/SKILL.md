---
name: aws-global-accelerator
description: Use when working with AWS Global Accelerator - designing standard or custom routing accelerators, configuring listeners, endpoint groups, traffic dials, endpoint weights, health checks, static anycast IPs, BYOIP, or deciding when to use Global Accelerator vs CloudFront for latency and availability improvements
---

# AWS Global Accelerator Expert Skill

Comprehensive AWS Global Accelerator guidance covering accelerator types, listeners, endpoint groups, traffic routing, health checks, and when to use it versus CloudFront. Based on the official AWS Global Accelerator Developer Guide.

## When to Use This Skill

**Activate this skill when:**
- Needing static IP addresses as a global entry point for an application
- Improving latency for non-HTTP or mixed TCP/UDP workloads
- Routing traffic across multiple AWS regions with automatic failover
- Performing blue/green or canary deployments across regions using traffic dials
- Needing instant, health-based failover without DNS TTL delays
- Building custom routing to specific EC2 instances/ports in a VPC
- Comparing Global Accelerator vs CloudFront for a use case

**Don't use this skill for:**
- Caching and CDN content delivery — use aws-cloudfront skill
- WAF and bot control at the edge — use aws-cloudfront with WAF
- DNS-based routing — use Route 53 skill

---

## What Global Accelerator Is

AWS Global Accelerator routes traffic over the **AWS global network backbone** instead of the public internet. Clients connect to the nearest AWS edge location via **anycast static IP addresses**, then traffic travels on AWS's private, optimized, congestion-free network to your endpoints.

### How It Differs From the Public Internet

```
Public Internet path:
  User → ISP → ~15 hops across internet → Your origin (variable latency, packet loss)

Global Accelerator path:
  User → AWS edge (nearest POP) → AWS backbone → Your endpoint (1–2 hops, consistent latency)
```

This is most impactful for:
- Users far from the AWS region hosting the app
- Workloads sensitive to packet loss or jitter (gaming, VoIP, video streaming, financial trading)
- TCP connections where the benefit compounds over the full connection lifetime

---

## Core Components

```
Accelerator
  └── Listener (port/protocol)
        └── Endpoint Group (per AWS Region)
              └── Endpoints (ALB, NLB, EC2, Elastic IP)
```

| Component | Description |
|-----------|-------------|
| **Accelerator** | The top-level resource; provides 2 static anycast IPv4 (or 4 for dual-stack) |
| **Listener** | Receives traffic on specified ports/protocols (TCP, UDP, or both) |
| **Endpoint Group** | A regional group of endpoints; has a traffic dial (0–100%) |
| **Endpoint** | An ALB, NLB, EC2 instance, or Elastic IP that receives traffic |

---

## Static Anycast IP Addresses

Every accelerator gets 2 static IPv4 addresses (IPv4 anycast). For dual-stack accelerators: 2 IPv4 + 2 IPv6 = 4 total.

Key properties:
- **Anycast routing** — both IPs are advertised from every AWS edge POP globally; users connect to the nearest one automatically
- **Permanent** — IPs stay assigned as long as the accelerator exists, even when disabled
- **Lost on delete** — if you delete the accelerator, the IPs are released; you cannot reclaim them
- **BYOIP** — bring your own IP address range instead of using AWS-provided ones (requires ROA/RPKI authorization)

Use static IPs when:
- Clients or partners whitelist specific IPs (can't use a DNS name)
- Regulatory or compliance requirements mandate fixed IP addresses
- You want a single IP entry point regardless of regional routing changes

---

## Accelerator Types

### Standard Accelerator

Routes traffic to the **optimal healthy endpoint** based on the client's geographic proximity and endpoint health. Supports ALB, NLB, EC2 instances, and Elastic IPs.

Traffic decision order:
1. Is there a healthy endpoint in the nearest region? → Route there
2. Otherwise, route to the next-nearest healthy region

**Best for:** Multi-region active-active or active-passive deployments, latency-optimized routing.

### Custom Routing Accelerator

Maps a specific client (identified by static IP + listener port) to a **specific EC2 instance and port** within a VPC subnet. No health checks or automatic failover — you control routing explicitly.

**Best for:** Gaming backends (route a specific player to a specific server), real-time communication apps that require session affinity to a specific server.

---

## Listeners

A listener defines which ports and protocols the accelerator accepts traffic on.

```json
{
  "Protocol": "TCP",
  "PortRanges": [
    { "FromPort": 80,  "ToPort": 80  },
    { "FromPort": 443, "ToPort": 443 }
  ],
  "ClientAffinity": "NONE"
}
```

**Client Affinity:**
- `NONE` (default) — each request may go to a different endpoint; best for stateless services
- `SOURCE_IP` — requests from the same client IP always go to the same endpoint; useful for stateful apps that can't use sticky sessions

**Protocol support:**
- `TCP` — for HTTP, HTTPS, and any TCP-based protocol
- `UDP` — for gaming, DNS, real-time streaming
- `TCP_UDP` — listen on both (uses TCP for health checks)

---

## Endpoint Groups

Each endpoint group corresponds to one AWS Region and contains the actual endpoints.

### Traffic Dials

Control the percentage of traffic a region receives:

```
us-east-1 endpoint group: traffic dial = 100%  (active)
eu-west-1 endpoint group: traffic dial = 0%    (standby / blue-green)
```

Traffic is distributed proportionally across endpoint groups with non-zero dials. Use this for:
- **Blue/green deployments** — gradually shift traffic from old region to new
- **Canary testing** — send 5% of global traffic to a new region
- **Disaster recovery** — set primary to 0% during an incident; secondary takes 100%

### Endpoint Weights

Control traffic distribution within a region across individual endpoints:

```
ALB-1: weight=200  → gets 200/300 = 67% of regional traffic
ALB-2: weight=100  → gets 100/300 = 33% of regional traffic
```

Default weight: 128 (range 0–255). Set to 0 to drain an endpoint without removing it.

---

## Health Checks

Standard accelerators continuously monitor endpoint health (custom routing does not).

- Health checks run automatically — no separate configuration needed
- On endpoint failure: new connections are **instantly** redirected to healthy endpoints
- No DNS TTL delay — failover is at the network layer, not DNS

**Failover behavior when all endpoints in a region are unhealthy:**
- Global Accelerator routes to the next-nearest region with healthy endpoints
- If no healthy endpoints exist globally: routes to all endpoints as a last-resort fallback

**Idle timeout:**
- TCP: 340 seconds
- UDP: 30 seconds
- Established connections keep routing to their endpoint even if it becomes unhealthy — only new connections are redirected

---

## Global Accelerator vs CloudFront

This is the most common architecture decision question.

| Dimension | Global Accelerator | CloudFront |
|-----------|-------------------|------------|
| **Primary use** | Network-level acceleration (TCP/UDP) | Content delivery and caching (HTTP/HTTPS) |
| **Caching** | None | Core feature — reduces origin load |
| **Layer** | Layer 4 (transport) | Layer 7 (application) |
| **Static IPs** | Yes — 2 anycast IPs | No — DNS-based (`*.cloudfront.net`) |
| **Protocols** | TCP, UDP | HTTP, HTTPS, WebSocket |
| **Edge compute** | None | Lambda@Edge, CloudFront Functions |
| **WAF integration** | No | Yes |
| **Failover speed** | Near-instant (network layer) | DNS TTL (60s typical) |
| **Pricing** | Hourly + data transfer | Data transfer + requests |

### Decision Guide

**Use Global Accelerator when:**
- You need static IP addresses that clients can whitelist
- Your application uses non-HTTP protocols (gaming UDP, custom TCP, IoT)
- You need sub-second failover between regions (no DNS TTL)
- Your app is stateful and already handles routing — you just need the backbone network
- You serve users from regions far from your AWS endpoint

**Use CloudFront when:**
- You're delivering web content (HTML, JS, CSS, images, video)
- Caching is valuable — reduces origin load and cost
- You need WAF, Lambda@Edge, or CloudFront Functions
- Your clients access via browser (DNS is fine, no IP whitelisting needed)

**Use both when:**
- CloudFront for cacheable content + edge security (WAF)
- Global Accelerator behind CloudFront for dynamic API traffic with regional failover (uncommon but valid)

---

## Architecture Patterns

### Multi-Region Active-Active

```
Global Accelerator (2 static IPs)
  Listener: TCP 443
  ├── Endpoint Group us-east-1 (traffic dial: 50%)
  │     └── ALB → ECS services
  └── Endpoint Group eu-west-1 (traffic dial: 50%)
        └── ALB → ECS services

Routing: Global Accelerator sends each user to the closest healthy region
Failover: If us-east-1 ALB fails health checks → all traffic shifts to eu-west-1 instantly
```

### Blue/Green Regional Deployment

```
Step 1: Deploy new version to eu-west-1 (blue: 100%, green: 0%)
Step 2: Shift traffic gradually: blue 90%, green 10%
Step 3: Monitor error rates → blue 50%, green 50%
Step 4: Full cutover → blue 0%, green 100%
Step 5: Rollback if needed: green 0%, blue 100% instantly

No DNS changes, no TTL waiting.
```

### Gaming / Real-Time UDP

```
Custom Routing Accelerator (UDP)
  Listener: UDP 7000-7999
  VPC subnet: 10.0.1.0/24 (game servers)
  
Matchmaker service:
  1. Creates a match, assigns players to server i-0abc123:7042
  2. Calls EnableCustomRoutingTraffic for that instance/port
  3. Returns static accelerator IP + port to all players
  4. All players connect to same IP:port → routed to same server
```

---

## Security Best Practices

1. **Lock down origin security groups** — ALB/NLB should only accept traffic from the Global Accelerator IP ranges (use the `com.amazonaws.global.globalaccelerator` prefix list in security group rules)
2. **BYOIP with care** — if you bring your own IPs, ensure ROA records are properly configured; IP hijacking protection requires RPKI
3. **Client affinity for stateful apps** — use `SOURCE_IP` affinity if your app requires session stickiness
4. **Health check sensitivity** — tune health check thresholds carefully; too sensitive causes unnecessary failovers; too loose delays recovery
5. **Monitor with CloudWatch** — key metrics: `NewFlowCount`, `ProcessedBytesIn/Out`, `UnhealthyRoutingFlow`

---

## Common Troubleshooting

| Symptom | Likely Cause |
|---------|-------------|
| Connections reach accelerator but not endpoint | Security group on ALB/NLB doesn't allow traffic from Global Accelerator prefix list IPs |
| Traffic not shifting with traffic dial change | Existing connections persist until idle timeout (TCP: 340s); new connections obey updated dial |
| Unexpected endpoint receiving traffic | All-zero traffic dial endpoints receive traffic when all non-zero endpoints are unhealthy — a fallback, not a bug |
| High latency despite Global Accelerator | Client's ISP not peering well with the nearest edge POP; try running `traceroute` to the static IP to verify traffic enters AWS quickly |
| Custom routing not reaching instance | `EnableCustomRoutingTraffic` not called for the specific instance+port combination; or NACL/security group blocking UDP |
