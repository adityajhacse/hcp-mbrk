provider "aws" {
  region = "us-west-2"
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_iam_policy_document" "kms_key_policy" {
  statement {
    sid    = "EnableRootPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogsUseOfTheKey"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.us-west-2.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:aws:logs:us-west-2:${data.aws_caller_identity.current.account_id}:log-group:/ecs/hello-service"
      ]
    }
  }
}

resource "aws_kms_key" "hello" {
  description             = "KMS key for Lambda/ECS hello resources"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_key_policy.json

  tags = {
    Name = "hello-kms-key"
  }
}

resource "aws_kms_alias" "hello" {
  name          = "alias/hello-service-kms"
  target_key_id = aws_kms_key.hello.key_id
}

resource "aws_iam_role" "ecs_task_execution" {
  name = "hello-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_kms" {
  name = "hello-ecs-task-kms-policy"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ]
      Resource = aws_kms_key.hello.arn
    }]
  })
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/hello-service"
  retention_in_days = 7
  kms_key_id        = aws_kms_key.hello.arn
}

resource "aws_security_group" "alb" {
  name        = "hello-alb-sg"
  description = "Allow HTTP traffic to ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs" {
  name        = "hello-ecs-sg"
  description = "Allow traffic from ALB to ECS task"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 5678
    to_port         = 5678
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8"]
  }
}

resource "aws_lb" "hello" {
  name               = "hello-ecs-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "hello" {
  name        = "hello-ecs-tg"
  port        = 5678
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    protocol = "HTTP"
    path     = "/"
  }
}

resource "aws_lb_listener" "hello" {
  load_balancer_arn = aws_lb.hello.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.hello.arn
  }
}

resource "aws_ecs_cluster" "hello" {
  name = "hello-ecs-cluster"
}

resource "aws_ecs_task_definition" "hello" {
  family                   = "hello-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "hello-service"
      image     = "hashicorp/http-echo:0.2.3"
      essential = true
      portMappings = [
        {
          containerPort = 5678
          hostPort      = 5678
          protocol      = "tcp"
        }
      ]
      command = [
        "-listen=:5678",
        "-text=Hello World from ECS Fargate"
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = "us-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "hello" {
  name            = "hello-service"
  cluster         = aws_ecs_cluster.hello.id
  task_definition = aws_ecs_task_definition.hello.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.hello.arn
    container_name   = "hello-service"
    container_port   = 5678
  }

  depends_on = [aws_lb_listener.hello]
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/hello_lambda.zip"

  source {
    content  = <<-EOT
      def handler(event, context):
          return {
              "statusCode": 200,
              "headers": {"Content-Type": "application/json"},
              "body": "{\\"message\\": \\"Hello World from Lambda\\"}"
          }
    EOT
    filename = "index.py"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "hello-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_kms" {
  name = "hello-lambda-kms-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ]
      Resource = aws_kms_key.hello.arn
    }]
  })
}

resource "aws_lambda_function" "hello" {
  function_name    = "hello-lambda"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  kms_key_arn      = aws_kms_key.hello.arn
}

resource "aws_apigatewayv2_api" "public_hello" {
  name          = "public-hello-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.public_hello.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.hello.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "hello" {
  api_id    = aws_apigatewayv2_api.public_hello.id
  route_key = "GET /hello"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.public_hello.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowExecutionFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.public_hello.execution_arn}/*/*"
}

resource "aws_sns_topic" "lambda_failure_alerts" {
  name = "lambda-failure-alerts"
}

resource "aws_sns_topic_subscription" "lambda_failure_email" {
  topic_arn = aws_sns_topic.lambda_failure_alerts.arn
  protocol  = "email"
  endpoint  = "project-channel-ssa-aaaaufd4vuz7igigrmq5pmposi@salesforce-sandbox2.org.slack.com"
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "hello-lambda-errors"
  alarm_description   = "Alarm when hello-lambda has invocation errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.lambda_failure_alerts.arn]
  ok_actions          = [aws_sns_topic.lambda_failure_alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.hello.function_name
  }
}

output "kms_key_arn" {
  value = aws_kms_key.hello.arn
}

output "ecs_service_name" {
  value = aws_ecs_service.hello.name
}

output "ecs_task_definition_arn" {
  value = aws_ecs_task_definition.hello.arn
}

output "ecs_public_url" {
  value = "http://${aws_lb.hello.dns_name}"
}

output "lambda_function_name" {
  value = aws_lambda_function.hello.function_name
}

output "public_apigateway_url" {
  value = aws_apigatewayv2_api.public_hello.api_endpoint
}

output "lambda_failure_sns_topic_arn" {
  value = aws_sns_topic.lambda_failure_alerts.arn
}
