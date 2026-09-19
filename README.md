# Cloud-Native Data Transformation Pipeline

A full-stack application that lets a user trigger an asynchronous data transformation
pipeline and view its progress and output. This repository contains the AWS architecture
design, Terraform configuration, and a locally runnable implementation.

---

## Overview

The application has two workloads with very different characteristics: a **request path**
that must respond in milliseconds, and a **processing path** that runs for as long as the
data requires. The architecture exists to keep those apart.

The API accepts a trigger, records the intent, and hands off. A queue absorbs the handoff.
A worker performs the transformation on its own schedule. A relational database holds both
run state and transformed output, so the frontend can ask *"where is my run?"* and
*"what did it produce?"* through the same API without ever talking to the worker.

---

## Architecture

![AWS architecture](docs/architecture.png)

Editable source: [`docs/architecture.drawio`](docs/architecture.drawio) (diagrams.net, AWS
2019 icon set). Numbered edges on the diagram match the numbered steps below.

### Main components

| Component | Service | Responsibility |
|---|---|---|
| Edge | CloudFront + WAF | TLS, caching, one origin domain for SPA and API, filtering before traffic reaches the account |
| Static hosting | S3 (private, OAC) | Serves the React bundle; not publicly readable |
| Ingress | ALB, public subnets | Only internet-reachable component in the VPC |
| API | ECS Fargate, private subnets | Stateless FastAPI — accepts triggers, records run state, publishes to the queue, serves status and output |
| Queue | SQS standard + DLQ | Durable handoff; decouples request latency from processing time |
| Worker | ECS Fargate, private subnets | Consumes the queue, reads the source file, transforms, writes results |
| Source data | S3 (versioned) | Holds the input file; the worker reads it by key |
| Database | RDS PostgreSQL, isolated subnets | Single source of truth for run state and transformed records |
| Private connectivity | VPC endpoints (S3 gateway; SQS, ECR, Logs, Secrets interface) | Private subnets reach AWS services without a NAT gateway |
| Supporting | Secrets Manager, ECR, CloudWatch | Credentials, images, logs and alarms |

**Region:** `ap-southeast-1`. Nothing is region-specific except the CloudFront web ACL,
which AWS requires in `us-east-1`.

### Application and data flow

**Request path — synchronous, must be fast**

1. Browser requests the application over HTTPS. CloudFront is the only public entry point.
2. WAF inspects at the edge, before the request consumes compute in the account.
3. Static assets are served from S3 via Origin Access Control — the bucket has no public
   access policy.
4. `/api/*` is forwarded to the ALB as a second origin. One distribution for both origins
   means the SPA calls the API as a same-origin relative path: no CORS, one certificate.
5. The ALB forwards to Fargate API tasks in private subnets. The tasks have no public IP
   and accept traffic only from the ALB security group.
6. `POST /api/v1/runs` inserts a run row as `QUEUED`, publishes `{run_id, source_key}` to
   SQS, and returns `202 Accepted` with the run id. No transformation happens on the
   request thread — response time is one insert plus one publish, regardless of input size.

**Processing path — asynchronous**

7. The worker long-polls SQS and claims the run with a conditional update
   (`SET status='RUNNING' WHERE status='QUEUED'`), so a redelivered message cannot start a
   second execution.
8. It reads the source file from S3 by key.
9. It transforms, upserts the rows into PostgreSQL, and marks the run `SUCCEEDED` with its
   counters. On failure the message returns to the queue; after three receives it lands in
   the DLQ and the run is marked `FAILED`.
10. The frontend polls `GET /api/v1/runs/{run_id}`, then fetches
    `GET /api/v1/runs/{run_id}/records` once terminal.

The API and worker never talk directly. The database is the only state they share.

### The source data and the transformation

The sample file is not a flat dataset, and the design reflects that.

`records.csv` holds 50 rows of `id, record, timestamp`, where `record` is **base64-encoded
JSON**: `{object_id, action, type, diameter, geometry}`. Across those rows there are **10
distinct `object_id` values, each appearing five times** with increasing timestamps.
`action` is either `null` (upsert) or `"DELETE"` (tombstone). This is a **change-data-capture
changelog**, not a set of independent records.

The transformation replays the log rather than copying rows:

```
decode base64 → parse and validate JSON
  → order by (timestamp, id)
  → fold to latest state per object_id (last write wins)
  → drop objects whose final action is DELETE
  → derive segment_count, vertex_count, length_m, bbox from the WKT geometry
  → upsert keyed on object_id
```

Replaying the sample yields **10 objects: 1 deleted, 9 current.**

Two properties matter architecturally: it is a **pure fold over sorted events**, so it is
deterministic; and it is therefore **idempotent**, which is what makes at-least-once queue
delivery safe.

`length_m` is a Euclidean sum over the WKT vertices. Valid because the coordinates are in a
projected CRS in metres — the ranges (~30,000–49,000 E, ~20,000–39,000 N) are consistent
with SVY21. Geographic coordinates would need a geodesic calculation instead.

---

## Key design decisions

