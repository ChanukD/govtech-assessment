# Remote state for the dev environment.
#
# State locking uses `use_lockfile`, which holds the lock as a conditional-write
# object (<key>.tflock) in the same bucket. The older `dynamodb_table` argument is
# deprecated and is deliberately not used here.
#
# The bucket itself is bootstrap infrastructure: it is created and versioned out of
# band, before this configuration runs, so it is not managed by this root module.
#
# `terraform init -backend=false` skips this block entirely, which is how the
# configuration is validated without AWS credentials (see infra/README.md).
terraform {
  backend "s3" {
    bucket       = "datapipe-tfstate-ap-southeast-1"
    key          = "dev/pipeline/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
