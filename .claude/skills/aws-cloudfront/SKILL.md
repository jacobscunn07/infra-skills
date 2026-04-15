---
name: aws-cloudfront
description: Use when working with Amazon CloudFront - designing CDN distributions, configuring origins and cache behaviors, TTL and cache invalidation, Origin Access Control (OAC) for S3, signed URLs and signed cookies, WAF integration, Lambda@Edge vs CloudFront Functions, geo-restriction, custom headers, HTTPS/TLS, or any CloudFront architecture and troubleshooting decisions
---

# AWS CloudFront Expert Skill

Comprehensive Amazon CloudFront guidance covering distributions, origins, cache behaviors, security, edge compute, and production patterns. Based on the official AWS CloudFront Developer Guide.

## When to Use This Skill

**Activate this skill when:**
- Designing a CloudFront distribution for a website, API, or media delivery
- Configuring origins (S3, ALB, custom HTTP) and origin groups for failover
- Tuning cache behaviors, TTL, and cache keys
- Setting up Origin Access Control (OAC) to lock down S3 origins
- Implementing signed URLs or signed cookies for private content
- Integrating AWS WAF with CloudFront for edge-layer protection
- Choosing between Lambda@Edge and CloudFront Functions
- Configuring HTTPS, custom TLS certificates, and security policies
- Troubleshooting cache misses, 403/404 errors, or origin errors

**Don't use this skill for:**
- Global Accelerator (TCP/UDP network acceleration) — use aws-global-accelerator skill
- S3 bucket configuration and access control — use aws-s3 skill
- WAF rule writing in depth — use aws-waf skill

---

## Core Concepts

CloudFront is a global CDN with **400+ Points of Presence (POPs)** across 90+ cities. It serves cached content from the edge nearest to the viewer, reducing latency and offloading traffic from your origin.

### Request Flow

```
Viewer request
    │
    ▼
CloudFront edge (POP)
    │ Cache hit? → Serve from edge (no origin contact)
    │ Cache miss?
    ▼
Origin request (S3 / ALB / custom HTTP)
    │
    ▼
Origin response → Cached at edge (if cacheable) → Returned to viewer
```

### Data Transfer Pricing

- **Origin → CloudFront:** Free for AWS origins (S3, ALB, API Gateway, EC2)
- **CloudFront → Viewers:** Charged per GB (varies by region)
- **CloudFront → Origin (cache misses):** Free for AWS origins; charged for non-AWS

---

## Distributions

A distribution is the top-level CloudFront resource. It gets a domain like `d111111abcdef8.cloudfront.net` (or your custom domain).

### Key Distribution Settings

| Setting | Notes |
|---------|-------|
| **Alternate domain names (CNAMEs)** | Your custom domain (e.g., `cdn.example.com`); requires matching ACM certificate |
| **SSL certificate** | Must be in `us-east-1` (ACM global certificate for CloudFront); use TLSv1.2_2021 or higher security policy |
| **HTTP/HTTPS** | Always redirect HTTP → HTTPS; never serve over HTTP in production |
| **IPv6** | Enable unless you have a specific reason not to |
| **Price class** | `PriceClass_All` (best performance, highest cost) or restrict to specific regions to reduce cost |
| **Logging** | Standard logs → S3; Real-time logs → Kinesis Data Streams for sub-minute latency |

---

## Origins

An origin is where CloudFront fetches content on a cache miss. A distribution can have up to **25 origins**.

### S3 Origin (Recommended: OAC)

Use **Origin Access Control (OAC)** — not the legacy OAI — to keep the S3 bucket fully private while allowing CloudFront to read it.

```json
{
  "Origins": [{
    "Id": "my-s3-origin",
    "DomainName": "my-bucket.s3.us-east-1.amazonaws.com",
    "S3OriginConfig": { "OriginAccessIdentity": "" },
    "OriginAccessControlId": "E1234567890ABC"
  }]
}
```

S3 bucket policy to allow OAC:
```json
{
  "Effect": "Allow",
  "Principal": { "Service": "cloudfront.amazonaws.com" },
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3:::my-bucket/*",
  "Condition": {
    "StringEquals": {
      "AWS:SourceArn": "arn:aws:cloudfront::ACCOUNT:distribution/DIST_ID"
    }
  }
}
```

Keep `Block Public Access` ON for the bucket — CloudFront access goes through OAC, not public.

### ALB / Custom HTTP Origin

