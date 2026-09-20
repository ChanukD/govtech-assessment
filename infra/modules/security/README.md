# security

Owns every security group and IAM role in the stack, so the relationships between
principals and the resources they can reach are readable in one place.

## Design notes

- **Internal traffic is always security-group-to-security-group.** No rule between
  components is expressed as a CIDR, so re-addressing the VPC cannot silently widen
  access. The two exceptions are both prefix lists, not CIDRs: CloudFront's
  origin-facing ranges on ALB ingress, and the S3 gateway endpoint on worker egress.
- **Nothing accepts `0.0.0.0/0`.** The ALB is reachable only from CloudFront's
  managed prefix list. That is narrower than a public ALB but does not by itself stop
  another CloudFront customer reaching it — see the shared-header TODO in `s3_site`.
- **Task roles and execution roles are separate.** The task role is what the
  application code can do; the execution role is what the ECS agent does on its behalf
  before the container starts. Application credentials therefore never carry image-pull
  or log-creation rights.
- **The API has no S3 permission at all.** The queue message carries an object key, not
  the payload, so the API never touches the source data. The worker gets `s3:GetObject`
  on that one bucket.
- **The execution policy is written out rather than using the AWS-managed
  `AmazonECSTaskExecutionRolePolicy`,** which grants its ECR and Logs actions on `*`.
  The only `Resource = "*"` here is `ecr:GetAuthorizationToken`, which AWS rejects with
  any resource restriction; the comment on that statement says so.
- **The database secret is scoped by name pattern** (`<name>-*`), because Secrets
  Manager appends a six-character suffix that cannot be known before creation. The name
  comes from the root module, which is what avoids a `security -> rds -> security`
  cycle.

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role.api_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.api_task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.worker_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.worker_task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.api_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.api_task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.worker_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.worker_task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_security_group.alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.worker](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.alb_to_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.api_to_database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.api_to_endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.worker_to_database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.worker_to_endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.worker_to_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.alb_from_cloudfront](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.api_from_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.database_from_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.database_from_worker](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.endpoints_from_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.endpoints_from_worker](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| api\_container\_port | Port the API listens on. The ALB is allowed to reach the API tasks on this port and no other. | `number` | n/a | yes |
| db\_secret\_arn\_pattern | ARN pattern of the database credentials secret, including the trailing wildcard that matches the suffix Secrets Manager appends. | `string` | n/a | yes |
| ecr\_repository\_arns | ARNs of the repositories the execution roles may pull images from. | `list(string)` | n/a | yes |
| log\_group\_arns | ARNs of the log groups the execution roles may write container logs to. | `list(string)` | n/a | yes |
| main\_queue\_arn | ARN of the run queue. The API may send to it; the worker may receive from it. | `string` | n/a | yes |
| name\_prefix | Prefix applied to every resource name in this module. | `string` | n/a | yes |
| s3\_gateway\_prefix\_list\_id | Prefix list of the S3 gateway endpoint, from the network module. The worker's S3 egress rule targets this rather than a CIDR. | `string` | n/a | yes |
| source\_bucket\_arn | ARN of the source-data bucket. Only the worker role is granted read access to it. | `string` | n/a | yes |
| vpc\_endpoints\_security\_group\_id | Security group of the interface VPC endpoints, created by the network module. This module owns its ingress rules so they can reference the task security groups by ID. | `string` | n/a | yes |
| vpc\_id | VPC the security groups are created in. | `string` | n/a | yes |
| alb\_listener\_port | Port the load balancer listens on. Must match the alb module's listener\_port. | `number` | `80` | no |
| alb\_source\_prefix\_list\_name | AWS-managed prefix list allowed to reach the ALB. Defaults to CloudFront's origin-facing ranges, so the ALB is not open to the whole internet. | `string` | `"com.amazonaws.global.cloudfront.origin-facing"` | no |
| db\_port | Port the database listens on. | `number` | `5432` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| alb\_security\_group\_id | Security group for the load balancer. |
| api\_execution\_role\_arn | Execution role the ECS agent uses to start API tasks: pull the image, write logs, inject the secret. |
| api\_security\_group\_id | Security group for the API tasks. |
| api\_task\_role\_arn | Task role the API container assumes. Send to the queue, read the database secret, nothing else. |
| database\_security\_group\_id | Security group for the database instance. |
| worker\_execution\_role\_arn | Execution role the ECS agent uses to start worker tasks. |
| worker\_security\_group\_id | Security group for the worker tasks. |
| worker\_task\_role\_arn | Task role the worker container assumes. Consume the queue, read the source bucket, read the database secret. |
<!-- END_TF_DOCS -->
