locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
  }

  # Whether this environment may be torn down without ceremony. Drives force_destroy,
  # final snapshots and secret recovery windows in one place instead of repeating the
  # environment check at each call site.
  is_disposable = var.environment == "dev"

  # AWS requires CLOUDFRONT-scoped web ACLs in us-east-1 whatever region the rest of
  # the stack uses. A constraint, not a deployment choice, so it is not a variable.
  cloudfront_waf_region = "us-east-1"

  service_names = toset(["api", "worker"])

  # Fixed here rather than taken from the rds module output, so the security module can
  # scope its IAM policy to this secret without creating a security -> rds -> security
  # dependency cycle.
  db_secret_name = "${local.name_prefix}/rds/credentials"

  # Secrets Manager appends a six-character suffix to every secret ARN, so an exact ARN
  # cannot be written before creation. The trailing wildcard matches that suffix and
  # nothing else.
  db_secret_arn_pattern = format(
    "arn:%s:secretsmanager:%s:%s:secret:%s-*",
    data.aws_partition.current.partition,
    data.aws_region.current.region,
    data.aws_caller_identity.current.account_id,
    local.db_secret_name,
  )

  api_path_pattern = "/api/*"

  # Creating a run is the only expensive, state-changing request in the API, so the
  # rate limit is scoped to it rather than applied to every path.
  waf_rate_limited_path = "/api/v1/runs"
}
