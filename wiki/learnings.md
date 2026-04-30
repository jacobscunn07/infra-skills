# Learnings

Append-only log of what worked and what didn't. Add a new dated entry at the end of each session that produced insights. Never edit or delete existing entries.

---

## 2026-04-27

### What Worked
- Extracting S3 User Guide content from PDF keyword metadata (via `strings`) when `pdftotext`/`pdftoppm` are unavailable — the `/Keywords` field in the PDF metadata is comprehensive enough to identify all major topic areas covered in the document.
- Combining the PDF's keyword topic list with the `/aws-s3` skill guidance produced a complete wiki page covering storage classes, access control, encryption, versioning, lifecycle, replication, performance, and architectural patterns in a single pass.

### What Didn't Work
- `pdftotext` and the Read tool's native PDF rendering both failed (poppler not installed); `strings` on the raw binary was the fallback that worked.

---

## 2026-04-27 (EC2)

### What Worked
- Creating a Python venv (`python3 -m venv /tmp/pdfenv`) and installing `pypdf` to extract text from PDFs when system-wide pip installs are blocked by externally-managed-environment restrictions.
- Targeted page-range searches (binary-searching for specific topic keywords) let you extract just the relevant sections from a 3793-page PDF without loading the whole document into context.

### What Didn't Work
- `pdftotext` still not available (poppler not installed). The `strings` fallback produces too much noise from binary/XML content in PDFs — pypdf is significantly better for clean text extraction.

---

## 2026-04-28 (ECR)

### What Worked
- WebFetch handles AWS PDF documentation URLs directly — the tool extracts and summarizes PDF content without needing local PDF tools, making it the fastest path for AWS user guide ingestion.
- Fetching the ECR PDF via WebFetch with a detailed extraction prompt produced a comprehensive single-pass summary covering all major topic areas (lifecycle, scanning, replication, pull-through cache, IAM, OCI artifacts).

### What Didn't Work
- Nothing notable; WebFetch on the AWS PDF docs URL was straightforward.

### Changed Approach
- Previous sessions (S3, EC2) required manual PDF extraction workarounds (`strings`, `pypdf`). For hosted AWS docs PDFs, WebFetch is the preferred approach — no local tooling needed.

---

## 2026-04-28 (ECS)

### What Worked
- When a PDF is too large for WebFetch (ECS Developer Guide exceeds the 10 MB content limit), fetching individual HTML topic pages in parallel produces equally comprehensive coverage — sometimes better, since you can target the most relevant sections.
- Fetching 6 pages in parallel (Welcome, task definitions, task networking, Fargate networking, IAM roles, capacity providers, services) covered all major ECS topics in two rounds.

### What Didn't Work
- Direct WebFetch of the ECS PDF URL (`ecs-dg.pdf`) failed with `maxContentLength size of 10485760 exceeded` — the guide is too large. Fallback to individual HTML pages was required.

### Changed Approach
- For large AWS guides (ECS, EC2, etc.), prefer fetching targeted HTML topic pages over the consolidated PDF. Topic pages return focused, pre-structured content; the PDF path is only worth attempting for smaller guides.

---

## 2026-04-28 (EFS)

### What Worked
- WebFetch on the EFS PDF (`efs-ug.pdf`, ~5.2 MB) succeeded in a single pass — the guide is small enough to avoid the 10 MB limit that blocked ECS.
- A detailed extraction prompt (enumerating file system types, throughput modes, storage classes, access points, mounting options, security, DR, pricing, and failure modes) produced a comprehensive single-pass summary with no follow-up fetches needed.

---

## 2026-04-28 (CloudFront)

### What Worked
- CloudFront PDF (`AmazonCloudFront_DevGuide.pdf`) exceeds the 10 MB WebFetch limit; falling back to targeted HTML topic pages worked well.
- Fetching 7 topic pages in two parallel rounds (OAC/OAI, cache policies, Lambda@Edge, CloudFront Functions, signed URLs, TLS, WAF/geo, invalidation) produced comprehensive coverage of all CloudFront major areas.
- The managed cache policy IDs (GUIDs) are present in the HTML docs and should be copied verbatim into Terraform — do not hand-type them.

