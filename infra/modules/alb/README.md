# alb

Public Application Load Balancer, its API target group, and the listener that forwards
to it.

## Design notes

- **`target_type = "ip"`** because Fargate tasks are ENI-addressed, not instances.
- **`drop_invalid_header_fields` is on.** With two hops in front of the application,
  ambiguous headers are a request-smuggling vector.
- **`deregistration_delay` is short (30s).** The API returns 202 immediately, so there
  are no long-running requests to drain.

## Simplifications

- **HTTP listener only, on port 80.** TLS terminates at CloudFront and this environment
  provisions no ACM certificate, so there is no certificate to serve HTTPS with. The
  edge-to-origin hop is therefore unencrypted across the AWS network. Production would
  add an ACM certificate and an HTTPS listener, and redirect 80 to 443.
- **No access logs.** They would need an S3 bucket with a log-delivery policy, which is
  out of scope for this environment.

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [aws_lb.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name\_prefix | Prefix applied to every resource name in this module. | `string` | n/a | yes |
| security\_group\_ids | Security groups attached to the load balancer. | `list(string)` | n/a | yes |
| subnet\_ids | Public subnets the load balancer is placed in, one per AZ. | `list(string)` | n/a | yes |
| target\_port | Port on the targets that the listener forwards to. | `number` | n/a | yes |
| vpc\_id | VPC the target group is created in. | `string` | n/a | yes |
| deregistration\_delay\_seconds | How long the load balancer waits for in-flight requests to finish before deregistering a target. | `number` | `30` | no |
| enable\_deletion\_protection | Whether the load balancer refuses deletion. Off in dev so the environment stays disposable. | `bool` | `false` | no |
| health\_check\_interval\_seconds | Seconds between health checks. | `number` | `15` | no |
| health\_check\_path | Path the target group polls to decide whether a task is healthy. | `string` | `"/healthz"` | no |
| health\_check\_timeout\_seconds | Seconds to wait for a health check response before counting it as a failure. | `number` | `5` | no |
| healthy\_threshold | Consecutive successful checks before a target is considered healthy. | `number` | `2` | no |
| idle\_timeout\_seconds | How long an idle connection is held open. The API returns 202 immediately, so it does not need a long timeout. | `number` | `60` | no |
| listener\_port | Port the load balancer listens on. HTTP, because TLS terminates at CloudFront and this environment provisions no ACM certificate. | `number` | `80` | no |
| unhealthy\_threshold | Consecutive failed checks before a target is taken out of service. | `number` | `3` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the load balancer. |
| arn\_suffix | ARN suffix of the load balancer, the form CloudWatch metric dimensions require. |
| dns\_name | DNS name of the load balancer. Used as the CloudFront origin for /api/*. |
| listener\_arn | ARN of the listener. |
| target\_group\_arn | ARN of the API target group, passed to the API ECS service. |
| target\_group\_arn\_suffix | ARN suffix of the target group, for CloudWatch metric dimensions. |
| zone\_id | Hosted zone ID of the load balancer, for an alias record if a custom domain is added later. |
<!-- END_TF_DOCS -->
