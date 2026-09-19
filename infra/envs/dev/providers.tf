provider "aws" {
  region = var.aws_region

  # Applied to every taggable resource in this root module and all child modules.
  # Individual resources set only a Name tag; they never repeat these four.
  default_tags {
    tags = local.common_tags
  }
}

# CloudFront-scoped WAF web ACLs must be created in us-east-1 regardless of where the
# rest of the stack lives. This alias exists solely for that resource and is passed
# explicitly into the s3_site module.
provider "aws" {
  alias  = "us_east_1"
  region = local.cloudfront_waf_region

  default_tags {
    tags = local.common_tags
  }
}
