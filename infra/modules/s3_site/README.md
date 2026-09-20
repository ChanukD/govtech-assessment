# s3_site

The static site bucket, the CloudFront distribution that fronts both it and the API,
and the WAF web ACL attached at the edge.

## Design notes

- **One distribution, two origins.** S3 serves the React build; `/api/*` is forwarded
  to the ALB. Because both are the same origin from the browser's point of view, the
  SPA calls the API as a relative path: no CORS, no preflight on mutating requests, one
  place to attach WAF.
- **The bucket is never public.** CloudFront reaches it through Origin Access Control,
  and the bucket policy trusts only this distribution by `AWS:SourceArn`.
- **API responses are not cached** (`Managed-CachingDisabled`), since they are per-run
  state and a cached run status would be stale by definition. Static assets use
  `Managed-CachingOptimized`.
- **403 and 404 from S3 return `/index.html` with a 200,** so client-side routes
  resolve to the SPA rather than an S3 error page.
- **This module takes a second provider.** CLOUDFRONT-scoped web ACLs are only accepted
  in `us-east-1`, so the caller passes `aws.us_east_1` through an explicit `providers`
  map. The module declares the alias via `configuration_aliases` and contains no
  `provider` block of its own.
- **The WAF rate limit is scoped to the trigger endpoint,** not applied globally.
  Polling for run status is frequent and legitimate and would trip a blanket limit; the
  scope-down statement matches `POST` to the run path only.

## Simplifications

- **No Route 53 zone and no ACM certificate.** The distribution uses the default
  `*.cloudfront.net` certificate, so there is no custom domain. Adding one means a
  hosted zone, a us-east-1 certificate with DNS validation, and `aliases` here.
- **The CloudFront-bypass rule is a documented TODO,** marked in `main.tf`. Closing it
  properly needs a second REGIONAL web ACL on the ALB, a shared secret header injected
  by CloudFront, and rotation of both without dropping traffic. The CloudFront-only
  prefix list on the ALB security group narrows the exposure but does not close it. The
  structural fix is CloudFront VPC origins, which make the ALB internal.
- **No access logging** on the distribution.

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudfront_distribution.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution) | resource |
| [aws_cloudfront_origin_access_control.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control) | resource |
| [aws_s3_bucket.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_ownership_controls.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_wafv2_web_acl.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| alb\_dns\_name | DNS name of the load balancer, used as the second CloudFront origin. | `string` | n/a | yes |
| name\_prefix | Prefix applied to every resource name in this module. | `string` | n/a | yes |
| alb\_origin\_port | Port CloudFront connects to on the load balancer. Must match the alb module's listener\_port. | `number` | `80` | no |
| api\_path\_pattern | Path pattern routed to the ALB origin instead of the S3 origin. Everything else is served from the bucket. | `string` | `"/api/*"` | no |
| default\_root\_object | Object returned for a request to the distribution root. | `string` | `"index.html"` | no |
| force\_destroy | Whether `terraform destroy` may delete the site bucket while it still holds objects. | `bool` | `false` | no |
| price\_class | Edge locations the distribution uses. | `string` | `"PriceClass_200"` | no |
| spa\_error\_response\_path | Object returned for 403 and 404 from the S3 origin, so client-side routes resolve to the SPA rather than an S3 error. | `string` | `"/index.html"` | no |
| waf\_managed\_rule\_groups | AWS-managed rule groups to attach, in evaluation order. Names are resolved against the AWS vendor. | `list(string)` | <pre>[<br/>  "AWSManagedRulesCommonRuleSet",<br/>  "AWSManagedRulesKnownBadInputsRuleSet",<br/>  "AWSManagedRulesAmazonIpReputationList"<br/>]</pre> | no |
| waf\_rate\_limit | Requests per five-minute window from one IP to the rate-limited path before WAF blocks that IP. | `number` | `100` | no |
| waf\_rate\_limited\_path | Path the rate-based rule is scoped to. Scoped rather than global so that polling for run status is not rate-limited alongside triggering runs. | `string` | `"/api/v1/runs"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bucket\_arn | ARN of the static site bucket. |
| bucket\_name | Name of the static site bucket. The React build is synced here. |
| distribution\_domain\_name | Domain name of the distribution. This is the application's public entry point. |
| distribution\_hosted\_zone\_id | CloudFront's hosted zone ID, for an alias record if a custom domain is added later. |
| distribution\_id | CloudFront distribution ID, needed to invalidate the cache after a deploy. |
| web\_acl\_arn | ARN of the CloudFront-scoped web ACL. |
<!-- END_TF_DOCS -->
