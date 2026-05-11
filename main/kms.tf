data "aws_iam_policy_document" "kms_key_policy" {
  statement {
    sid    = "EnableRootPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogsUseOfTheKey"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.us-west-2.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:aws:logs:us-west-2:${data.aws_caller_identity.current.account_id}:log-group:/ecs/hello-service"
      ]
    }
  }
}

resource "aws_kms_key" "hello" {
  description             = "KMS key for Lambda/ECS hello resources"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_key_policy.json

  tags = {
    Name = "hello-kms-key"
  }
}

resource "aws_kms_alias" "hello" {
  name          = "alias/hello-service-kms"
  target_key_id = aws_kms_key.hello.key_id
}