```json
{
  "Origins": [{
    "Id": "my-alb-origin",
    "DomainName": "my-alb-123.us-east-1.elb.amazonaws.com",
    "CustomOriginConfig": {
      "HTTPSPort": 443,
      "OriginProtocolPolicy": "https-only",
      "OriginSSLProtocols": ["TLSv1.2"]
    },
    "CustomHeaders": [{
      "HeaderName": "X-Origin-Secret",
      "HeaderValue": "mysecret"
    }]
  }]
}
```

**Custom origin secret header:** CloudFront sends a secret header to the ALB; the ALB security group or WAF only accepts requests containing it. This prevents viewers from bypassing CloudFront and hitting the ALB directly.

### Origin Groups (Failover)

Define a primary and secondary origin. If the primary returns a 5xx or times out, CloudFront automatically retries against the secondary.

```
Primary: ALB in us-east-1
Failover: ALB in us-west-2
Condition: HTTP 500, 502, 503, 504
```

---

## Cache Behaviors

A cache behavior maps a URL path pattern to an origin and defines caching rules. Behaviors are evaluated in order — the first match wins. The default (`*`) behavior is always evaluated last.

### Cache Behavior Settings

| Setting | Description |
|---------|-------------|
| **Path pattern** | `images/*`, `/api/*`, `*.css`, `*` (default) |
| **Origin** | Which origin to forward cache misses to |
| **Viewer protocol policy** | `redirect-http-to-https` (always use this) |
| **Cache policy** | Controls TTL, cache key (headers/cookies/query strings included in key) |
| **Origin request policy** | What to forward to origin (may differ from cache key) |
| **Response headers policy** | Add security headers (HSTS, CSP, X-Frame-Options) to responses |
| **Edge function** | Lambda@Edge or CloudFront Function association |

### TTL Configuration

CloudFront respects `Cache-Control` and `Expires` headers from the origin. The cache policy sets minimum, maximum, and default TTL:

| Scenario | TTL Strategy |
|----------|-------------|
| Static assets (JS, CSS, images with hash in name) | Max TTL: 1 year; immutable; no invalidation needed |
| HTML pages | Short TTL (60–300s) or no-cache; use `Cache-Control: no-cache` for dynamic pages |
| API responses | `Cache-Control: no-store` for personalized; short TTL for shared cacheable responses |
| S3 static site | Default TTL: 24h; configure per-object headers as needed |

**Cache invalidation:** `aws cloudfront create-invalidation --paths "/*"` — charged per path (first 1,000/month free). Use versioned filenames (`app.a1b2c3.js`) instead of invalidation wherever possible.

### Cache Key Design

The cache key determines whether two requests are served the same cached object. Include only what actually changes the response:

- **Good:** Include `Accept-Encoding` (compress), `CloudFront-Is-Mobile-Viewer` (responsive)
- **Bad:** Including `Cookie` or `Authorization` header usually means a cache miss every time — send those to origin via the origin request policy without including in cache key

---

## Security

### HTTPS and TLS

- Always use ACM certificates (free, auto-renew) in `us-east-1`
- Security policy: use `TLSv1.2_2021` or `TLSv1.2_2019` minimum — never allow TLS 1.0 or 1.1
- Enable **HTTP Strict Transport Security (HSTS)** via response headers policy

### AWS WAF Integration

Attach a WAF Web ACL (must be in `us-east-1` for CloudFront):

```
CloudFront distribution → WAF Web ACL
  Rules:
    - AWS Managed Rules (Core, Known Bad Inputs)
    - Rate limiting (e.g., 2000 req/5min per IP)
    - Geo block (block specific countries)
    - Bot control
```

WAF runs at the edge — blocks bad traffic before it reaches your origin.

### Signed URLs and Signed Cookies

Restrict access to content to only authenticated viewers.

| | Signed URL | Signed Cookie |
|--|-----------|--------------|
| **Use for** | One file at a time | Multiple files / entire section |
| **Example** | Download link for one video | Premium subscriber accessing `/premium/*` |
| **Mechanism** | URL contains signature + expiry | Cookie sent with all requests |

**Signed URL structure:**
```
https://d111.cloudfront.net/video.mp4
?Expires=1735689600
&Signature=...
&Key-Pair-Id=APKA...
```

Requires a **CloudFront key group** and a **trusted key pair** (RSA 2048-bit). Your app signs the URL server-side; the private key never leaves your app.

### Geo-Restriction

Block or allow specific countries:
```json
"Restrictions": {
  "GeoRestriction": {
    "RestrictionType": "blacklist",
    "Locations": ["CN", "RU", "KP"]
  }
}
```

For fine-grained geo logic (redirect based on country), use CloudFront Functions to inspect `CloudFront-Viewer-Country` header.

---

