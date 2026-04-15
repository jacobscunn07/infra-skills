---
name: aws-networking
description: Use when working with AWS networking - designing VPCs, subnets, routing, security groups, NACLs, internet/NAT gateways, VPC peering, Transit Gateway, VPN, Direct Connect, VPC endpoints, flow logs, or any AWS network architecture and troubleshooting decisions
---

# AWS Networking Expert Skill

Comprehensive AWS VPC and networking guidance covering architecture design, security, connectivity, and production patterns. Based on the official AWS VPC documentation and best practices.

## When to Use This Skill

**Activate this skill when:**
- Designing VPC architecture (CIDR planning, subnet layout, multi-AZ)
- Configuring security groups, NACLs, or routing
- Setting up internet access (IGW, NAT Gateway, Egress-Only IGW)
- Connecting VPCs (peering, Transit Gateway)
- Connecting on-premises networks (Site-to-Site VPN, Direct Connect)
- Accessing AWS services privately (VPC Endpoints)
- Troubleshooting network connectivity issues
- Reviewing network security posture
- Planning IP address space (IPv4/IPv6, BYOIP)
- Monitoring and observability (Flow Logs, Traffic Mirroring)

**Don't use this skill for:**
- General AWS IAM or compute questions unrelated to networking
- Application-level networking (load balancer routing rules, etc.) unless VPC context is involved

---

## Core Concepts

### VPC Fundamentals

A **VPC (Virtual Private Cloud)** is a logically isolated virtual network within an AWS Region. Key facts:

- Spans all Availability Zones in a Region
- CIDR block range: /16 (65,536 IPs) to /28 (16 IPs)
- Supports both IPv4 and IPv6
- **Default VPC**: Pre-created per Region; has IGW attached, public subnets in each AZ, instances get public IPs automatically
- **Custom VPCs**: Fully controlled; recommended for production workloads

**Reserved IPs per subnet** (AWS always reserves 5 addresses):
| Offset | Purpose |
|--------|---------|
| .0 | Network address |
| .1 | VPC router |
| .2 | AWS DNS |
| .3 | Reserved for future use |
| .255 | Network broadcast |

> A /28 subnet has 16 IPs but only 11 usable. Always account for reserved addresses.

---

### Subnet Architecture

Subnets live in a **single Availability Zone**. Design for high availability by deploying subnets across multiple AZs.

**Subnet types by routing behavior:**

| Type | Route to IGW | Internet Access |
|------|-------------|-----------------|
| Public | Yes | Inbound + Outbound |
| Private | No (routes through NAT) | Outbound only |
| Isolated | No | None |

**Recommended multi-tier layout:**
```
VPC: 10.0.0.0/16
├── AZ-1a
│   ├── Public:    10.0.0.0/24   (web/ALB)
│   ├── Private:   10.0.10.0/24  (app/compute)
│   └── Isolated:  10.0.20.0/24  (databases)
├── AZ-1b
│   ├── Public:    10.0.1.0/24
│   ├── Private:   10.0.11.0/24
│   └── Isolated:  10.0.21.0/24
└── AZ-1c
    ├── Public:    10.0.2.0/24
    ├── Private:   10.0.12.0/24
    └── Isolated:  10.0.22.0/24
```

**CIDR sizing guidance:**
- Use /24 or larger for most workloads — gives room for growth
- Reserve larger CIDR blocks for private subnets (more instances)
- Leave unallocated space in the VPC CIDR for future subnets
- Avoid overlapping CIDRs with on-premises networks if hybrid connectivity is planned

---

### Route Tables

Route tables control where traffic is directed from subnets and gateways.

**Key rules:**
- Every subnet is associated with exactly one route table
- A route table can be associated with multiple subnets
- The most specific route (longest prefix match) wins
- IPv4 and IPv6 require separate route entries

**Common route table patterns:**

Public subnet route table:
```
Destination      Target
10.0.0.0/16      local
0.0.0.0/0        igw-xxxxxxxxx
::/0             igw-xxxxxxxxx  (if IPv6)
```

Private subnet route table (with NAT):
```
Destination      Target
10.0.0.0/16      local
0.0.0.0/0        nat-xxxxxxxxx
```

Isolated subnet route table:
```
Destination      Target
10.0.0.0/16      local
```

