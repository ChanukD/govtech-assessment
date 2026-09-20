data "aws_region" "current" {}

locals {
  name           = "${var.name_prefix}-${var.service_name}"
  container_name = var.service_name

  # A target group is what makes this service load-balanced. Everything conditional
  # below keys off this single fact rather than off the service's name.
  load_balanced = var.target_group_arn != null

  container_definition = {
    name        = local.container_name
    image       = var.image_uri
    essential   = true
    stopTimeout = var.stop_timeout_seconds

    portMappings = local.load_balanced ? [{
      containerPort = var.container_port
      protocol      = "tcp"
    }] : []

    # Map iteration is ordered by key, so the rendered definition is stable and does
    # not produce a spurious new task revision on every plan.
    environment = [
      for k, v in var.environment_variables : {
        name  = k
        value = v
      }
    ]

    secrets = [
      for k, v in var.secret_environment_variables : {
        name      = k
        valueFrom = v
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = var.log_group_name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = var.service_name
      }
    }
  }
}

resource "aws_ecs_task_definition" "this" {
  family                   = local.name
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  execution_role_arn = var.execution_role_arn
  task_role_arn      = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([local.container_definition])

  tags = {
    Name = local.name
  }
}

resource "aws_ecs_service" "this" {
  name            = local.name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  enable_execute_command = var.enable_execute_command

  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  # Only meaningful with a load balancer; null for a queue consumer.
  health_check_grace_period_seconds = local.load_balanced ? var.health_check_grace_period_seconds : null

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  # A failed deployment rolls back instead of leaving the service half-updated.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  dynamic "load_balancer" {
    for_each = local.load_balanced ? [var.target_group_arn] : []

    content {
      target_group_arn = load_balancer.value
      container_name   = local.container_name
      container_port   = var.container_port
    }
  }

  tags = {
    Name = local.name
  }

  lifecycle {
    # desired_count is managed here today, but ignoring it leaves room for an
    # autoscaling policy to own it later without fighting Terraform.
    ignore_changes = [desired_count]
  }
}
