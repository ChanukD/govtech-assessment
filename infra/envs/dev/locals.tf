locals {
  # Every resource name in the stack starts with this.
  name_prefix = "${var.project}-${var.environment}"

  # Applied through provider default_tags, not per resource.
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
  }

  # AWS requires CLOUDFRONT-scoped WAF web ACLs in us-east-1, whatever region the rest
  # of the stack uses. Held as a local rather than a variable because it is an AWS
  # constraint, not a deployment choice.
  cloudfront_waf_region = "us-east-1"

  # Logical service names. Drives ECR repositories, log groups and the two ecs_service
  # module calls, so all three stay in step from one definition.
  service_names = toset(["api", "worker"])

  # The database secret name is fixed here rather than taken from the rds module
  # output, so that the IAM policies in the security module can be scoped to it
  # without creating a security -> rds -> security dependency cycle. See
  # db_secret_arn_pattern below and the note in infra/README.md.
  db_secret_name = "${local.name_prefix}/rds/credentials"

  # Secrets Manager appends a six-character suffix to every secret ARN, so an exact
  # ARN cannot be written ahead of creation. The trailing wildcard matches that suffix
  # and nothing else: this grants one named secret, not the account's secrets.
  db_secret_arn_pattern = format(
    "arn:%s:secretsmanager:%s:%s:secret:%s-*",
    data.aws_partition.current.partition,
    data.aws_region.current.region,
    data.aws_caller_identity.current.account_id,
    local.db_secret_name,
  )

  # Path pattern CloudFront forwards to the ALB rather than serving from S3.
  api_path_pattern = "/api/*"

  # The endpoint the WAF rate-based rule is scoped to: creating a run is the only
  # expensive, state-changing request in the API.
  waf_rate_limited_path = "/api/v1/runs"
}