## Edge Compute

### CloudFront Functions vs Lambda@Edge

| | CloudFront Functions | Lambda@Edge |
|--|---------------------|-------------|
| **Runtime** | JavaScript (ES5.1) | Node.js, Python |
| **Execution location** | 400+ edge POPs | ~13 regional edge caches |
| **Max duration** | 1ms | 5s (viewer) / 30s (origin) |
| **Memory** | 2 MB | 128 MB – 10 GB |
| **Request access** | Headers, URL, cookies, query strings | Full request + response body |
| **Cost** | ~6× cheaper | More expensive |
| **Use for** | URL rewrites, redirects, header manipulation, A/B testing | Auth (JWT validation), image resize, complex routing |

### CloudFront Function Examples

URL rewrite (remove `/v1` prefix before forwarding to origin):
```javascript
function handler(event) {
  var request = event.request;
  request.uri = request.uri.replace(/^\/v1/, '');
  return request;
}
```

Redirect old paths:
```javascript
function handler(event) {
  var request = event.request;
  if (request.uri === '/old-path') {
    return {
      statusCode: 301,
      statusDescription: 'Moved Permanently',
      headers: { location: { value: '/new-path' } }
    };
  }
  return request;
}
```

### Lambda@Edge Trigger Points

```
Viewer request  → runs before CloudFront cache check
Origin request  → runs on cache miss, before forwarding to origin
Origin response → runs after origin responds, before caching
Viewer response → runs before returning to viewer
```

Use **viewer request** for auth (validate JWT before serving anything). Use **origin response** for adding security headers to cacheable responses.

---

## Architecture Patterns

### Static Website / SPA

```
Viewers → CloudFront
  Behaviors:
    /api/*   → ALB origin, no-cache, no WAF bypass
    *        → S3 origin (OAC), 1-year TTL for hashed assets, short TTL for index.html
  Security:
    WAF: managed rules + rate limit
    OAC: S3 bucket private
    HTTPS: TLS 1.2+, HSTS header
  Edge function (CF Function):
    Viewer request: rewrite /app/* to /index.html (SPA routing)
```

### API Acceleration

```
Viewers → CloudFront
  Behavior: /api/*
  Cache policy: no-store (personalized API responses)
  Origin request policy: forward Authorization header to origin
  Custom header: X-Origin-Secret (prevent ALB direct access)
  WAF: rate limiting + bot control
  ALB: security group allows only CloudFront managed prefix list
```

### Multi-Origin with Failover

```
Origin group:
  Primary: ALB us-east-1
  Failover: ALB us-west-2 (triggered on 5xx)
  
Combined with Route 53 latency routing for regional failover at DNS level.
```

---

## Security Best Practices

1. **OAC for all S3 origins** — never public buckets; always OAC + Block Public Access on
2. **Custom origin secret** — send a secret header to ALB/custom origins; block direct access at SG or WAF
3. **HTTPS-only** — redirect HTTP → HTTPS; use `TLSv1.2_2021` security policy
4. **Enable WAF** — attach a Web ACL with at minimum AWS Managed Rules Core set and a rate limit rule
5. **Response headers policy** — add `Strict-Transport-Security`, `X-Content-Type-Options`, `X-Frame-Options`, `Content-Security-Policy`
6. **Geo-restriction** — block countries you don't serve if feasible (reduces attack surface)
7. **Signed URLs/cookies for private content** — never expose private S3 content via public CloudFront without signing

---

## Common Troubleshooting

| Symptom | Likely Cause |
|---------|-------------|
| `403 Access Denied` from S3 origin | OAC not configured; or S3 bucket policy doesn't allow CloudFront service principal; or Block Public Access blocking the policy |
| Cache miss on every request | Cache key includes headers/cookies that vary per request (e.g., `Authorization`); or `Cache-Control: no-store` from origin |
| Origin receiving `X-Forwarded-For` loop | Multiple proxies; CloudFront appends to existing header — origin should read the rightmost untrusted IP |
| Viewers getting stale content after deploy | Content wasn't invalidated; use versioned filenames to avoid this; run `create-invalidation` as a deploy step |
| `502 Bad Gateway` from CloudFront | Origin unreachable; TLS handshake failure between CloudFront and origin; check origin's certificate CN matches the `DomainName` in the origin config |
| WAF blocking legitimate traffic | WAF rule too broad; check WAF sampled requests in console to identify which rule triggered; add IP allow-list for known good IPs |
| Lambda@Edge function not executing | Wrong event trigger point; or function deployed in wrong region (must deploy to `us-east-1`, CloudFront replicates) |
