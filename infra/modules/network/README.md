# network

Creates the VPC and everything that decides where traffic can go: three subnet tiers
across two AZs, their route tables, and the VPC endpoints that replace a NAT gateway.

## Design notes

- **Subnet ranges are derived, never written down.** `cidrsubnet()` carves each tier
  from `vpc_cidr` at offsets 0, 10 and 20, so a tier can grow to ten AZs before ranges
  would collide and adding an AZ never renumbers existing subnets.
- **No NAT gateway.** The private tier reaches AWS services through a free S3 gateway
  endpoint and five interface endpoints. At this scale that is cheaper than a NAT
  gateway (~USD 32/month plus per-GB processing) and keeps the traffic off the public
  path entirely. The trade-off: anything *not* fronted by an endpoint is unreachable
  from the private subnets, so a new AWS dependency means a new endpoint.
- **The isolated tier has no routes at all** beyond `local`. The database cannot reach
  the internet and the internet cannot reach it.
- **One route table per tier, not per AZ.** Per-AZ tables only earn their keep once
  there is a per-AZ NAT gateway to point at, and there is none.
- **The interface-endpoint security group is created here but has no rules.** The
  `security` module owns its ingress so the rule can reference the task security groups
  by ID rather than by CIDR. Splitting it this way is what breaks the otherwise
  circular dependency between the two modules.

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [aws_internet_gateway.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_route.public_internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.isolated](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.isolated](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_security_group.vpc_endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.isolated](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.interface](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name\_prefix | Prefix applied to every resource name in this module. | `string` | n/a | yes |
| vpc\_cidr | CIDR block for the VPC. Subnet ranges are derived from it with cidrsubnet(), never written down. | `string` | n/a | yes |
| az\_count | Number of availability zones to spread each subnet tier across. | `number` | `2` | no |
| interface\_endpoint\_services | Service names to create interface VPC endpoints for, without the com.amazonaws.<region> prefix. These replace a NAT gateway for the private subnets. | `set(string)` | <pre>[<br/>  "sqs",<br/>  "ecr.api",<br/>  "ecr.dkr",<br/>  "logs",<br/>  "secretsmanager"<br/>]</pre> | no |
| subnet\_newbits | Bits added to the VPC prefix when carving subnets. 8 against a /16 yields /24 subnets. | `number` | `8` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| availability\_zones | Availability zone names the subnet tiers were placed in. |
| isolated\_subnet\_ids | Isolated subnet IDs, one per AZ. Hosts the database and has no route off the VPC. |
| private\_subnet\_ids | Private subnet IDs, one per AZ. Hosts the API and worker tasks. |
| public\_subnet\_ids | Public subnet IDs, one per AZ. Hosts the ALB only. |
| s3\_gateway\_prefix\_list\_id | Prefix list of the S3 gateway endpoint. The worker's egress rule targets this rather than a CIDR. |
| vpc\_cidr\_block | CIDR block of the VPC. |
| vpc\_endpoints\_security\_group\_id | Security group attached to the interface endpoints. Its ingress rules are owned by the security module. |
| vpc\_id | ID of the VPC. |
<!-- END_TF_DOCS -->
