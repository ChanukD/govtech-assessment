data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

module "network" {
  source = "../../modules/network"

  name_prefix = local.name_prefix
  vpc_cidr    = var.vpc_cidr
  az_count    = var.az_count
}

module "ecr" {
  source = "../../modules/ecr"

  name_prefix      = local.name_prefix
  repository_names = local.service_names
  max_image_count  = var.ecr_max_image_count
  force_delete     = local.is_disposable
}

module "sqs" {
  source = "../../modules/sqs"

  name_prefix                = local.name_prefix
  queue_name                 = "runs"
  visibility_timeout_seconds = var.queue_visibility_timeout_seconds
  max_receive_count          = var.queue_max_receive_count
}

module "s3_source" {
  source = "../../modules/s3_source"

  name_prefix   = local.name_prefix
  force_destroy = local.is_disposable
}

# Creates the log groups the ECS services write to, so it is wired before them. Its
# alarm targets are passed as names and ARN suffixes rather than module objects, which
# is what keeps that ordering possible.
module "observability" {
  source = "../../modules/observability"

  name_prefix        = local.name_prefix
  service_names      = local.service_names
  log_retention_days = var.log_retention_days

  ecs_cluster_name          = aws_ecs_cluster.main.name
  api_service_name          = "${local.name_prefix}-api"
  worker_service_name       = "${local.name_prefix}-worker"
  queue_name                = module.sqs.queue_name
  dlq_name                  = module.sqs.dlq_name
  alb_arn_suffix            = module.alb.arn_suffix
  target_group_arn_suffix   = module.alb.target_group_arn_suffix
  db_instance_identifier    = module.rds.instance_identifier
  queue_message_age_alarm   = var.queue_visibility_timeout_seconds * 10
  db_free_storage_threshold = var.db_allocated_storage * 1024 * 1024 * 1024 / 10
}

# Owns every security group and IAM role, so the relationships between principals and
# the resources they reach are readable in one place.
module "security" {
  source = "../../modules/security"

  name_prefix        = local.name_prefix
  vpc_id             = module.network.vpc_id
  api_container_port = var.api_container_port
  alb_listener_port  = var.alb_listener_port

  # The endpoint security group is created by the network module; its ingress rules
  # belong here, where they can reference the task security groups by ID.
  vpc_endpoints_security_group_id = module.network.vpc_endpoints_security_group_id
  s3_gateway_prefix_list_id       = module.network.s3_gateway_prefix_list_id

  source_bucket_arn     = module.s3_source.bucket_arn
  main_queue_arn        = module.sqs.queue_arn
  db_secret_arn_pattern = local.db_secret_arn_pattern
  ecr_repository_arns   = values(module.ecr.repository_arns)
  log_group_arns        = values(module.observability.log_group_arns)
}

module "rds" {
  source = "../../modules/rds"

  name_prefix        = local.name_prefix
  subnet_ids         = module.network.isolated_subnet_ids
  security_group_ids = [module.security.database_security_group_id]

  engine_version              = var.db_engine_version
  instance_class              = var.db_instance_class
  allocated_storage           = var.db_allocated_storage
  max_allocated_storage       = var.db_max_allocated_storage
  backup_retention_days       = var.db_backup_retention_days
  deletion_protection         = var.db_deletion_protection
  secret_name                 = local.db_secret_name
  skip_final_snapshot         = local.is_disposable
  secret_recovery_window_days = local.is_disposable ? 0 : 7
}

module "alb" {
  source = "../../modules/alb"

  name_prefix        = local.name_prefix
  vpc_id             = module.network.vpc_id
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.security.alb_security_group_id]
  target_port        = var.api_container_port
  listener_port      = var.alb_listener_port
  health_check_path  = "/healthz"
}

# One cluster shared by both services. It sits here rather than in ecs_service because
# that module is instantiated per service and the cluster is not.
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# Reachable from the ALB, publishes to the queue, never reads the source data.
module "api_service" {
  source = "../../modules/ecs_service"

  name_prefix  = local.name_prefix
  service_name = "api"
  cluster_arn  = aws_ecs_cluster.main.arn

  image_uri     = "${module.ecr.repository_urls["api"]}:${var.api_image_tag}"
  task_cpu      = var.api_task_cpu
  task_memory   = var.api_task_memory
  desired_count = var.api_desired_count

  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.security.api_security_group_id]
  task_role_arn      = module.security.api_task_role_arn
  execution_role_arn = module.security.api_execution_role_arn
  log_group_name     = module.observability.log_group_names["api"]

  # The load-balanced half of the generic module. The worker passes none of these.
  container_port                    = var.api_container_port
  target_group_arn                  = module.alb.target_group_arn
  health_check_grace_period_seconds = 60

  environment_variables = {
    APP_ENV       = var.environment
    SQS_QUEUE_URL = module.sqs.queue_url
    DB_HOST       = module.rds.address
    DB_PORT       = tostring(module.rds.port)
    DB_NAME       = module.rds.db_name
  }

  secret_environment_variables = {
    DB_USER     = "${module.rds.secret_arn}:username::"
    DB_PASSWORD = "${module.rds.secret_arn}:password::"
  }
}

# No inbound traffic and no load balancer. Reads the source bucket; the API does not.
module "worker_service" {
  source = "../../modules/ecs_service"

  name_prefix  = local.name_prefix
  service_name = "worker"
  cluster_arn  = aws_ecs_cluster.main.arn

  image_uri     = "${module.ecr.repository_urls["worker"]}:${var.worker_image_tag}"
  task_cpu      = var.worker_task_cpu
  task_memory   = var.worker_task_memory
  desired_count = var.worker_desired_count

  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.security.worker_security_group_id]
  task_role_arn      = module.security.worker_task_role_arn
  execution_role_arn = module.security.worker_execution_role_arn
  log_group_name     = module.observability.log_group_names["worker"]

  # Long enough for an in-flight message to finish rather than be abandoned on SIGTERM.
  stop_timeout_seconds = 60

  environment_variables = {
    APP_ENV       = var.environment
    SQS_QUEUE_URL = module.sqs.queue_url
    SOURCE_BUCKET = module.s3_source.bucket_name
    DB_HOST       = module.rds.address
    DB_PORT       = tostring(module.rds.port)
    DB_NAME       = module.rds.db_name
  }

  secret_environment_variables = {
    DB_USER     = "${module.rds.secret_arn}:username::"
    DB_PASSWORD = "${module.rds.secret_arn}:password::"
  }
}

# Takes the us-east-1 provider explicitly: its web ACL is CLOUDFRONT-scoped and AWS
# accepts those in that region only.
module "s3_site" {
  source = "../../modules/s3_site"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name_prefix           = local.name_prefix
  alb_dns_name          = module.alb.dns_name
  alb_origin_port       = var.alb_listener_port
  api_path_pattern      = local.api_path_pattern
  price_class           = var.cloudfront_price_class
  force_destroy         = local.is_disposable
  waf_rate_limit        = var.waf_trigger_rate_limit
  waf_rate_limited_path = local.waf_rate_limited_path
}
