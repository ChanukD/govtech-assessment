# CloudFront's origin-facing ranges. Using this prefix list instead of 0.0.0.0/0 means
# the ALB is only reachable from the edge, not from the whole internet. It does not
# prevent a bypass by another CloudFront customer — see the shared-header TODO in the
# s3_site module for the remaining half of that control.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = var.alb_source_prefix_list_name
}

# Security groups
#
# Every rule between components references the peer security group by ID. No internal
# rule is written in terms of a CIDR, so re-addressing the VPC cannot silently widen
# access.

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb"
  description = "Load balancer. Ingress from CloudFront edge ranges only."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}

resource "aws_security_group" "api" {
  name        = "${var.name_prefix}-api"
  description = "API tasks. Ingress from the ALB only."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-api"
  }
}

resource "aws_security_group" "worker" {
  name        = "${var.name_prefix}-worker"
  description = "Worker tasks. No ingress: the worker pulls from the queue and is never called."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-worker"
  }
}

resource "aws_security_group" "database" {
  name        = "${var.name_prefix}-database"
  description = "Database. Ingress from the API and worker tasks only."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-database"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_cloudfront" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from CloudFront edge locations"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  ip_protocol       = "tcp"
  from_port         = var.alb_listener_port
  to_port           = var.alb_listener_port
}

resource "aws_vpc_security_group_egress_rule" "alb_to_api" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to API tasks"
  referenced_security_group_id = aws_security_group.api.id
  ip_protocol                  = "tcp"
  from_port                    = var.api_container_port
  to_port                      = var.api_container_port
}

resource "aws_vpc_security_group_ingress_rule" "api_from_alb" {
  security_group_id            = aws_security_group.api.id
  description                  = "Application traffic from the load balancer"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.api_container_port
  to_port                      = var.api_container_port
}

resource "aws_vpc_security_group_egress_rule" "api_to_endpoints" {
  security_group_id            = aws_security_group.api.id
  description                  = "SQS, Secrets Manager, ECR and Logs via interface endpoints"
  referenced_security_group_id = var.vpc_endpoints_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_egress_rule" "api_to_database" {
  security_group_id            = aws_security_group.api.id
  description                  = "Run state reads and writes"
  referenced_security_group_id = aws_security_group.database.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
}

resource "aws_vpc_security_group_egress_rule" "worker_to_endpoints" {
  security_group_id            = aws_security_group.worker.id
  description                  = "SQS, Secrets Manager, ECR and Logs via interface endpoints"
  referenced_security_group_id = var.vpc_endpoints_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

# S3 is a gateway endpoint, so the destination is its prefix list rather than a
# security group.
resource "aws_vpc_security_group_egress_rule" "worker_to_s3" {
  security_group_id = aws_security_group.worker.id
  description       = "Read source data through the S3 gateway endpoint"
  prefix_list_id    = var.s3_gateway_prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "worker_to_database" {
  security_group_id            = aws_security_group.worker.id
  description                  = "Write transformed output"
  referenced_security_group_id = aws_security_group.database.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
}

resource "aws_vpc_security_group_ingress_rule" "database_from_api" {
  security_group_id            = aws_security_group.database.id
  description                  = "PostgreSQL from the API"
  referenced_security_group_id = aws_security_group.api.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
}

resource "aws_vpc_security_group_ingress_rule" "database_from_worker" {
  security_group_id            = aws_security_group.database.id
  description                  = "PostgreSQL from the worker"
  referenced_security_group_id = aws_security_group.worker.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
}

# Rules on a security group the network module created. Owned here so they can name
# the task security groups instead of the VPC CIDR.
resource "aws_vpc_security_group_ingress_rule" "endpoints_from_api" {
  security_group_id            = var.vpc_endpoints_security_group_id
  description                  = "HTTPS from the API tasks"
  referenced_security_group_id = aws_security_group.api.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_worker" {
  security_group_id            = var.vpc_endpoints_security_group_id
  description                  = "HTTPS from the worker tasks"
  referenced_security_group_id = aws_security_group.worker.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

# IAM
#
# Task roles are what the application code can do. Execution roles are what the ECS
# agent can do on the task's behalf before the container starts. They are separate so
# that application credentials never carry image-pull or log-creation rights.

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "api_task" {
  name               = "${var.name_prefix}-api-task"
  description        = "Application role for the API container"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role" "worker_task" {
  name               = "${var.name_prefix}-worker-task"
  description        = "Application role for the worker container"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role" "api_execution" {
  name               = "${var.name_prefix}-api-execution"
  description        = "ECS agent role for starting API tasks"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role" "worker_execution" {
  name               = "${var.name_prefix}-worker-execution"
  description        = "ECS agent role for starting worker tasks"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# The API publishes the run and nothing more. It has no S3 permission at all: the
# message carries a key, so the API never touches the source data.
data "aws_iam_policy_document" "api_task" {
  statement {
    sid       = "PublishRunToQueue"
    actions   = ["sqs:SendMessage"]
    resources = [var.main_queue_arn]
  }

  statement {
    sid       = "ReadDatabaseCredentials"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn_pattern]
  }
}

data "aws_iam_policy_document" "worker_task" {
  statement {
    sid = "ConsumeRunQueue"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [var.main_queue_arn]
  }

  statement {
    sid       = "ReadSourceData"
    actions   = ["s3:GetObject"]
    resources = ["${var.source_bucket_arn}/*"]
  }

  statement {
    sid       = "ReadDatabaseCredentials"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn_pattern]
  }
}

resource "aws_iam_role_policy" "api_task" {
  name   = "${var.name_prefix}-api-task"
  role   = aws_iam_role.api_task.id
  policy = data.aws_iam_policy_document.api_task.json
}

resource "aws_iam_role_policy" "worker_task" {
  name   = "${var.name_prefix}-worker-task"
  role   = aws_iam_role.worker_task.id
  policy = data.aws_iam_policy_document.worker_task.json
}

# Written out rather than using the AWS-managed AmazonECSTaskExecutionRolePolicy,
# which grants its ECR and Logs actions on "*". This scopes them to the repositories
# and log groups this stack actually owns.
data "aws_iam_policy_document" "execution" {
  statement {
    # ecr:GetAuthorizationToken issues an account-wide token and accepts no resource
    # restriction: AWS rejects this action with anything other than "*".
    sid       = "AuthenticateToEcr"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PullImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = var.ecr_repository_arns
  }

  statement {
    sid = "WriteContainerLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    # Log streams are children of the group, so the ARN carries a trailing wildcard.
    resources = [for arn in var.log_group_arns : "${arn}:*"]
  }

  statement {
    # The agent, not the application, resolves secrets into the container environment.
    sid       = "InjectDatabaseCredentials"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn_pattern]
  }
}

resource "aws_iam_role_policy" "api_execution" {
  name   = "${var.name_prefix}-api-execution"
  role   = aws_iam_role.api_execution.id
  policy = data.aws_iam_policy_document.execution.json
}

resource "aws_iam_role_policy" "worker_execution" {
  name   = "${var.name_prefix}-worker-execution"
  role   = aws_iam_role.worker_execution.id
  policy = data.aws_iam_policy_document.execution.json
}
