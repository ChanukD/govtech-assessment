# s3_source

The versioned bucket holding the pipeline's input file.

## Design notes

- **Versioning is not optional.** The input is a change-data-capture changelog; a
  replaced object would make a completed run impossible to reproduce.
- **Bucket names are globally unique,** so the account ID and region are appended
  rather than relying on the project name being unclaimed.
- **Fully private,** with a public access block, `BucketOwnerEnforced` ownership, and a
  bucket policy that denies any non-TLS request.
- **Noncurrent versions expire after 30 days,** which bounds what versioning costs.

## Note on module placement

The required module layout has no home for the source-data bucket — `s3_site` is
explicitly the static site and its distribution. Rather than overload that module or
scatter bucket resources into the root, this separate module was added.

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [aws_s3_bucket.source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name\_prefix | Prefix applied to the bucket name. The account ID and region are appended to keep the name globally unique. | `string` | n/a | yes |
| abort\_incomplete\_multipart\_days | Days before an incomplete multipart upload is aborted and its parts reclaimed. | `number` | `7` | no |
| force\_destroy | Whether `terraform destroy` may delete a bucket that still holds objects. True only for disposable environments. | `bool` | `false` | no |
| noncurrent\_version\_expiration\_days | Days a superseded object version is retained. Versioning is always on — this bounds what it costs. | `number` | `30` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bucket\_arn | ARN of the source-data bucket, used to scope the worker's read policy. |
| bucket\_name | Name of the source-data bucket, passed to the worker as configuration. |
| bucket\_regional\_domain\_name | Regional domain name of the bucket. |
<!-- END_TF_DOCS -->
