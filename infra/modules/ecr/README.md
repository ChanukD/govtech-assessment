# ecr

One container image repository per service, each with a lifecycle policy.

## Design notes

- **`for_each` over a set of names,** so repositories are keyed by service name in
  state. Adding a third service is a one-line change and does not renumber the others.
- **Tags are immutable by default,** so a deployed tag always refers to the same image.
- **The lifecycle policy expires untagged images first,** which means the retention
  count rule below it only ever counts images a deployment could actually reference.
- **AES256 encryption using the ECR-managed key.** A CMK would add cost and key
  management for no benefit at this sensitivity.

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [aws_ecr_lifecycle_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_lifecycle_policy) | resource |
| [aws_ecr_repository.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name\_prefix | Prefix applied to every repository name. | `string` | n/a | yes |
| repository\_names | Logical repository names to create, one per service. A set, so repositories are keyed by name in state rather than by list position. | `set(string)` | n/a | yes |
| encryption\_type | Encryption for images at rest. AES256 uses the ECR-managed key; KMS adds cost and key management for no benefit here. | `string` | `"AES256"` | no |
| force\_delete | Whether `terraform destroy` may delete a repository that still contains images. True only for disposable environments. | `bool` | `false` | no |
| image\_tag\_mutability | Whether tags can be overwritten. IMMUTABLE means a deployed tag always refers to the same image. | `string` | `"IMMUTABLE"` | no |
| max\_image\_count | Tagged images to retain per repository before the oldest are expired. | `number` | `10` | no |
| scan\_on\_push | Whether to scan images for vulnerabilities on push. | `bool` | `true` | no |
| untagged\_expiry\_days | Days before an untagged image is expired. Untagged images are build layers no deployment references. | `number` | `7` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| repository\_arns | Repository ARNs keyed by logical name, used to scope the execution roles' pull permissions. |
| repository\_names | Full repository names keyed by logical name. |
| repository\_urls | Repository URLs keyed by logical name, for CI to push to and for task definitions to pull from. |
<!-- END_TF_DOCS -->
