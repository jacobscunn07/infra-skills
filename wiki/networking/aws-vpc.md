---
title: AWS VPC
tags: [vpc, networking, subnets, routing, security-groups, nacl, nat-gateway, igw, vpc-endpoints, vpc-peering, flow-logs, dns]
related: ["[[Compute/AWS EC2]]", "[[Compute/AWS ECS]]", "[[Storage/AWS EFS]]", "[[Networking/AWS CloudFront]]", "[[Networking/AWS Global Accelerator]]", "[[Observability/AWS CloudWatch]]", "[[IAM/AWS IAM]]"]
created: 2026-04-28
updated: 2026-04-28
---

## Overview

Amazon VPC is the foundational AWS networking layer — an isolated virtual network where you launch AWS resources. Every EC2 instance, ECS task, RDS database, and Lambda function (in VPC mode) runs inside a VPC. VPC controls IP addressing, routing, internet access, and security boundaries. Getting VPC design right is a prerequisite for scalable, secure, multi-tier architectures.

## Key Concepts

- **VPC CIDR** — the primary IP address range (e.g., `10.0.0.0/16`). Cannot change after creation; can add up to 5 secondary CIDRs. Min `/28`, max `/16`.
- **Subnet** — a slice of the VPC CIDR bound to a single AZ. First 4 and last IP are reserved by AWS. Deploy subnets across multiple AZs for HA.
- **Route table** — controls where traffic from a subnet is directed. Main route table is the default; create custom ones per subnet tier.
- **Internet Gateway (IGW)** — enables bidirectional internet access; one per VPC. Instances also need a public/EIP assigned.
- **NAT Gateway** — managed outbound-only internet for private subnets; placed in a public subnet with an EIP. Deploy one per AZ for fault tolerance.
- **Security group** — stateful, ENI-level firewall. Default: deny all inbound, allow all outbound. Apply per tier (web, app, db).
- **NACL** — stateless, subnet-level firewall. Lowest rule number wins. Must explicitly allow return traffic (ephemeral ports 1024–65535).
- **VPC Endpoint** — private connectivity to AWS services without leaving the AWS network; two types: Gateway and Interface.
- **VPC Peering** — 1:1 connection between VPCs; not transitive.
- **Flow Logs** — capture 5-tuple metadata for all traffic at VPC, subnet, or ENI level.

## Patterns

### Three-Tier HA Layout

The canonical multi-tier VPC has three subnet layers across at least two AZs:

| Tier | Subnet Type | Route | Resources |
|---|---|---|---|
| Public | Public | `0.0.0.0/0 → IGW` | ALB, NAT Gateway, Bastion |
| Application | Private | `0.0.0.0/0 → NAT GW` | EC2, ECS tasks, Lambda |
| Data | Isolated | No internet route | RDS, ElastiCache, EFS |

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "main" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_nat_gateway" "az1" {
  allocation_id = aws_eip.nat_az1.id
  subnet_id     = aws_subnet.public_az1.id
  depends_on    = [aws_internet_gateway.main]
}
```

### NAT Gateway Per-AZ

Routing each private AZ's traffic through a NAT Gateway in the same AZ avoids cross-AZ data transfer charges and eliminates the NAT as a single point of failure.

```hcl
# Private subnet in AZ1 routes through AZ1 NAT GW
resource "aws_route" "private_az1_nat" {
  route_table_id         = aws_route_table.private_az1.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.az1.id
}
```

### VPC Endpoints for AWS Services

Always create VPC endpoints for services used heavily in private subnets — eliminates NAT Gateway data processing costs and keeps traffic on the AWS backbone.

**Gateway Endpoints (free):** S3 and DynamoDB. Added as route table entries.

```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_az1.id, aws_route_table.private_az2.id]
}
```

**Interface Endpoints (hourly charge):** All other AWS services (SSM, ECR, Secrets Manager, KMS, CloudWatch Logs, etc.). Creates an ENI per AZ; use `private_dns_enabled = true` so existing SDK calls resolve to the private endpoint automatically.

```hcl
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_az1.id, aws_subnet.private_az2.id]
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
}
```

### VPC Peering

1:1 cross-VPC connectivity. Routes must be manually configured on both sides; DNS resolution can be enabled per-peering.

```hcl
resource "aws_vpc_peering_connection" "main" {
  vpc_id        = aws_vpc.requester.id
  peer_vpc_id   = aws_vpc.accepter.id
  peer_owner_id = var.peer_account_id
}