### What Didn't Work
- Direct WebFetch of the CloudFront PDF failed with `maxContentLength size of 10485760 exceeded`. Same limit as ECS.

### Changed Approach
- Confirmed the pattern: for any large AWS service guide (CloudFront, ECS, EC2), go straight to individual HTML topic pages rather than attempting the PDF.

---

## 2026-04-28 (CloudWatch)

### What Worked
- CloudWatch user guide PDF (`acw-ug.pdf`) exceeds the 10 MB WebFetch limit; falling back to targeted HTML topic pages produced comprehensive coverage across 6 pages in two parallel rounds.
- Fetching the concepts page, alarms page, Logs page, Logs Insights syntax, anomaly detection, CloudWatch Agent, EMF, cross-account monitoring, and Container Insights pages in parallel covered all major CloudWatch areas completely.
- The CloudWatch concepts page (`cloudwatch_concepts.html`) is particularly dense — it covers namespaces, dimensions, resolution, periods, statistics, retention schedules, and non-obvious behaviors all in one page and is the best starting point for any CloudWatch ingestion.

### What Didn't Work
- Direct WebFetch of the CloudWatch PDF failed with `maxContentLength size of 10485760 exceeded`. Same 10 MB limit as ECS and CloudFront.

### Changed Approach
- Pattern now firmly established: always attempt PDF first, fall back immediately to targeted HTML pages for any large AWS service guide. The HTML path is now the expected path for major services.

---

## 2026-04-28 (Global Accelerator)

### What Worked
- Global Accelerator overview and components pages are concise HTML docs — two targeted fetches (what-is, introduction-components, introduction-benefits-of-migrating) provided complete coverage in a single round.
- The `introduction-benefits-of-migrating` page contains the clearest CloudFront vs. Global Accelerator comparison table in the AWS docs; it's the right starting point for that comparison.

### Changed Approach
- For newer/smaller AWS services like Global Accelerator (not a 1000+ page developer guide), the main `what-is` HTML page plus 1-2 companion pages is sufficient — no PDF fallback needed.

---

## 2026-04-28 (IAM)

### What Worked
- IAM User Guide PDF exceeds the 10 MB WebFetch limit; falling back to 6 targeted HTML topic pages (introduction, policies, roles, evaluation logic, federation, ABAC, Access Analyzer) produced comprehensive coverage in two parallel rounds.
- The evaluation logic page (`reference_policies_evaluation-logic.html`) is the most important single page in the IAM docs — it precisely defines union vs. intersection semantics for every policy type combination and is the right starting point for any policy troubleshooting.
- The policies overview page (`access_policies.html`) covers all seven policy types (identity-based, resource-based, permissions boundary, SCP, RCP, ACL, session) with their key behavioral differences in one place.

### What Didn't Work
- Direct WebFetch of the IAM PDF (`iam-ug.pdf`) failed with `maxContentLength size of 10485760 exceeded`. Same 10 MB limit as ECS/CloudFront/CloudWatch.

### Changed Approach
- Pattern confirmed: large AWS service PDFs always exceed the 10 MB limit. For IAM specifically, the evaluation logic and policies pages are the highest-density starting points; no need to read the full guide linearly.

---

## 2026-04-28 (KMS)

### What Worked
- KMS Developer Guide PDF exceeds the 10 MB WebFetch limit; falling back to 7 targeted HTML topic pages (overview, concepts, key policies, rotation, multi-region, key deletion, VPC endpoints, CloudTrail) produced comprehensive coverage in two parallel rounds.
- The concepts page (`concepts.html`) is the highest-density starting point for KMS — it covers all three key ownership tiers, the internal HBK/domain key/CDK hierarchy, key identifiers, and envelope encryption in one page.
- The key policy overview page (`key-policy-overview.html`) includes working JSON examples for all major patterns (default policy, cross-account, grants) and a clear table of common mistakes — ideal for Terraform key policy authoring.

