# sqs

The run queue, its dead-letter queue, and the redrive policy between them.

## Design notes

- **Standard, not FIFO.** Ordering is already carried in the payload — every event has
  a timestamp and the transformation sorts before folding — so FIFO would cap
  throughput at 300 msg/s per group to provide information the data already contains.
- **`maxReceiveCount = 3`.** After three receives a message is a genuine failure rather
  than a transient one, and belongs in the DLQ where it can be inspected.
- **The DLQ retains for 14 days, the main queue for 4.** A dead-lettered message is
  evidence and needs time to be investigated.
- **Long polling at 20s,** the maximum, which removes empty-receive churn from the
  worker.
- **A redrive *allow* policy is set on the DLQ.** Without it the DLQ would accept a
  redrive from any queue in the account.
- **`visibility_timeout` must exceed worst-case processing time.** At 30s it suits the
  sample workload; a slower transformation would be redelivered while still running.
  The idempotent worker makes that safe but wasteful — see the known limitations in the
  root README.

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [aws_sqs_queue.dlq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue_redrive_allow_policy.dlq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_redrive_allow_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name\_prefix | Prefix applied to every resource name in this module. | `string` | n/a | yes |
| queue\_name | Logical queue name, combined with name\_prefix. The dead-letter queue takes the same name with a -dlq suffix. | `string` | n/a | yes |
| dlq\_message\_retention\_seconds | How long a failed message survives on the dead-letter queue. Longer than the main queue, because a DLQ message is evidence and needs time to be investigated. | `number` | `1209600` | no |
| max\_receive\_count | Receives of one message before it is moved to the dead-letter queue. | `number` | `3` | no |
| message\_retention\_seconds | How long an unconsumed message survives on the main queue. | `number` | `345600` | no |
| receive\_wait\_time\_seconds | Long-poll duration. 20 is the maximum and the right value for a worker: it removes empty-receive churn. | `number` | `20` | no |
| visibility\_timeout\_seconds | How long a received message is hidden from other consumers. Must exceed the worst-case processing time or a slow run will be redelivered while it is still being worked. | `number` | `30` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| dlq\_arn | ARN of the dead-letter queue. |
| dlq\_name | Name of the dead-letter queue, for the depth alarm. |
| dlq\_url | URL of the dead-letter queue. |
| queue\_arn | ARN of the main run queue, used to scope the API and worker IAM policies. |
| queue\_name | Name of the main run queue, the form CloudWatch metric dimensions require. |
| queue\_url | URL of the main run queue, passed to the API and worker as configuration. |
<!-- END_TF_DOCS -->
