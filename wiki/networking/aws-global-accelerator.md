---
title: AWS Global Accelerator
tags: [global-accelerator, anycast, networking, multi-region, failover, static-ip, gaming, iot, shield]
related: ["[[Networking/AWS CloudFront]]", "[[Compute/AWS EC2]]", "[[Networking/AWS VPC]]"]
created: 2026-04-28
updated: 2026-04-28
---

## Overview

AWS Global Accelerator improves availability and performance for internet applications by routing traffic over the AWS global network rather than the public internet. It provides two static anycast IP addresses as fixed entry points, routing users to the nearest healthy regional endpoint. Unlike [[Networking/AWS CloudFront]], it operates at Layer 4 (TCP/UDP) and does not cache — it accelerates any protocol.

## Key Concepts

- **Accelerator** — the top-level resource; provides 2 static IPv4 addresses (or 2 IPv4 + 2 IPv6 for dual-stack). Two types: Standard and Custom Routing.
- **Static anycast IPs** — traffic enters the AWS network at the nearest edge location and travels the AWS backbone to the endpoint. IPs are fixed for the accelerator's lifetime; losing the accelerator loses the IPs permanently.
- **Network zones** — isolated infrastructure units (analogous to AZs), one IP per zone. If one IP is unavailable, clients retry on the other zone's IP automatically.
- **Listener** — processes inbound connections on a port/port-range and protocol (TCP, UDP, or both). Associates to one or more endpoint groups.
- **Endpoint group** — a Regional bucket containing one or more endpoints. Each group has a **traffic dial** (0–100%) controlling what fraction of listener traffic it receives.
- **Endpoint** — the actual resource receiving traffic: NLB, ALB (internet-facing or internal), EC2 instance, or Elastic IP. Each endpoint has a **weight** controlling its share within the group.
- **Traffic dial** — coarse control per Region; useful for blue/green cutover or gradual traffic shifts.
- **Endpoint weight** — fine control within a Region; useful for canary deployments or weighted A/B tests.
- **Client affinity** — optional session stickiness; routes all requests from the same source IP to the same endpoint for the duration of a session.
- **BYOIP** — bring your own IPv4 range to use as the static IPs instead of AWS-assigned addresses.

## Accelerator Types

### Standard Accelerator
Routes traffic to the nearest healthy endpoint based on user location, health checks, and configured weights/dials. Supports NLB, ALB, EC2, and Elastic IP endpoints. Supports dual-stack (IPv4 + IPv6).

### Custom Routing Accelerator
Deterministically maps specific client IP:port combinations to specific EC2 destinations within VPC subnets. One accelerator can fan out to thousands of instances. Designed for gaming servers and VoIP where the client must reach a specific backend process. Does **not** support dual-stack.

## Patterns

### Multi-Region Active-Active with Automatic Failover
Deploy endpoint groups in two or more Regions, each with a traffic dial. Keep both at 100% — Global Accelerator routes to the nearest healthy Region. On a Regional failure, health checks detect unhealthy endpoints and shift traffic to the next nearest Region automatically (typically within seconds).

### Blue/Green Deployment via Traffic Dial
Stand up a new Region or endpoint group. Set its traffic dial to 0% (dark). Gradually increment — 5%, 25%, 50%, 100% — while monitoring. To roll back, set the dial back to 0%. No DNS TTL wait; changes propagate quickly through the edge network.

### Protecting Origins with Internal ALBs
Configure an internal (non-internet-facing) ALB as an endpoint. Global Accelerator reaches it via private IP peering, keeping origin traffic off the public internet entirely. Exposes only the two static IPs, reducing attack surface.

### IoT / Embedded Clients with Static IPs
Devices with hardcoded IPs (firmware, set-top boxes) can't chase DNS changes. Use the two static anycast IPs as the permanent network address. Scale, swap, or fail over backend endpoints without touching client firmware.

### Gaming with Custom Routing
Each game session runs on a specific EC2 instance. Custom routing accelerator maps each unique client IP:port to the correct instance, providing low-latency, deterministic routing without requiring public IPs on game servers.

## Global Accelerator vs CloudFront

| | Global Accelerator | CloudFront |
|---|---|---|
| Layer | 4 (TCP/UDP) | 7 (HTTP/HTTPS) |
| Caching | ❌ | ✅ |
| Static IPs | ✅ (2 anycast) | ❌ |
| Protocols | Any (TCP, UDP, HTTP, gRPC, custom) | HTTP/HTTPS only |
| DDoS protection | AWS Shield Standard (included) | AWS Shield Standard (included) |
| Edge functions | ❌ | CloudFront Functions, Lambda@Edge |
| Best for | Non-HTTP, real-time, gaming, IoT, multi-region failover | Web content delivery, caching, CDN |

**Decision rule:** Use CloudFront when you need caching, edge compute, or HTTP-specific features. Use Global Accelerator when you need static IPs, non-HTTP protocols, or sub-second multi-region failover for any protocol.

## Gotchas

- **Deleting an accelerator permanently loses the static IPs** — they cannot be recovered or reassigned. Use IAM tag-based policies (ABAC) to block accidental deletion.
- **Disabled accelerators still hold their IPs** — you are billed for them even when disabled.
- **Custom routing does not support dual-stack** — IPv6 requires a standard accelerator.
- **VPC Block Public Access (BPA) blocks Global Accelerator traffic** — unless the specific VPC or subnet is explicitly excluded from BPA. Egress-only BPA exclusions are still blocked.
- **Traffic dials and endpoint weights only apply to standard accelerators** — custom routing uses deterministic port mapping, not weighted routing.
- **Health check failures do not use traffic dials** — if the only healthy endpoint is in a Region with a 0% traffic dial, Global Accelerator will still route there to avoid dropping traffic.
- **ALBs used as endpoints must allow traffic from Global Accelerator's edge IPs** — for internal ALBs this is handled via private peering; for internet-facing ALBs, ensure security groups permit it.

## References

- [[Networking/AWS CloudFront]]
- [[Compute/AWS EC2]]
