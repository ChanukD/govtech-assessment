data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  # S3 bucket names are globally unique, so the account and region are appended rather
  # than relying on the project name alone being unclaimed.
  bucket_name = "${var.name_prefix}-source-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"
}

resource "aws_s3_bucket" "source" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = {
    Name = local.bucket_name
  }
}

# Versioning is not optional here: the input file is a changelog, and a replaced object
# would otherwise make a completed run impossible to reproduce.
resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket = aws_s3_bucket.source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.source]
}

data "aws_iam_policy_document" "source" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.source.arn,
      "${aws_s3_bucket.source.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "source" {
  bucket = aws_s3_bucket.source.id
  policy = data.aws_iam_policy_document.source.json

  # The public access block must be in place before a policy is attached, or the
  # policy write can be rejected.
  depends_on = [aws_s3_bucket_public_access_block.source]
}
