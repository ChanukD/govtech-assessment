# Infrastructure

Terraform for the AWS architecture in [`docs/architecture.png`](../docs/architecture.png):
a React SPA behind CloudFront, a Python API on Fargate, an SQS handoff to a Fargate
worker, and PostgreSQL on RDS.

**This configuration has never been applied.** There is no state file, no AWS account
behind it, and no cost has been incurred. It is written to be read and statically
checked — see below for how to do that without credentials.

84 resources across 42 distinct types, in ten modules and one environment.

---

## Validating without AWS credentials

```bash
cd infra
./validate.sh
```

Runs four checks and exits non-zero if any of the first three fail:

| Check | What it proves |
| --- | --- |
| `terraform fmt -recursive -check` | Formatting is canonical |
| `terraform init -backend=false` + `validate` | Every reference, type and module contract resolves |
| `tflint --recursive` | No unused declarations, deprecated syntax or provider misuse |
| `trivy config` | Security posture; advisory only, see [Accepted scan findings](#accepted-scan-findings) |

Individual checks: `./validate.sh fmt | validate | lint | scan`.

The key flag is **`-backend=false`**. It initialises modules and providers only, so
Terraform never contacts S3, never acquires a lock, and never needs credentials.
`validate` is a static check and does not reach AWS either. Nothing here produces a
plan, so nothing can accidentally touch infrastructure.

Requires `terraform` (~> 1.9), and optionally `tflint`, `trivy` and `terraform-docs`.
Missing optional tools are skipped with a warning rather than failing the run. `tflint`
needs network access on its first run to fetch the AWS ruleset.

### Where state would live

[`envs/dev/backend.tf`](envs/dev/backend.tf) declares an S3 backend. On a real apply,
state would be written to `s3://datapipe-tfstate-ap-southeast-1/dev/pipeline/terraform.tfstate`,
locked by a `.tflock` object alongside it.

Locking uses **`use_lockfile = true`**, not `dynamodb_table`. The DynamoDB mechanism is
deprecated; S3 conditional writes now provide the same mutual exclusion without a
second resource to provision and pay for.

The state bucket is treated as **bootstrap infrastructure created out of band** — a
bucket cannot hold the state that creates it. In a larger setup this would be a small
separate configuration, or the backend would be partially configured and supplied per
environment with `-backend-config`.

---

## Layout

```text
infra/
  modules/
    network/         VPC, 3 subnet tiers x 2 AZs, route tables, VPC endpoints
    security/        Security groups, IAM roles and policies
    s3_site/         Static site bucket + CloudFront distribution + WAF web ACL
    s3_source/       Versioned bucket holding the pipeline input
    alb/             Load balancer, target group, listener
    ecs_service/     Generic Fargate service - instantiated twice
    sqs/             Run queue + DLQ + redrive policy
    rds/             Subnet group, parameter group, instance, credentials secret
    ecr/             Image repositories with lifecycle policies
    observability/   Log groups, alarms, SNS topic
  envs/dev/          The only environment. Wiring, variables and outputs.
  validate.sh        Static checks
```

Each module has its own README with a purpose line, design notes, and a generated
inputs/outputs table.

### Why it is split this way

**Modules are drawn around lifecycle and ownership, not around AWS service names.** A
module exists where a group of resources changes together, is reasoned about together,
or would be reviewed by the same person.

- **`security` holds every security group and IAM role** rather than distributing them
  into the modules that use them. Least privilege is a property of the system, not of
  any one component: the question "what can the API actually reach?" should be
  answerable by reading one file. It also means a permission change is reviewed as a
  permission change, not buried in a database or queue diff.
- **`ecs_service` is genuinely generic.** The API and the worker are two calls to the
  same module. Nothing in it branches on a service name; the only structural difference
  is whether a `target_group_arn` was passed, which makes the service load-balanced.
  Writing two near-identical modules would have meant every future change applied
  twice.
- **`network` owns the endpoints, `security` owns their rules.** The interface-endpoint
  security group is created in `network` but deliberately has no rules, because its
  ingress must reference the task security groups *by ID* rather than by CIDR. Since
  `security` needs `vpc_id` from `network`, putting both the group and its rules in one
  place would create a cycle. Splitting group from rules resolves it without weakening
  the rule.
- **`observability` takes names and ARN suffixes, not module objects.** That keeps it
  dependency-free with respect to the modules it watches, which is what lets it create
  the log groups the ECS services consume without another cycle.
- **`envs/dev` is wiring.** The only resources there are the ECS cluster and its
  capacity providers, which are shared by both services and so belong to the
  environment rather than to the per-service module.

### The one dependency cycle worth explaining

`rds` owns the credentials secret but needs the database security group from
`security`; `security` needs the secret's ARN to scope its IAM policy. That is circular.

It is broken by fixing the **secret name** in [`envs/dev/locals.tf`](envs/dev/locals.tf)
and passing it to both. The IAM policy is then scoped to
`arn:aws:secretsmanager:<region>:<account>:secret:<name>-*`. The trailing wildcard is
not laziness: Secrets Manager appends a six-character suffix, so the exact ARN cannot
be known before creation. The policy grants one named secret, not the account's
secrets.

---

## How this maps to the architecture diagram

Every numbered edge on [`docs/architecture.png`](../docs/architecture.png) has a
corresponding resource here.

| Diagram component | Module | Notes |
| --- | --- | --- |
| AWS WAF managed rules | `s3_site` | Web ACL in us-east-1 via a second provider |
| CloudFront | `s3_site` | Two origins: S3 and the ALB under `/api/*` |
| S3 — static site | `s3_site` | Private, Origin Access Control only |
| S3 — source data | `s3_source` | Versioned |
| Application Load Balancer | `alb` | Public subnets |
| ECS Fargate — API | `ecs_service` (api) | Private subnets, behind the target group |
| SQS run queue + DLQ | `sqs` | Standard, `maxReceiveCount` 3 |
| ECS Fargate — worker | `ecs_service` (worker) | Private subnets, no load balancer |
| RDS PostgreSQL | `rds` | Isolated subnets |
| VPC endpoints | `network` | S3 gateway; SQS, ECR API, ECR DKR, Logs, Secrets |
| Secrets Manager | `rds` | Generated password, never an input or output |
| CloudWatch | `observability` | Log groups, alarms, SNS topic |
| ECR | `ecr` | One repository per service |

Three things on the diagram are **intentionally not** in this environment: Multi-AZ on
the database, target-tracking autoscaling on the services, and the shared-secret header
that would stop the ALB being reached directly. All three are in the list below.

---

## Simplifications

Everything here is a decision with a reason, not an oversight. Each is also noted in
the README of the module it affects.

### Availability and scale

| Simplification | Reasoning | What production would do |
| --- | --- | --- |
| **Single-AZ database** | A standby doubles the cost of the most expensive component in a development environment. The subnet group still spans two AZs, so enabling it is a one-variable change. | `multi_az = true`; failover becomes automatic rather than a restore from backup |
| **`db.t4g.micro`, no read replica** | Sized for tens of runs a day against megabyte inputs. There is no read traffic to offload. | Size from measured load; add a replica only if reads actually compete with writes |
| **No ECS autoscaling** | `desired_count` is fixed at 2 API tasks and 1 worker. Autoscaling policies are meaningless without load to scale against. | Target-tracking on CPU for the API; queue-depth scaling on `ApproximateNumberOfMessagesVisible` for the worker |
| **No RDS Proxy** | Fargate tasks are long-lived and pool connections, so the total is bounded at plan time. RDS Proxy solves Lambda-style connection storms this design does not have. | Only if connection count becomes a real constraint |

### Edge and TLS

| Simplification | Reasoning | What production would do |
| --- | --- | --- |
| **No Route 53 zone or ACM certificate** | A custom domain needs a zone that exists outside this configuration. CloudFront's default certificate serves the SPA over HTTPS without one. | Hosted zone, us-east-1 certificate with DNS validation, `aliases` on the distribution |
| **ALB listens on HTTP** | Following from the above: with no certificate, there is no HTTPS listener to create. TLS terminates at CloudFront, so the unencrypted hop is edge-to-origin inside AWS. | ACM certificate on the ALB, HTTPS listener, redirect from 80 |
| **CloudFront bypass is a documented TODO** | Closing it properly needs a second REGIONAL web ACL on the ALB, a shared secret header, and rotation of both without dropping traffic. The ALB security group already admits only CloudFront's prefix list, which narrows but does not close it. | CloudFront VPC origins, making the ALB internal — this removes the problem structurally rather than papering over it |

### Operations

| Simplification | Reasoning | What production would do |
| --- | --- | --- |
| **No SNS subscriptions** | Who gets paged differs per environment. The topic exists and every alarm publishes to it. | An email, chat webhook or PagerDuty integration per environment |
| **No access logging** | ALB, CloudFront and both buckets have logging off; each needs a destination bucket with a delivery policy and lifecycle rules. | Central logging bucket with retention |
| **No VPC flow logs** | Not part of the architecture being represented, and needs a destination and delivery role to be useful. | Enabled to CloudWatch or S3 |
| **AWS-managed keys, not CMKs** | ECR, log groups, SNS, Performance Insights, the secret and both buckets use AWS-managed encryption. A CMK per service adds key administration and cost. | CMKs with rotation for regulated or personal data |
| **Enhanced monitoring off** | Avoids an extra IAM role and per-instance cost. Performance Insights is on, free at seven days. | Enabled at 15s or 30s granularity |
| **Dev is disposable** | `force_destroy`, `skip_final_snapshot` and a zero secret-recovery window are all driven from `local.is_disposable`, which is true only when `environment == "dev"`. | All three invert for staging and production |

### Not built

- **A second environment.** `envs/dev` is the only root module. Staging and production
  would be sibling directories reusing the same modules with different variables — the
  modules take no `environment` variable and contain no environment-specific logic.
- **A CI/CD pipeline.** No CodePipeline, CodeBuild or GitHub Actions workflow. Image
  tags are variables that CI would set per deployment.
- **Application resources.** Nothing here builds, pushes or deploys an image; the ECR
  repositories are empty and the services would not start until CI pushes to them.

---

## Conventions

**Naming.** Every resource is prefixed `${project}-${environment}`, built once in
`locals.tf`. No resource name is typed twice.

**Tagging.** `Project`, `Environment`, `ManagedBy` and `Owner` are applied through
provider `default_tags` and appear on no individual resource. Resources set only a
`Name` tag, and `Tier` where it aids navigation.

**No hardcoded identifiers.** No account ID, ARN, availability zone or subnet CIDR is
written down. They come from `aws_caller_identity`, `aws_partition`, `aws_region`,
`aws_availability_zones` and `cidrsubnet()`. The single exception is the string
`us-east-1` for the WAF provider alias, which is an AWS constraint rather than a
deployment choice and is commented as such.

**`for_each`, not `count`.** Every collection is keyed by name — subnets by AZ,
repositories and log groups by service, endpoints by service name. Removing one
therefore does not renumber the others in state. `count` is not used anywhere.

**Variables.** All 153 have a type and a description. Defaults exist only where one is
genuinely safe: `project`, `environment`, `owner` and both image tags have none.
Validation blocks cover CIDRs, environment names, instance classes, ports, Fargate
CPU/memory combinations and CloudWatch retention periods.

**Outputs.** 68 in total. The database endpoint and secret ARN are marked `sensitive`.
**No output exposes a credential in any form** — the generated password is written
straight to Secrets Manager and read back by nothing.

**Dependencies are implicit.** Ordering comes from attribute references. `depends_on`
appears three times, all in the S3 modules and all for orderings Terraform cannot infer
because the resources involved do not reference each other: twice so a bucket policy is
not written before its public access block exists, and once so lifecycle rules that act
on noncurrent versions are not applied before versioning is enabled.

**IAM is scoped to named ARNs.** One `Resource = "*"` exists, on
`ecr:GetAuthorizationToken`, which AWS rejects with any resource restriction. The
comment above it says so. The AWS-managed `AmazonECSTaskExecutionRolePolicy` was
deliberately not used because it grants its ECR and Logs actions on `*`.

**Least privilege between the two services.** The API can send to the queue and read
the database secret. It has **no S3 permission at all** — the queue message carries an
object key, not the payload, so the API never touches the source data. The worker can
receive, delete and extend visibility on the queue, read that one bucket, and read the
secret. Their execution roles are separate from their task roles and from each other.

**No secrets anywhere in the configuration.** `terraform.tfvars` holds no credential.
The database password is generated by `random_password` and written directly to Secrets
Manager; there is deliberately no password variable in the `rds` module to pass one in.

---

## Accepted scan findings

`trivy config` reports 16 findings, all of them deliberate. Each is listed in
[`.trivyignore`](.trivyignore) with its reasoning, so the scan runs clean while the
decisions stay visible and reviewable. The script treats trivy as advisory and does not
gate on it; `fmt`, `validate` and `tflint` are the gates.

One lint rule is disabled in [`.tflint.hcl`](.tflint.hcl): `terraform_required_version`,
which wants a version constraint in every module. Child modules here deliberately do
not pin one — the root module owns it, and a module that pins its own is harder to
reuse from a root on a different version.
