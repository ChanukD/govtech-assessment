locals {
  identifier = "${var.name_prefix}-postgres"

  # The parameter group family needs the major version on its own, so a value like
  # "16.4" still resolves to "postgres16".
  major_version = split(".", var.engine_version)[0]
}

# Generated here and written straight to Secrets Manager. The value reaches the
# container at task start through the execution role, so it is never an input
# variable, never in tfvars, and never an output.
resource "random_password" "master" {
  length  = 32
  special = true

  # PostgreSQL connection strings and the RDS API both reject some punctuation in the
  # master password; this set is safe in both.
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db" {
  name        = var.secret_name
  description = "PostgreSQL credentials for ${local.identifier}"

  recovery_window_in_days = var.secret_recovery_window_days

  tags = {
    Name = var.secret_name
  }
}

# Written after the instance exists so the stored document carries the real endpoint,
# which means a consumer needs this secret and nothing else to connect.
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    engine   = "postgres"
    username = var.master_username
    password = random_password.master.result
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = aws_db_instance.main.db_name
  })
}

resource "aws_db_subnet_group" "main" {
  name        = "${var.name_prefix}-db"
  description = "Isolated subnets for ${local.identifier}"
  subnet_ids  = var.subnet_ids

  tags = {
    Name = "${var.name_prefix}-db"
  }
}

resource "aws_db_parameter_group" "main" {
  name        = "${var.name_prefix}-postgres${local.major_version}"
  family      = "postgres${local.major_version}"
  description = "Parameters for ${local.identifier}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = tostring(var.log_min_duration_statement_ms)
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "main" {
  identifier = local.identifier

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.master_username
  password = random_password.master.result
  port     = 5432

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.main.name
  vpc_security_group_ids = var.security_group_ids
  publicly_accessible    = false

  # Single-AZ is a deliberate simplification for this environment. See infra/README.md.
  multi_az = var.multi_az

  backup_retention_period = var.backup_retention_days
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = true

  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.identifier}-final"

  performance_insights_enabled = var.performance_insights_enabled
  monitoring_interval          = var.monitoring_interval_seconds

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = {
    Name = local.identifier
  }
}