---

### Internet Connectivity

#### Internet Gateway (IGW)
- Horizontally scaled, redundant, and highly available — no bandwidth constraints
- Enables **bidirectional** internet connectivity for instances with public IPs
- One IGW per VPC
- Must be attached to the VPC AND the subnet's route table must route to it
- Instance also needs a public IPv4 or Elastic IP

#### NAT Gateway
- Allows **outbound-only** internet access for private subnet resources
- Managed by AWS — no administration required
- Deploy one NAT Gateway **per AZ** for high availability (NAT Gateways are AZ-scoped)
- Costs money: hourly charge + per-GB data processing
- Supports IPv4 only; for IPv6 use Egress-Only IGW

```
Private instance → NAT Gateway (public subnet) → IGW → Internet
```

**NAT Gateway vs NAT Instance:**
| | NAT Gateway | NAT Instance |
|---|---|---|
| Availability | AWS-managed, highly available | Self-managed EC2 |
| Bandwidth | Up to 100 Gbps | Instance type limited |
| Cost | Higher (managed) | Lower (but operational overhead) |
| Recommendation | Use for all new deployments | Legacy only |

#### Egress-Only Internet Gateway
- IPv6 equivalent of NAT Gateway
- Allows outbound IPv6 traffic; blocks unsolicited inbound
- No charge (unlike NAT Gateway)

---

### Security: Security Groups

Security Groups are **stateful, instance-level firewalls**.

**Key behaviors:**
- Applied to ENIs (Elastic Network Interfaces), not subnets
- **Stateful**: Return traffic is automatically allowed
- Only **allow** rules — no deny rules
- All outbound traffic allowed by default (on new SGs)
- Multiple SGs can be applied to one instance
- SG rules can reference other SG IDs (not just CIDRs)

**Best practices:**
```
✅ DO:
- Use least-privilege rules (specific ports/sources)
- Reference SG IDs for inter-tier traffic (e.g., allow ALB SG → App SG)
- Name SGs descriptively (e.g., "web-tier-sg", "db-sg")
- Regularly audit unused rules

❌ DON'T:
- Open 0.0.0.0/0 to SSH/RDP (use SSM Session Manager instead)
- Use a single catch-all SG for all resources
- Open all ports between tiers — only allow what's needed
```

**Common pattern — 3-tier web app:**
```
ALB SG:        Inbound: 443 from 0.0.0.0/0
App SG:        Inbound: 8080 from ALB SG
DB SG:         Inbound: 5432 from App SG
```

---

### Security: Network ACLs (NACLs)

NACLs are **stateless, subnet-level firewalls**.

**Key behaviors:**
- Applied at the subnet boundary
- **Stateless**: Must explicitly allow both inbound AND outbound (including ephemeral ports)
- Supports both **allow** and **deny** rules
- Rules evaluated in order (lowest number first) — first match wins
- Default NACL allows all traffic; custom NACLs deny all by default

**Ephemeral port ranges** (must allow for return traffic):
| Client OS | Ephemeral Port Range |
|-----------|---------------------|
| Linux | 32768–60999 |
| Windows | 49152–65535 |
| AWS NAT Gateway | 1024–65535 |

**NACLs vs Security Groups — when to use which:**

| Use Case | Tool |
|----------|------|
| Primary access control | Security Groups |
| Block specific IPs/CIDRs | NACLs (use deny rules) |
| Defense-in-depth second layer | NACLs |
| Subnet-wide policy enforcement | NACLs |

**NACLs cannot block:**
- Route 53 Resolver DNS (VPC+2 address) — use Route 53 Resolver DNS Firewall instead
- EC2 Instance Metadata Service (IMDS)
- DHCP, Time Sync Service, Windows license activation

---

### VPC-to-VPC Connectivity

#### VPC Peering
- Direct, private connection between two VPCs
- Can peer across Regions and accounts
- **Not transitive** — if A↔B and B↔C, A cannot reach C through B
- No bandwidth bottleneck or single point of failure
- Both VPCs must have non-overlapping CIDR blocks
- Requires route table entries + SG rules on both sides

**When to use:** Small number of VPC-to-VPC connections, simple topology.

