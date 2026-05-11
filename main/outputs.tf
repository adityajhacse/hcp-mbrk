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

output "lambda_alarm_notifier_name" {
  value = aws_lambda_function.lambda_alarm_notifier.function_name
}
