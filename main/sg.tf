resource "aws_security_group" "alb" {
  name        = "hello-alb-sg"
  description = "Allow HTTP traffic to ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
  #  to_port     = 80
  #  protocol    = "tcp"
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