#### Transit Gateway (TGW)
- Regional hub-and-spoke router
- Connects: VPCs, VPN connections, Direct Connect gateways, other TGWs (peering)
- **Transitive routing** — all attached VPCs can communicate (by default)
- Supports thousands of attachments
- Supports route tables for traffic segmentation
- Costs: hourly attachment fee + per-GB data transfer

**When to use:** Many VPCs, hybrid connectivity, complex routing requirements.

```
              ┌─────────────────┐
   VPC-A ─────┤                 ├──── On-Premises (VPN)
   VPC-B ─────┤ Transit Gateway ├──── Direct Connect
   VPC-C ─────┤                 ├──── TGW (another Region)
              └─────────────────┘
```

**VPC Peering vs Transit Gateway:**
| | VPC Peering | Transit Gateway |
|---|---|---|
| Transitive routing | No | Yes |
| Max connections | N*(N-1)/2 | Thousands |
| Cost | Free (data transfer costs) | Attachment + data fees |
| Use case | Few VPCs | Many VPCs / hybrid |

---

### Hybrid Connectivity

#### AWS Site-to-Site VPN
- IPsec VPN over the internet
- **Two tunnels** per VPN connection (for redundancy) — always configure both
- Terminates on a **Virtual Private Gateway** (VGW) attached to the VPC, or a **Transit Gateway**
- Customer gateway: your on-premises VPN device
- Bandwidth: up to ~1.25 Gbps per tunnel
- Use when: quick setup, cost-sensitive, internet latency acceptable

#### AWS Direct Connect (DX)
- Dedicated private network connection from on-premises to AWS
- **Not encrypted by default** — use MACsec or IPsec over DX for encryption
- Consistent latency, higher bandwidth (1 Gbps to 100 Gbps)
- Use when: consistent performance, large data transfers, compliance requirements
- Redundancy: order multiple DX connections in active/active or active/passive

**Hybrid connectivity best practice:**
- Use Direct Connect as primary + Site-to-Site VPN as backup
- Terminate both on Transit Gateway for centralized management

---

### VPC Endpoints

VPC Endpoints allow private connectivity to AWS services **without internet gateway, NAT, or VPN**.

#### Gateway Endpoints
- Free of charge
- Supports: **S3** and **DynamoDB** only
- Added as a route in the route table
- Policy-based access control

#### Interface Endpoints (AWS PrivateLink)
- Creates an ENI with a private IP in your subnet
- Supports 100+ AWS services (SSM, Secrets Manager, ECR, SQS, etc.)
- Hourly cost per endpoint + per-GB data
- Can restrict access using endpoint policies
- Use for: keeping service traffic off the internet, compliance requirements

**When to use which:**
```
S3 or DynamoDB from private subnet → Gateway Endpoint (free)
Any other AWS service from private subnet → Interface Endpoint
Cross-account private service exposure → PrivateLink
```

---

### IP Addressing

#### IPv4
- **Private (RFC 1918):** 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 — no charge
- **Public IPv4:** Charged ($0.005/hr per IP, ~$3.65/mo) — minimize public IPs
- **Elastic IP (EIP):** Static public IPv4; charged when not associated with a running instance
- **BYOIP:** Bring your own public IP ranges to AWS

#### IPv6
- All IPv6 addresses are publicly routable (no private IPv6 equivalent)
- Use Egress-Only IGW to control outbound-only access
- No NAT for IPv6
- Free to use (no charge for IPv6 addresses)
- Dual-stack (IPv4 + IPv6) supported on VPCs and subnets

---

### Monitoring & Observability

#### VPC Flow Logs
- Captures metadata about IP traffic (not packet contents) to/from ENIs, subnets, or VPCs
- Destinations: CloudWatch Logs, S3, Kinesis Data Firehose
- Versions: v2 (default) through v7 with increasingly rich fields
- **Common use cases:** Security analysis, troubleshooting connectivity, compliance auditing
- Cost: CloudWatch ingestion + storage, S3 storage

**Flow log record fields (v2):**
```
version account-id interface-id srcaddr dstaddr srcport dstport protocol packets bytes start end action log-status
```

**Reading flow logs for troubleshooting:**
- `ACCEPT` = traffic was allowed by SG + NACL
- `REJECT` = traffic was blocked by SG or NACL
- No record = traffic never reached the interface (check routing)

