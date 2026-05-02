# HCP Terraform -> AWS Setup (Completed)

This document captures all setup steps completed to enable HCP Terraform workload identity access to AWS for workspace `hcp-mbrk`.

## 1) Environment details

- AWS account: `916657620953`
- AWS CLI profile used: `embark`
- Terraform Cloud/HCP org: `adityajhacse`
- HCP project: `ADITYA`
- HCP workspace: `hcp-mbrk`
- IAM role name: `HCP-terraform-role`
- IAM role ARN: `arn:aws:iam::916657620953:role/HCP-terraform-role`

## 2) Trust policy created

File: `hcp-terraform-trust-policy.json`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::916657620953:oidc-provider/app.terraform.io"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "app.terraform.io:aud": "aws.workload.identity"
        },
        "StringLike": {
          "app.terraform.io:sub": "organization:adityajhacse:project:ADITYA:workspace:hcp-mbrk:run_phase:*"
        }
      }
    }
  ]
}
```

## 3) IAM role created

Role created with:

```bash
aws iam create-role \
  --role-name HCP-terraform-role \
  --assume-role-policy-document file://hcp-terraform-trust-policy.json \
  --description "Role for HCP Terraform workload identity" \
  --profile embark
```

## 4) OIDC provider created (required)

The trust policy uses:

- `arn:aws:iam::916657620953:oidc-provider/app.terraform.io`

This provider did not exist initially and was created with:

```bash
aws iam create-open-id-connect-provider \
  --url https://app.terraform.io \
  --client-id-list aws.workload.identity \
  --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da0afd40f64 \
  --profile embark
```

## 5) Minimum KMS access policy attached

File: `hcp-terraform-kms-min-policy.json`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCreateAndReadKmsKey",
      "Effect": "Allow",
      "Action": [
        "kms:CreateKey",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
```

Attached as inline policy:

- Policy name: `HCPTerraformKMSMinimumAccess`

```bash
aws iam put-role-policy \
  --role-name HCP-terraform-role \
  --policy-name HCPTerraformKMSMinimumAccess \
  --policy-document file://hcp-terraform-kms-min-policy.json \
  --profile embark
```

## 6) HCP Terraform workspace configuration

In workspace `hcp-mbrk`, add these environment variables:

- `TFC_AWS_PROVIDER_AUTH=true`
- `TFC_AWS_RUN_ROLE_ARN=arn:aws:iam::916657620953:role/HCP-terraform-role`

These enable dynamic credentials via AWS workload identity federation.

## 7) Verification commands

### Verify caller identity

```bash
aws sts get-caller-identity --profile embark
```

### Verify OIDC provider

```bash
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::916657620953:oidc-provider/app.terraform.io \
  --profile embark
```

### Verify role trust policy

```bash
aws iam get-role --role-name HCP-terraform-role --profile embark
```

### Verify inline KMS policy

```bash
aws iam get-role-policy \
  --role-name HCP-terraform-role \
  --policy-name HCPTerraformKMSMinimumAccess \
  --profile embark
```

## 8) Optional permissions based on Terraform usage

If Terraform also manages aliases or key tags, add:

- `kms:CreateAlias`
- `kms:TagResource`

If Terraform uses key policy updates, grants, deletion scheduling, or other KMS lifecycle operations, expand permissions accordingly.
