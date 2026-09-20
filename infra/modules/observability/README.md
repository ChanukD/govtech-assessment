# observability

Log groups for both services, an SNS topic, and the CloudWatch alarms that publish to
it.

## Design notes

- **Alarm targets are passed as names and ARN suffixes, not module objects.** That
  keeps this module free of dependencies on the modules it watches, which is what lets
  the ECS services consume the log groups it creates without a dependency cycle.
- **The DLQ alarm threshold is zero.** Any message there is a run that exhausted every
  retry.
- **Queue *age* is alarmed, not just depth.** Depth stays low if nothing is being
  enqueued either; a rising oldest-message age is what actually catches a worker that
  has stopped consuming.
- **API latency is alarmed on p99, not average.** The API only inserts a row and
  publishes a message, so the tail is where a problem shows first.
- **Both ECS services share one alarm pair** driven from a map, rather than the same
  two alarms written out twice.

## Simplifications

- **No subscriptions on the SNS topic.** Who gets paged differs per environment and
  would be an email address or chat webhook in tfvars. The topic exists and every alarm
  publishes to it; wiring a destination is one resource.
- **No dashboard and no composite alarms.**
- **Log groups use the default CloudWatch encryption,** not a CMK.

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.api_5xx](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.api_latency](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.api_unhealthy_hosts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.db_cpu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.db_free_storage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.dlq_not_empty](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.queue_backlog](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.service_cpu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.service_memory](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_sns_topic.alarms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| alb\_arn\_suffix | Load balancer ARN suffix, a dimension on the 5xx and latency alarms. | `string` | n/a | yes |
| api\_service\_name | API ECS service name, a dimension on its utilisation alarms. | `string` | n/a | yes |
| db\_instance\_identifier | Database instance identifier, a dimension on the database alarms. | `string` | n/a | yes |
| dlq\_name | Dead-letter queue name, a dimension on the DLQ depth alarm. | `string` | n/a | yes |
| ecs\_cluster\_name | ECS cluster name, a dimension on the service CPU and memory alarms. | `string` | n/a | yes |
| name\_prefix | Prefix applied to every resource name in this module. | `string` | n/a | yes |
| queue\_name | Main queue name, a dimension on the message-age alarm. | `string` | n/a | yes |
| service\_names | Logical service names to create log groups for. A set, so log groups are keyed by name in state. | `set(string)` | n/a | yes |
| target\_group\_arn\_suffix | Target group ARN suffix, a dimension on the healthy-host alarm. | `string` | n/a | yes |
| worker\_service\_name | Worker ECS service name, a dimension on its utilisation alarms. | `string` | n/a | yes |
| alarm\_evaluation\_periods | Consecutive periods a metric must breach before the alarm fires. | `number` | `2` | no |
| alarm\_period\_seconds | Metric period each evaluation covers. | `number` | `60` | no |
| api\_5xx\_threshold | Target-generated 5xx responses in one period before alarming. | `number` | `5` | no |
| api\_latency\_threshold\_seconds | p99 target response time in seconds before alarming. The API only inserts a row and publishes, so it should be far below this. | `number` | `2` | no |
| cpu\_utilisation\_threshold | Service CPU utilisation percentage before alarming. | `number` | `80` | no |
| db\_cpu\_threshold | Database CPU utilisation percentage before alarming. | `number` | `80` | no |
| db\_free\_storage\_threshold | Free storage in bytes before alarming. Defaults to roughly 2 GiB; the caller scales it to the allocated storage. | `number` | `2147483648` | no |
| dlq\_depth\_threshold | Messages on the dead-letter queue before alarming. Zero-tolerance: any DLQ message is a run that failed every retry. | `number` | `0` | no |
| log\_retention\_days | Retention applied to every log group this module creates. | `number` | `30` | no |
| memory\_utilisation\_threshold | Service memory utilisation percentage before alarming. | `number` | `80` | no |
| queue\_message\_age\_alarm | Age in seconds of the oldest queued message before alarming. Indicates the worker has stopped keeping up or stopped consuming. | `number` | `300` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| alarm\_names | Names of every alarm created, for reference in runbooks. |
| log\_group\_arns | Log group ARNs keyed by service name, used to scope the execution roles' write permissions. |
| log\_group\_names | Log group names keyed by service name, passed to the ECS task definitions. |
| sns\_topic\_arn | SNS topic every alarm in this module publishes to. |
<!-- END_TF_DOCS -->
