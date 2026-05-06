resource "aws_kms_key" "example" {
  description = "KMS key for encrypting dev workspace"
  key_usage  = "ENCRYPT_DECRYPT"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
     {  
        Effect = "Allow11"
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
