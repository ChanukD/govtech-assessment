data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  bucket_name   = "${var.name_prefix}-site-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"
  s3_origin_id  = "s3-site"
  alb_origin_id = "alb-api"
}

# Managed policies, referenced by name so the IDs are not hardcoded.
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# Forwards everything except Host, which must stay the origin's own or the ALB will
# not match its rules.
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_s3_bucket" "site" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = {
    Name = local.bucket_name
  }
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# The bucket is never public. CloudFront reaches it through Origin Access Control,
# and the bucket policy below trusts only this distribution.
resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.name_prefix}-site-oac"
  description                       = "Origin Access Control for ${local.bucket_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_iam_policy_document" "site" {
  statement {
    sid    = "AllowCloudFrontRead"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    # Narrows the service principal to this one distribution, so another account's
    # CloudFront cannot read the bucket.
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.main.arn]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.site.arn,
      "${aws_s3_bucket.site.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site.json

  depends_on = [aws_s3_bucket_public_access_block.site]
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.name_prefix} SPA and API"
  default_root_object = var.default_root_object
  price_class         = var.price_class
  web_acl_id          = aws_wafv2_web_acl.main.arn

  origin {
    origin_id                = local.s3_origin_id
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  # Serving the API from the same distribution is what removes CORS: the SPA calls
  # /api/* as a same-origin relative path.
  origin {
    origin_id   = local.alb_origin_id
    domain_name = var.alb_dns_name

    custom_origin_config {
      http_port  = var.alb_origin_port
      https_port = 443

      # The ALB has no ACM certificate in this environment, so the edge-to-origin hop
      # is HTTP. See infra/README.md.
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  # API responses are per-run state; caching them would serve a stale run status.
  ordered_cache_behavior {
    path_pattern             = var.api_path_pattern
    target_origin_id         = local.alb_origin_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  # Client-side routes are not objects in the bucket, so S3's 403/404 become the SPA
  # entry point rather than an error page.
  dynamic "custom_error_response" {
    for_each = toset([403, 404])

    content {
      error_code         = custom_error_response.value
      response_code      = 200
      response_page_path = var.spa_error_response_path
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # No custom domain in this environment, so the default *.cloudfront.net
    # certificate is used. See infra/README.md.
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1"
  }

  tags = {
    Name = "${var.name_prefix}-distribution"
  }
}

# CLOUDFRONT-scoped ACLs are only accepted in us-east-1, which is why this module
# takes a second provider.
resource "aws_wafv2_web_acl" "main" {
  provider = aws.us_east_1

  name        = "${var.name_prefix}-web-acl"
  description = "Edge filtering for ${var.name_prefix}"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = { for i, name in var.waf_managed_rule_groups : name => i }

    content {
      name = rule.key
      # Managed groups occupy the low priorities; the rate-based rule sits above them.
      priority = rule.value + 1

      # The rule group decides for itself whether to block or count.
      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.key
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.key
        sampled_requests_enabled   = true
      }
    }
  }

  # Scoped to the trigger endpoint rather than applied globally: polling for run
  # status is frequent and legitimate, and would trip a blanket rate limit.
  rule {
    name     = "rate-limit-run-trigger"
    priority = length(var.waf_managed_rule_groups) + 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"

        scope_down_statement {
          and_statement {
            statement {
              byte_match_statement {
                search_string         = var.waf_rate_limited_path
                positional_constraint = "STARTS_WITH"

                field_to_match {
                  uri_path {}
                }

                text_transformation {
                  priority = 0
                  type     = "LOWERCASE"
                }
              }
            }

            statement {
              byte_match_statement {
                search_string         = "post"
                positional_constraint = "EXACTLY"

                field_to_match {
                  method {}
                }

                text_transformation {
                  priority = 0
                  type     = "LOWERCASE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-run-trigger"
      sampled_requests_enabled   = true
    }
  }

  # TODO: block requests that reach the ALB without passing through CloudFront.
  # CloudFront injects a secret header via custom_header on the ALB origin, and a
  # REGIONAL web ACL on the load balancer blocks any request missing it. That needs a
  # second web ACL, a secret to hold the header value, and rotation of both without
  # dropping traffic, so it is left out of this environment. The CloudFront-only
  # prefix list on the ALB security group (see the security module) narrows the
  # exposure but does not close it. The structural fix is CloudFront VPC origins,
  # which make the ALB internal and remove the bypass entirely.

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.name_prefix}-web-acl"
  }
}
