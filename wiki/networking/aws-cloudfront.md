---
title: AWS CloudFront
tags: [cloudfront, cdn, edge, caching, oac, lambda-edge, waf, signed-urls]
related: ["[[Storage/AWS S3]]", "[[IAM/IAM Policies]]", "[[Compute/AWS ECS]]", "[[Networking/AWS Global Accelerator]]"]
created: 2026-04-28
updated: 2026-04-28
---

## Overview

Amazon CloudFront is a global CDN that caches and delivers content from edge locations (Points of Presence) close to viewers. Requests route over the AWS backbone, reducing latency. Static assets, dynamic API responses, and streaming media can all pass through CloudFront. It integrates natively with S3, ALB, API Gateway, and custom HTTP origins.

## Key Concepts

- **Distribution** — the CloudFront configuration unit; assigned a `*.cloudfront.net` domain at creation. Attach custom domains via CNAME + ACM certificate.
- **Origin** — the source of truth for content: S3 bucket, ALB, API Gateway, EC2, or any HTTPS endpoint.
- **Cache behavior** — path-pattern rules (e.g., `/api/*`, `/static/*`) that map to an origin and control caching, headers, and edge functions.
- **Edge location (POP)** — where content is cached. Regional Edge Caches sit between POPs and origins as a second-tier cache.
- **Cache key** — the unique identifier for a cached object; determines cache hits. Fewer components in the key → higher hit ratio.
- **TTL** — how long an object stays in the edge cache. Controlled by `Cache-Control`/`Expires` headers from origin OR overridden by the cache policy's min/max/default TTL settings.

## Patterns

### Origin Access Control (OAC) for S3

OAC is the **recommended** way to restrict S3 bucket access to CloudFront only. It replaces the legacy Origin Access Identity (OAI).

| Feature | OAC | OAI (legacy) |
|---|---|---|
| Post-Dec 2022 opt-in Regions | ✅ | ❌ |
| SSE-KMS encrypted objects | ✅ | ❌ |
| PUT/DELETE (upload via CF) | ✅ | ❌ |
| Status | Recommended | Legacy |

**S3 bucket policy for OAC (read-only):**
```json
{
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "cloudfront.amazonaws.com" },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::my-bucket/*",
    "Condition": {
      "StringEquals": {
        "AWS:SourceArn": "arn:aws:cloudfront::123456789012:distribution/EDFDVBD6EXAMPLE"
      }
    }
  }]
}
```

For SSE-KMS buckets, the CloudFront service principal also needs `kms:Decrypt` (and `kms:Encrypt`/`kms:GenerateDataKey*` for uploads) in the **KMS key policy** — the S3 bucket policy alone is not sufficient.

OAC signing behaviors:
- `always` — signs all requests; HTTPS between CloudFront and S3 is enforced (recommended).
- `never` — disables signing; S3 bucket must be public.
- `no-override` — signs only when the viewer request lacks an `Authorization` header. You **must** add `Authorization` to the cache policy or caching breaks.

**OAI → OAC migration:** add both statements to the bucket policy simultaneously, switch the distribution origin setting, wait for deploy to complete, then remove the OAI statement.

### Cache Policies

Attach a cache policy to each cache behavior instead of using legacy forwarding settings.

**AWS Managed cache policies:**

| Policy | ID | Default TTL | Cache Key |
|---|---|---|---|
| `CachingOptimized` | `658327ea-f89d-4fab-a63d-7e88639e58f6` | 86,400 s (24 h) | `Accept-Encoding` only |
| `CachingDisabled` | `4135ea2d-6df8-44a3-9df3-4b5a84be39ad` | 0 s | Nothing |
| `CachingOptimizedForUncompressedObjects` | `b2884449-e4de-46a7-ac36-70bc7f1ddd6d` | 86,400 s | None |
| `UseOriginCacheControlHeaders` | `83da9c7e-98b4-4e11-a168-04f0df8e2c65` | 0 s | Host, Origin, X-HTTP-Method* |
| `UseOriginCacheControlHeaders-QueryStrings` | `4cc15a8a-d715-48a4-82b8-cc0b614638fe` | 0 s | Host, Origin, X-HTTP-Method*, all QS |
| `Amplify` | `2e54312d-136d-493c-8eb9-b001f22f67d2` | 2 s | Authorization, CF-Viewer-Country, Host, all cookies/QS |

Use `CachingDisabled` for API/dynamic endpoints (equivalent to "no caching"). Use `CachingOptimized` for S3-served static assets.

**Warning:** Policies with `min TTL > 0` (e.g., `CachingOptimized`) will cache objects even if origin returns `Cache-Control: no-cache, no-store, private`.

### CloudFront Functions vs Lambda@Edge

| Feature | CloudFront Functions | Lambda@Edge |
|---|---|---|
| Runtime | JavaScript (ES 5.1) | Node.js, Python |
| Events | Viewer request, Viewer response | Viewer req/res + **Origin req/res** |
| Max duration | Sub-millisecond | 30 seconds |
| Max memory | 2 MB | 128 MB (viewer) / 10 GB (origin) |
| Max code size | 10 KB | 50 MB |
| Network access | ❌ | ✅ |
| File system access | ❌ | ✅ |
| Request body access | ❌ | ✅ |
| Geo/device data | ✅ | Viewer events: ❌ / Origin events: ✅ |
| CloudFront KeyValueStore | ✅ (JS Runtime 2.0) | ❌ |
| Scale | Millions req/s | 10,000 req/s per Region |