resource "aws_vpc_peering_connection_accepter" "main" {
  vpc_peering_connection_id = aws_vpc_peering_connection.main.id
  auto_accept               = true
}
```

For more than 2–3 VPCs, use Transit Gateway instead — peering meshes grow as O(n²).

### Security Group Referencing

Reference security groups instead of CIDRs where possible — reduces surface area and auto-tracks instance churn:

```hcl
# DB tier: only accept from app tier
resource "aws_security_group_rule" "db_from_app" {
  type                     = "ingress"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.app.id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
}
```

### Flow Logs

Enable at VPC level for production; ship to S3 for cost-effective long-term storage or to CloudWatch Logs for querying with Logs Insights.

```hcl
resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
}
```

## Gotchas

- **VPC CIDR is immutable.** Plan address space before creating. Use large blocks (`/16`) and carve subnets later. Add secondary CIDRs if you run out, but they can't overlap with existing routes.
- **AWS reserves 5 IPs per subnet.** `.0` (network), `.1` (VPC router), `.2` (DNS), `.3` (future use), `.255` (broadcast). A `/28` only yields 11 usable IPs.
- **Changing the main route table affects all un-associated subnets.** Don't treat the main route table as "private" — explicitly associate custom route tables with every subnet.
- **NAT Gateway has no bandwidth limit but does have a per-hour + per-GB cost.** Large data transfers (backups, container image pulls) can be expensive through NAT; use VPC endpoints to bypass for S3 and ECR.
- **VPC peering is not transitive.** A→B peering and B→C peering does not mean A can reach C. Use Transit Gateway for hub-and-spoke multi-VPC routing.
- **No CIDR overlap in peering.** Any overlap in primary or secondary CIDRs makes peering impossible — plan RFC1918 address space across environments to leave room for on-prem and cross-account peering.
- **NACLs are stateless.** You must allow ephemeral ports `1024–65535` for return traffic. Forgetting this breaks all TCP connections through the NACL.
- **Custom NACLs default to DENY all.** Unlike the default NACL (which allows everything), a newly created custom NACL blocks all traffic until rules are added.
- **Security groups are stateful; return traffic is automatically allowed.** Don't duplicate inbound + outbound rules for bidirectional traffic — inbound allow is sufficient for established connections.
- **Interface VPC endpoints need a security group.** The SG on the endpoint ENI must allow port 443 from the resources that call the service.
- **`enableDnsHostnames` and `enableDnsSupport` must both be true** for EC2 instances to get public DNS hostnames. Also required for Interface VPC endpoints to use private DNS.
- **Flow Logs do not capture DHCP, AWS DNS queries, instance metadata (169.254.169.254), or Windows license activation traffic.** Don't rely on them for a complete traffic picture.
- **EIP limit per region is 5 by default.** In multi-AZ setups with one NAT GW per AZ, you'll hit this limit quickly — request a quota increase before deploying.

## Limits & Quotas

| Resource | Default |
|---|---|
| VPCs per region | 5 |
| Subnets per VPC | 200 |
| Route tables per VPC | 200 |
| Routes per route table | 50 |
| Security groups per VPC | 500 |
| Inbound rules per SG | 60 |
| Outbound rules per SG | 60 |
| Network ACLs per VPC | 200 |
| VPC Peering connections per VPC | 50 |
| Elastic IPs per region | 5 |

All can be increased via AWS Service Quotas.

## References

- [[Compute/AWS EC2]]
- [[Compute/AWS ECS]]
- [[Storage/AWS EFS]]
- [[Networking/AWS CloudFront]]
- [[Networking/AWS Global Accelerator]]
- [[Observability/AWS CloudWatch]]
