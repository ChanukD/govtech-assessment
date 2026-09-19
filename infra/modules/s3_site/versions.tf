terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.65"

      # The web ACL is CLOUDFRONT-scoped, which AWS only accepts in us-east-1. The
      # caller must pass that provider in explicitly; this module declares no provider
      # blocks of its own.
      configuration_aliases = [aws.us_east_1]
    }
  }
}