**When to use CloudFront Functions:** cache key normalization, header manipulation, URL rewriting, JWT validation at the edge.

**When to use Lambda@Edge:** responses requiring external API calls, complex auth flows, origin selection logic, anything needing >10 KB of code or >2 MB memory.

Lambda@Edge functions must be created in **us-east-1** regardless of origin region.

### Signed URLs and Signed Cookies

Restrict access to private content using either signed URLs (per-object) or signed cookies (multiple objects / entire distribution path).

Use **trusted key groups** (not legacy trusted signers) — upload public keys to CloudFront and reference key group IDs in the distribution config.

**Canned policy** (simpler, shorter URL):
- Set an expiration date/time.
- Cannot restrict by IP or set a start time.

**Custom policy** (more flexible, longer URL):
- Optional start time, optional IP CIDR restriction, required expiration.

**Critical TTL gotcha:** CloudFront validates the signed URL/cookie only at request time, not mid-download. A download started before expiry will complete. However, each HTTP range-GET is validated separately — an expired signed URL will fail range requests even if the initial request succeeded.

**Query string gotcha:** Adding query parameters to a signed URL *after* signing returns HTTP 403. Sign the full URL including any query parameters.

### HTTPS / TLS Security Policies

CloudFront security policies determine the minimum TLS version and cipher suites.

| Policy | Min TLS | Notes |
|---|---|---|
| `TLSv1.3_2025` | TLS 1.3 only | Most restrictive; recommended for modern apps |
| `TLSv1.2_2021` | TLS 1.2 | Good compatibility baseline |
| `TLSv1.2_2018` | TLS 1.2 | Broader cipher support |
| `TLSv1.1_2016` | TLS 1.1 | Legacy; avoid |
| `TLSv1_2016`, `TLSv1`, `SSLv3` | TLS 1.0 / SSL 3.0 | Deprecated; avoid |

TLS 1.3 policies support quantum-safe key exchanges (`X25519MLKEM768`, `SecP256r1MLKEM768`).

Custom SSL certificates must be provisioned in **us-east-1** via ACM (regardless of origin region). CloudFront uses SNI by default; dedicated IP (legacy) costs extra.

### WAF Integration

Associate an AWS WAF web ACL with the distribution to block OWASP Top 10 attacks, rate-limit, and filter by IP or geo. WAF web ACLs for CloudFront must be created in **us-east-1** (WAFv2 global scope) — they cannot be regional ACLs.

Enable the **Security dashboard** in the CloudFront console to see WAF metrics and configure geo-restrictions in one place.

### Geo-Restriction

CloudFront built-in geo-restriction operates at country level only and applies to the entire distribution (not per cache behavior).

- **Allowlist** — serve only to listed countries.
- **Blocklist** — block listed countries, allow all others.
- Blocked requests return HTTP 403 (configurable to a custom error page).
- IP-to-country lookup accuracy: ~99.8%. Unknown locations are served.

For city/ZIP/coordinate-level control, use a third-party geo service (MaxMind, Digital Element) with signed URLs to gate access at the application layer.

### Cache Invalidation

Invalidation removes objects from edge caches before TTL expiry. The first 1,000 invalidation paths per month are free; additional paths incur a per-path charge.

**Prefer file versioning** (e.g., `app.v2.js`) over frequent invalidations — cheaper, respects browser caches and proxy caches, enables instant rollback.

When invalidation is necessary, wildcard paths (`/static/*`) count as one path against the free tier but invalidate all matching objects.

## Gotchas

- **OAC requires a non-website S3 endpoint.** S3 static website hosting endpoints (`s3-website-*.amazonaws.com`) must be configured as custom origins — OAC is not supported.
- **Lambda@Edge can't use OAC for origin redirects.** OAC is incompatible with Lambda@Edge origin redirect responses.
- **Cache policies with min TTL > 0 override origin `Cache-Control: no-cache`.** Always verify which policy is attached before debugging a "why is stale content cached?" problem.
- **gRPC traffic is not cacheable.** Cache policy settings have no effect on gRPC requests.
- **ACM certificates and WAF web ACLs for CloudFront must be in us-east-1.** Creating them in any other region means they won't appear in the CloudFront console.
- **Lambda@Edge functions must be authored in us-east-1.** Replicas are automatically created in edge locations, but the authoritative function lives in us-east-1.
- **Range-GET requests are each validated separately** against signed URL/cookie expiry. A long-lived download broken into range requests will fail if the signed credential expires mid-transfer.
- **Invalidations are not instant.** Propagation to all edge locations typically takes a few minutes.
- **`Authorization` header in cache key for `no-override` OAC signing.** If not added to the cache policy, CloudFront silently serves incorrect cached responses.

## References

- [[Storage/AWS S3]]
- [[IAM/IAM Policies]]
- [[Compute/AWS ECS]]
