resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.subnet_ids
  security_groups    = var.security_group_ids

  idle_timeout               = var.idle_timeout_seconds
  enable_deletion_protection = var.enable_deletion_protection

  # Ambiguous headers are a request-smuggling vector once there are two hops in front
  # of the application.
  drop_invalid_header_fields = true

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}

resource "aws_lb_target_group" "api" {
  name        = "${var.name_prefix}-api"
  port        = var.target_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = var.deregistration_delay_seconds

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = var.health_check_interval_seconds
    timeout             = var.health_check_timeout_seconds
    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = var.unhealthy_threshold
  }

  tags = {
    Name = "${var.name_prefix}-api"
  }
}

# HTTP only. TLS terminates at CloudFront and this environment provisions no ACM
# certificate, so there is no HTTPS listener to create. See infra/README.md.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = var.listener_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
