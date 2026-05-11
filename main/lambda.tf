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

resource "aws_lambda_function" "hello" {
  function_name    = "hello-lambda"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  kms_key_arn      = aws_kms_key.hello.arn
}
