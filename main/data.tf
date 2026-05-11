data "aws_caller_identity" "current" {}

data "aws_secretsmanager_secret" "slack_webhook_url" {
  name = "slack_webhook_url"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
