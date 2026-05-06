resource "aws_kms_keyqqq" "example" {
  description = "KMS key for encrypting dev workspace"
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
