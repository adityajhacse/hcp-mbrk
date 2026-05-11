resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/hello-service"
  retention_in_days = 7
  kms_key_id        = aws_kms_key.hello.arn
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
