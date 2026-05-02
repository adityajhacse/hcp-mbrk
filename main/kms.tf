resource "aws_kms_key" "example" {
  name = "kms-test-1"
  description = "KMS key for encrypting data"
  key_usage  = "ENCRYPT_DECRYPT"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = "kms:*"
        Resource = "*"
      }
    ]
  })
}




provider "aws" {
  region = "us-west-2"
}
