
provider "aws" {
  region = var.aws_region
}

# Get current account number
data "aws_caller_identity" "current" {}

#
#
# S3 Buckets
#
#
# S3 bucket for AWS Config logs
resource "aws_s3_bucket" "config_logs" {
  bucket = var.s3_bucket_name_config
  force_destroy = true
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket_versioning" "config_logs_versioning" {
  bucket = aws_s3_bucket.config_logs.id
  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "config_logs_ownership" {
  bucket = aws_s3_bucket.config_logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "config_logs_acl" {
  depends_on = [
    aws_s3_bucket_ownership_controls.config_logs_ownership
  ]
  bucket = aws_s3_bucket.config_logs.id
  acl    = "private"
}

resource "aws_s3_bucket_policy" "config_logs_policy" {
  bucket = aws_s3_bucket.config_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config_logs.arn
      },
      {
        Sid = "AWSConfigBucketExistenceCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = "s3:ListBucket"
        Resource = aws_s3_bucket.config_logs.arn
      },
      {
        Sid = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = "s3:PutObject"
        Resource = [
          "${aws_s3_bucket.config_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        ],
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}



#
# IAM Role for AWS Config
#
resource "aws_iam_role" "config_role" {
  name = var.aws_config_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "config_policy" {
  name = var.aws_config_policy_name
  role = aws_iam_role.config_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketAcl",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.config_logs.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.config_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
      },
      {
        Effect = "Allow"
        Action = [
          "config:Put*",
          "config:Get*",
          "config:Describe*",
          "config:Deliver*",
          "config:List*",
          "config:Delete*",
          "config:Batch*",
          "cloudtrail:DescribeTrails",
          "cloudtrail:GetTrailStatus",
          "iam:GetPasswordPolicy",
          "iam:GetAccountPasswordPolicy"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = "*"
      }
    ]
  })
}

#
# AWS Config Recorder and Delivery Channel
#
resource "aws_config_configuration_recorder" "main" {
  name     = var.aws_config_name
  role_arn = aws_iam_role.config_role.arn
  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "${var.aws_config_name}-delivery"
  s3_bucket_name = aws_s3_bucket.config_logs.bucket
  depends_on     = [
    aws_config_configuration_recorder.main
  ]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [
    aws_config_delivery_channel.main
  ]
}

#
# AWS Config Rules
#
resource "aws_config_config_rule" "cloudtrail_enabled" {
  name = "cloudtrail-enabled"
  maximum_execution_frequency = "One_Hour"
  source {
    owner             = "AWS"
    source_identifier = "CLOUD_TRAIL_ENABLED"
  }
  depends_on = [
    aws_config_configuration_recorder.main
  ]
}

resource "aws_config_config_rule" "s3_bucket_public_read_prohibited" {
  name = "s3-bucket-public-read-prohibited"
  maximum_execution_frequency = "One_Hour"
  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
  depends_on = [
    aws_config_configuration_recorder.main
  ]
}

resource "aws_config_config_rule" "iam_password_policy" {
  name = "iam-password-policy"
  maximum_execution_frequency = "One_Hour"
  source {
    owner             = "AWS"
    source_identifier = "IAM_PASSWORD_POLICY"
  }
  depends_on = [
    aws_config_configuration_recorder.main
  ]
}
