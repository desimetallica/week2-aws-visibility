provider "aws" {
  region = var.aws_region
}


resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket = var.s3_bucket_name
  force_destroy = true
  
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs_versioning" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "cloudtrail_logs_ownership" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "cloudtrail_logs_policy" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_acl" "cloudtrail_logs_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.cloudtrail_logs_ownership]

  bucket = aws_s3_bucket.cloudtrail_logs.id
  acl    = "private"
}

resource "aws_cloudtrail" "main" {
  depends_on = [
    aws_s3_bucket_policy.cloudtrail_logs_policy
  ]
  name                          = var.aws_cloudtrail_name
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true
  event_selector {
    read_write_type           = "All"
    include_management_events = true
    data_resource {
      type   = "AWS::S3::Object"
      values = []
    }
  }
}