| Decision | Reasoning | Rejected alternative |
|---|---|---|
| Queue-based async | Survives instance replacement, gives retries, DLQ and visibility; API never holds data it isn't processing | In-process background task — dies with the instance, no retry, breaks with more than one API task |
| Message carries a key, not the payload | ~100 bytes; avoids the 256 KB SQS limit entirely and keeps the API free of data handling (its task role has no source-bucket read) | Embedding file contents, which forces the extended-client S3 offload anyway |
| SQS standard | Ordering is already in the payload — every event carries a timestamp and the transform sorts before folding | FIFO — caps throughput at 300 msg/s per group for information the data already contains |
| Idempotent worker | At-least-once delivery guarantees an eventual duplicate; conditional claim prevents double execution, upsert on `object_id` prevents duplicate rows | Assuming exactly-once, which SQS standard does not provide |
| One datastore | Run state and output can be joined in one query | DynamoDB for status — splits the data and forces application-side joins |
| PostgreSQL | Uniform relational output with filtering and pagination; leaves a path to PostGIS for spatial querying | Document store — no benefit for this shape |
| VPC endpoints, no NAT | S3 gateway endpoint is free; interface endpoints cost less than NAT at this scale and keep traffic off the public path | NAT gateway — ~USD 32/month plus per-GB processing |
| No RDS Proxy | Fargate tasks are long-lived and pool connections, so totals are bounded by `max_tasks × pool_size` at plan time | RDS Proxy solves Lambda-style connection storms, which this design does not have |
| One distribution, both origins | Removes CORS, one certificate, one place to attach WAF | Separate API subdomain — adds a preflight to every mutating request |

---

## Trade-offs

| Decision | Gained | Given up |
|---|---|---|
| Queue-based async | Durability, retries, independent scaling, DLQ visibility | Eventual consistency; at-least-once forces idempotency; more infrastructure |
| Fargate over Lambda | No 15-minute ceiling, no cold starts, connection pooling, local Compose mirrors production | Always-on cost, no scale-to-zero, images to build and store |
| Standard over FIFO | Higher throughput, simpler config | Ordering recovered from payload; duplicates handled in application logic |
| RDS over DynamoDB | Joins, familiar querying, PostGIS path | Instance to size and patch; connections are finite |
| Polling over push | Trivial, no persistent connections, works through any proxy | Wasted requests while idle; status latency bounded by poll interval |
| Public ALB behind CloudFront | Simple to provision | Needs a shared-secret header to prevent edge bypass |
| Single region | Simplicity, lower cost, data residency | No regional failover |

---

## Assumptions

1. **Scale:** tens of runs per day, input files in the order of megabytes. Instance sizing,
   task counts and poll intervals all follow from this.
2. **No authentication.** Production would add Cognito or OIDC and scope runs per user —
   an additive change to the current API.
3. **The source file is trusted** — a known, well-formed input in a controlled bucket.
   User uploads would need presigned URLs, size limits and content validation.
4. **Runs complete in seconds**, which justifies a 30-second visibility timeout and a
   2-second poll interval.
5. **Coordinates are projected, in metres.** Inferred from value ranges, not from an
   explicit CRS declaration in the data.
6. **Single environment.** Terraform represents development; staging and production reuse
   the same modules with different variables.

---

## Known limitations

Deliberate omissions with a stated reason, not oversights.

- **The ALB can be reached directly**, bypassing CloudFront and WAF. Mitigation: a shared
  secret header injected by CloudFront and enforced by a WAF rule on the ALB. The stronger
  fix is CloudFront VPC origins, making the ALB internal with no public listener.
- **Visibility timeout vs. processing time.** A transformation outliving the timeout is
  redelivered; the conditional claim prevents duplicate writes but wastes a worker. A
  `ChangeMessageVisibility` heartbeat would resolve it.
- **Polling does not scale** — request volume grows linearly with concurrent users. SSE or
  WebSockets are the production answer.
- **No backpressure on run creation.** An `Idempotency-Key` header handles accidental
  double submission; real rate limiting needs a WAF rate-based rule on the trigger endpoint.
- **Single-AZ database in the dev Terraform.** Multi-AZ is on the diagram; see the Terraform
  section for the full simplification list.

---

## Local implementation mapping

The local implementation uses no cloud services but mirrors the same shape, so the two are
one design rather than two.

| Concern | Local | AWS |
|---|---|---|
| Static hosting | Vite dev server | CloudFront + S3 (OAC) |
| API | `uvicorn` container | ALB + ECS Fargate |
| Queue | `runs` table polled with a conditional claim | SQS standard + DLQ |
| Worker | Separate Compose service | ECS Fargate, scaled on queue depth |
| Database | SQLite (WAL mode) | RDS PostgreSQL, Multi-AZ |
| Source data | `./data/records.csv` bind mount | S3, via gateway endpoint |
| Configuration | `.env` | SSM Parameter Store + Secrets Manager |

The local queue uses the same claim semantics SQS provides, expressed in SQL — moving to
SQS replaces one adapter, not the design.

Honest limitation: SQLite with two writing processes needs WAL mode and a busy timeout, and
will not survive meaningful write concurrency. Acceptable for a local demo; the first thing
that changes in a hosted environment.

---

## Potential improvements

1. **CloudFront VPC origins** — make the ALB internal and remove the bypass problem
   structurally.
2. **Server-sent events** for run status, replacing polling.
3. **Step Functions** if the pipeline grows past a single step — per-step retry and visible
   execution history, at the cost of moving logic out of application code.
4. **PostGIS** with a geometry column and spatial index, once anything queries the data
   spatially.
5. **Aurora Serverless v2** if load turns out spiky — higher unit cost for near-zero idle.
6. **Authentication and per-user run scoping.**

---

> Local setup, API documentation, Terraform and AI tool usage sections follow below.