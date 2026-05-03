resource "aws_kms_key" "example" {
  description = "KMS key for encrypting mbark"
  name = "fff"
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
