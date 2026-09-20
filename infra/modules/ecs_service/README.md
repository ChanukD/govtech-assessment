# ecs_service

A single Fargate service: one task definition, one service, optionally behind a load
balancer. Instantiated twice by the dev environment — once as the API, once as the
worker — with no per-service variants of the module.

## Design notes

- **The load-balanced shape is opt-in and derived from one fact.** Passing
  `target_group_arn` makes the service load-balanced; everything conditional keys off
  that rather than off the service name. The API passes it, plus `container_port` and a
  health-check grace period. The worker passes none of them and gets a service with no
  load balancer, no port mapping and no grace period.
- **The pairing is enforced, not assumed.** A `target_group_arn` without a
  `container_port` fails validation rather than creating a target group with nothing to
  register.
- **`desired_count` is in `ignore_changes`.** It is managed here today, but ignoring it
  leaves room for an autoscaling policy to own it later without fighting Terraform on
  every apply.
- **Environment variables come from a map, secrets from a separate map.** Secret values
  are resolved by the ECS agent at task start and never enter Terraform state.

## Simplifications

- **No autoscaling policy.** `desired_count` is fixed. The architecture diagram shows
  target-tracking on the API and queue-depth scaling on the worker; both are omitted
  here and would be a separate `aws_appautoscaling_*` set of resources.

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [aws_ecs_service.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| cluster\_arn | ARN of the ECS cluster to run in. | `string` | n/a | yes |
| desired\_count | Number of tasks to run. Fixed — this module intentionally creates no autoscaling policy. | `number` | n/a | yes |
| execution\_role\_arn | Role assumed by the ECS agent to pull the image, write logs and resolve secrets. Deliberately separate from task\_role\_arn. | `string` | n/a | yes |
| image\_uri | Fully qualified container image URI including tag or digest. | `string` | n/a | yes |
| log\_group\_name | CloudWatch log group the container writes to. Created by the observability module. | `string` | n/a | yes |
| name\_prefix | Prefix applied to every resource name in this module. | `string` | n/a | yes |
| security\_group\_ids | Security groups attached to the task ENIs. | `list(string)` | n/a | yes |
| service\_name | Logical name of this service, for example api or worker. Combined with name\_prefix to name the service, task definition and container. | `string` | n/a | yes |
| subnet\_ids | Private subnets to place tasks in. | `list(string)` | n/a | yes |
| task\_cpu | Fargate CPU units for the task. | `number` | n/a | yes |
| task\_memory | Fargate memory in MiB. Must be a combination Fargate allows for the chosen task\_cpu. | `number` | n/a | yes |
| task\_role\_arn | Role assumed by the application code inside the container. | `string` | n/a | yes |
| container\_port | Port the container listens on. Null for services that accept no inbound traffic, such as a queue consumer. | `number` | `null` | no |
| cpu\_architecture | Fargate CPU architecture. ARM64 is cheaper per task but requires images built for it. | `string` | `"X86_64"` | no |
| deployment\_maximum\_percent | Upper bound on running tasks during a deployment, as a percentage of desired\_count. | `number` | `200` | no |
| deployment\_minimum\_healthy\_percent | Lower bound on running tasks during a deployment, as a percentage of desired\_count. | `number` | `100` | no |
| enable\_execute\_command | Whether ECS Exec is permitted into running tasks. Off by default; it is a debugging path into a private subnet. | `bool` | `false` | no |
| environment\_variables | Plain environment variables for the container. Never put credentials here — use secret\_environment\_variables. | `map(string)` | `{}` | no |
| health\_check\_grace\_period\_seconds | Grace period before load balancer health checks can kill a starting task. Only meaningful with a target group. | `number` | `null` | no |
| secret\_environment\_variables | Environment variables resolved from Secrets Manager or SSM at task start, as name => valueFrom ARN. The value never enters Terraform state. | `map(string)` | `{}` | no |
| stop\_timeout\_seconds | Grace period for the container to exit on SIGTERM. The worker uses this to finish an in-flight message rather than abandoning it. | `number` | `30` | no |
| target\_group\_arn | Target group to register tasks with. Null creates a service with no load balancer. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| container\_name | Container name inside the task definition, needed for ECS Exec and for load balancer registration. |
| service\_arn | ARN of the ECS service. |
| service\_name | Name of the ECS service. |
| task\_definition\_arn | ARN of the task definition revision this service currently runs. |
<!-- END_TF_DOCS -->
