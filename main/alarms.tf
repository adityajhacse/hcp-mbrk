resource "aws_sns_topic" "lambda_failure_alerts" {
  name = "lambda-failure-alerts"
}

resource "aws_sns_topic_subscription" "lambda_failure_email" {
  topic_arn = aws_sns_topic.lambda_failure_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.lambda_alarm_notifier.arn
}

data "archive_file" "lambda_alarm_notifier_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_alarm_notifier.zip"

  source {
    filename = "index.py"
    content  = <<-EOT
      import json
      import os
      import urllib.request
      import boto3

      _secret_cache = None

      def _get_webhook_url():
          global _secret_cache
          if _secret_cache:
              return _secret_cache

          secret_name = os.environ["SLACK_WEBHOOK_SECRET_NAME"]
          client = boto3.client("secretsmanager")
          response = client.get_secret_value(SecretId=secret_name)
          secret_raw = response.get("SecretString", "{}")
          secret_obj = json.loads(secret_raw)
          webhook_url = secret_obj["slack_webhook_url"]
          _secret_cache = webhook_url
          return webhook_url

      def _post_to_slack(payload):
          webhook_url = _get_webhook_url()
          req = urllib.request.Request(
              webhook_url,
              data=json.dumps(payload).encode("utf-8"),
              headers={"Content-Type": "application/json"},
              method="POST",
          )
          with urllib.request.urlopen(req, timeout=10) as resp:
              if resp.status >= 400:
                  raise RuntimeError(f"Slack webhook failed with status {resp.status}")

      def handler(event, context):
          records = event.get("Records", [])
          for record in records:
              msg = record.get("Sns", {}).get("Message", "")
              try:
                  alarm = json.loads(msg)
              except json.JSONDecodeError:
                  alarm = {"AlarmName": "Unknown", "NewStateValue": "ALARM", "NewStateReason": msg}

              state = alarm.get("NewStateValue", "ALARM")
              reason = alarm.get("NewStateReason", "No reason provided")
              region = alarm.get("Region", os.environ.get("AWS_REGION", "us-west-2"))
              state_change_time = alarm.get("StateChangeTime", "unknown-time")

              function_name = "unknown-lambda"
              trigger = alarm.get("Trigger", {})
              for dim in trigger.get("Dimensions", []):
                  if dim.get("name") == "FunctionName":
                      function_name = dim.get("value", "unknown-lambda")
                      break

              payload = {
                  "text": (
                      f":rotating_light: Lambda function *{function_name}* is *{state}* in `{region}`\n"
                      f"*Failure Time:* `{state_change_time}`\n"
                      f">{reason}"
                  )
              }
              _post_to_slack(payload)

          return {"statusCode": 200}
    EOT
  }
}

resource "aws_lambda_function" "lambda_alarm_notifier" {
  function_name    = "lambda-alarm-to-slack-notifier"
  role             = aws_iam_role.lambda_alarm_notifier_exec.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_alarm_notifier_zip.output_path
  source_code_hash = data.archive_file.lambda_alarm_notifier_zip.output_base64sha256
  timeout          = 15

  environment {
    variables = {
      SLACK_WEBHOOK_SECRET_NAME = data.aws_secretsmanager_secret.slack_webhook_url.name
    }
  }
}

resource "aws_lambda_permission" "allow_sns_to_invoke_notifier" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_alarm_notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.lambda_failure_alerts.arn
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "hello-lambda-errors"
  alarm_description   = "Alarm quickly when hello-lambda has invocation errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.lambda_failure_alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.hello.function_name
  }
}
