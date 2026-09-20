locals {
  queue_name = "${var.name_prefix}-${var.queue_name}"
  dlq_name   = "${local.queue_name}-dlq"
}

# Declared before the main queue because the redrive policy below references its ARN,
# which is also what makes Terraform create it first.
resource "aws_sqs_queue" "dlq" {
  name                      = local.dlq_name
  message_retention_seconds = var.dlq_message_retention_seconds
  sqs_managed_sse_enabled   = true

  tags = {
    Name = local.dlq_name
  }
}

resource "aws_sqs_queue" "main" {
  name                       = local.queue_name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = {
    Name = local.queue_name
  }
}

# Without this the DLQ would accept a redrive from any queue in the account.
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.main.arn]
  })
}
