
provider "aws" {
  region = var.aws_region
}

# Get current account number
data "aws_caller_identity" "current" {}

resource "aws_iam_group" "admins" {
  name = var.admin_group_name
}

resource "aws_iam_group" "developers" {
  name = var.developer_group_name
}

resource "aws_iam_group" "readonly" {
  name = var.readonly_group_name
}

data "aws_iam_policy_document" "admin" {
  statement {
    actions   = ["*"]
    resources = ["*"]
    effect    = "Allow"
  }
}

resource "aws_iam_policy" "admin_policy" {
  name        = "AdminPolicy"
  description = "Full admin access"
  policy      = data.aws_iam_policy_document.admin.json
}

data "aws_iam_policy_document" "developer" {
  statement {
    actions   = [
      "ec2:Describe*",
      "s3:List*",
      "s3:Get*",
      "s3:Put*",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:Get*",
      "dynamodb:PutItem",
      "lambda:InvokeFunction"
    ]
    resources = ["*"]
    effect    = "Allow"
  }
}

resource "aws_iam_policy" "developer_policy" {
  name        = "DeveloperPolicy"
  description = "Developer access"
  policy      = data.aws_iam_policy_document.developer.json
}

data "aws_iam_policy_document" "readonly" {
  statement {
    actions   = [
      "ec2:Describe*",
      "s3:List*",
      "s3:Get*",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:Get*"
    ]
    resources = ["*"]
    effect    = "Allow"
  }
}

resource "aws_iam_policy" "readonly_policy" {
  name        = "ReadOnlyPolicy"
  description = "Read-only access"
  policy      = data.aws_iam_policy_document.readonly.json
}

resource "aws_iam_group_policy_attachment" "admin_attach" {
  group      = aws_iam_group.admins.name
  policy_arn = aws_iam_policy.admin_policy.arn
}

resource "aws_iam_group_policy_attachment" "developer_attach" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.developer_policy.arn
}

resource "aws_iam_group_policy_attachment" "readonly_attach" {
  group      = aws_iam_group.readonly.name
  policy_arn = aws_iam_policy.readonly_policy.arn
}

resource "aws_iam_user" "alice" {
  name = var.admin_user_name
}

resource "aws_iam_user" "bob" {
  name = var.developer_user_name
}

resource "aws_iam_user" "carol" {
  name = var.readonly_user_name
}

resource "aws_iam_user_group_membership" "alice_admin" {
  user = aws_iam_user.alice.name
  groups = [aws_iam_group.admins.name]
}

resource "aws_iam_user_group_membership" "bob_developer" {
  user = aws_iam_user.bob.name
  groups = [aws_iam_group.developers.name]
}

resource "aws_iam_user_group_membership" "carol_readonly" {
  user = aws_iam_user.carol.name
  groups = [aws_iam_group.readonly.name]
}

resource "aws_iam_user_login_profile" "carol_console" {
  user    = aws_iam_user.carol.name
  # Optionally, set a password or let AWS generate one
}