### What Didn't Work
- Direct WebFetch of the KMS PDF (`kms-dg.pdf`) failed with `maxContentLength size of 10485760 exceeded`. Same 10 MB limit as all large AWS service PDFs.

### Changed Approach
- For KMS specifically, the rotation page is required reading even if you think you know rotation — the billing gotcha (monthly fee charged for first and second rotation, free after that) and the EXTERNAL-origin limitation are not obvious from first principles.

---

## 2026-04-28 (VPC)

### What Worked
- VPC User Guide PDF (`vpc-ug.pdf`, ~6.4 MB) is within the WebFetch limit and succeeded in a single pass — the guide is smaller than ECS/CloudFront/CloudWatch.
- A detailed extraction prompt covering CIDR, routing, security groups, NACLs, NAT, VPC endpoints, peering, DNS, flow logs, IPv6, and quotas produced comprehensive single-pass coverage with no follow-up fetches needed.

### What Didn't Work
- Nothing notable; WebFetch on the VPC PDF succeeded directly.

---

## 2026-04-28 (EC2 Auto Scaling)

### What Worked
- EC2 Auto Scaling Developer Guide PDF (`as-dg.pdf`) is within the WebFetch limit and succeeded in a single pass.
- The document is structured around discrete feature areas (policies, lifecycle hooks, warm pools, instance refresh, mixed instances), making a single detailed extraction prompt sufficient for complete coverage.

### What Didn't Work
- Nothing notable; WebFetch on the Auto Scaling PDF succeeded directly.

---

## 2026-04-28 (RDS)

### What Worked
- RDS User Guide PDF exceeds the 10 MB WebFetch limit; falling back to 8 targeted HTML topic pages (Welcome, storage types, Multi-AZ, read replicas, automated backups, RDS Proxy, IAM auth, encryption) produced comprehensive coverage in three parallel rounds.
- The storage types page (`CHAP_Storage.html`) is the most operationally dense page in the RDS docs — it covers all five storage type comparisons, IOPS-to-storage ratios, autoscaling constraints, the magnetic deprecation deadline, and the instance-class throughput bottleneck in one place.
- Fetching the Proxy page revealed the `rdsproxyadmin` protection requirement (never modify/delete) which is easy to miss in practice.

### What Didn't Work
- Direct WebFetch of the RDS PDF (`rds-ug.pdf`) failed with `maxContentLength size of 10485760 exceeded`. Same 10 MB limit as all large AWS service PDFs.

### Changed Approach
- For RDS specifically, the storage types, Multi-AZ, and encryption pages are the highest-value starting points — they cover the most non-obvious operational gotchas (magnetic deprecation, instance IOPS cap, encryption immutability).

---

## 2026-04-29 (GitHub Actions)

### What Worked
- The GitHub Actions overview page is a clean, well-structured index — a single WebFetch call produced comprehensive coverage of all major features (OIDC, reusable workflows, matrix, concurrency, composite actions, environments) in one pass.
- Categorizing under `wiki/cicd/` is the right home; the page has direct relevance to this repo's Terraform CI/CD pipeline patterns.

---

## 2026-04-29 (Mermaid.js)

### What Worked
- The Mermaid intro page is dense and well-structured — a single WebFetch call produced the full diagram type inventory, integration methods, security model, and version info in one pass.
- Categorizing Mermaid under `wiki/concepts/` fits well; it's a cross-cutting documentation tool used across all wiki and docs pages in this repo.

---

## 2026-04-28 (Google SRE Book ToC)

### What Worked
- The Google SRE Book table of contents page is clean, structured HTML — a single WebFetch call produced the full chapter and part hierarchy with no follow-up needed.
- Categorizing this as `wiki/concepts/` (rather than `wiki/observability/`) was the right call: the book covers incident management, on-call, SLOs, overload handling, and cascading failures — all cross-cutting, not observability-specific.
- Synthesizing the ToC into a single dense reference page (patterns per chapter cluster rather than one entry per chapter) keeps the wiki page actionable without being a book index.