#### Traffic Mirroring
- Copies actual packet data from ENIs to inspection appliances
- Use for: IDS/IPS, deep packet inspection, forensics
- Source and destination must be in same VPC (or peered/TGW connected)
- Additional cost per mirrored session

#### Network Access Analyzer
- Identifies unintended network access paths to resources
- Finds overly permissive configurations before they're exploited

#### AWS Network Firewall
- Managed stateful firewall deployed inside your VPC
- Supports: domain filtering, intrusion detection/prevention (IPS/IDS), stateful rules
- Deploy in a dedicated "firewall" subnet; route traffic through it

---

## Architecture Patterns

### Single-Region Multi-AZ (Standard Production)
```
Region: us-east-1
VPC: 10.0.0.0/16

          AZ-1a              AZ-1b              AZ-1c
    ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
    │ Public /24   │   │ Public /24   │   │ Public /24   │
    │  ALB, NAT GW │   │  ALB, NAT GW │   │  ALB, NAT GW │
    ├──────────────┤   ├──────────────┤   ├──────────────┤
    │ Private /24  │   │ Private /24  │   │ Private /24  │
    │  App servers │   │  App servers │   │  App servers │
    ├──────────────┤   ├──────────────┤   ├──────────────┤
    │ Isolated /24 │   │ Isolated /24 │   │ Isolated /24 │
    │  RDS, Cache  │   │  RDS, Cache  │   │  RDS, Cache  │
    └──────────────┘   └──────────────┘   └──────────────┘
           │
    Internet Gateway
           │
        Internet
```

### Hub-and-Spoke (Multi-VPC Enterprise)
```
Shared Services VPC ──┐
Production VPC ────────┤
Staging VPC ───────────┼── Transit Gateway ── On-Premises (DX + VPN)
Dev VPC ───────────────┤
Security/Inspection ───┘
```

### VPC Endpoint Strategy for Private Workloads
```
Private EC2
    │
    ├── S3 access → Gateway Endpoint (free, in route table)
    ├── SSM/Secrets Manager → Interface Endpoints (PrivateLink)
    └── ECR pull → Interface Endpoints (ecr.api + ecr.dkr + s3 gateway)
```

---

## Security Best Practices

1. **Never use the default VPC for production** — create dedicated VPCs
2. **Defense in depth**: Use both Security Groups (primary) + NACLs (secondary)
3. **Eliminate public IPs where possible** — use SSM Session Manager instead of bastion hosts
4. **Least-privilege security groups** — reference SG IDs not CIDRs for inter-tier traffic
5. **Deploy NAT Gateway per AZ** — one shared NAT Gateway is a single point of failure
6. **Enable VPC Flow Logs** on all production VPCs — send to S3 for cost efficiency
7. **Use VPC Endpoints** for S3/DynamoDB and sensitive service access
8. **Plan CIDR blocks carefully** — overlapping CIDRs block peering and VPN
9. **Tag everything** — VPCs, subnets, route tables, SGs with environment/team/purpose
10. **Enable AWS Network Firewall** for egress filtering and IPS in regulated environments

---

## Common Troubleshooting

### Connectivity checklist (instance cannot reach destination):

1. **Route table** — Does the subnet's route table have a route to the destination?
2. **Internet Gateway** — Is an IGW attached to the VPC and in the route table?
3. **Public IP** — Does the instance have a public IP or EIP? (for internet access)
4. **Security Group** — Do inbound rules on destination allow the traffic? Outbound on source?
5. **NACL** — Do both inbound AND outbound rules on both subnets allow the traffic (including ephemeral ports)?
6. **OS firewall** — Is iptables/Windows Firewall blocking inside the instance?
7. **Flow Logs** — Check for ACCEPT/REJECT records to pinpoint the block

### Common mistakes:
| Symptom | Likely Cause |
|---------|-------------|
| Instance unreachable from internet | Missing IGW, no public IP, SG blocks port |
| Private instance can't reach internet | No NAT Gateway, missing route, NAT GW in wrong subnet |
| VPC peering not working | Missing route table entries on both sides, SG doesn't allow |
| S3 access slow from private subnet | Using internet path instead of Gateway Endpoint |
| NACLs seem to block despite correct rules | Forgot to allow ephemeral port range for return traffic |
| TGW attachments not routing | Missing TGW route table associations/propagations |
